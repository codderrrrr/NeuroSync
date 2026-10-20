"""Longitudinal service: baselines, observations, and what a recording means.

The comparison rules themselves live in ``longitudinal``, which is pure. This
module owns the durable side: turning stored sessions into observations,
recomputing a patient's own reference, and recording the state one session
reached against it.
"""

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from neurosync.modules.exceptions import service as exception_service
from neurosync.modules.medication import service as medication_service
from neurosync.modules.medication.context import (
    EvidenceInputs,
    MedicationContextResult,
    assess_evidence_strength,
)
from neurosync.modules.medication.models import (
    EvidenceStrength,
    MedicationContext,
    MedicationEvent,
)
from neurosync.modules.medication.service import MedicationEventNotFoundError
from neurosync.modules.monitoring.errors import (
    ERR_MISSING_RESULT,
    ERR_NON_TAP_RECORDING,
    MonitoringError,
    UnknownMedicationEventError,
)
from neurosync.modules.monitoring.longitudinal import (
    FeatureValues,
    LongitudinalAssessment,
    Observation,
    assess_observation,
    build_baseline,
)

# The pure comparison type and the persisted row share a name; alias the pure
# one so a reader can tell a computed baseline from a stored one at a glance.
from neurosync.modules.monitoring.longitudinal import (
    PatientBaseline as BaselineSnapshot,
)
from neurosync.modules.monitoring.models import (
    BaselineConfidence,
    LongitudinalResult,
    MissingResultShapeError,
    MonitoringResult,
    MonitoringSession,
    PatientBaseline,
    SessionStatus,
    tap_recording_features,
)

logger = logging.getLogger(__name__)


def baseline_explanation(stored: PatientBaseline) -> str:
    """Describe how a stored baseline was built.

    The sentence itself belongs to the pure comparison layer, which owns the
    "how many observations, how many borderline" wording. This is the public
    seam the API renders it through, so a router never has to know that format
    and never reaches into a private helper to get it.
    """
    return _baseline_from_row(stored).explanation()


def _observation_from_row(monitoring_session: MonitoringSession) -> Observation:
    """Adapt one session and its stored result into a comparable observation.

    Only the duration-independent features are carried across, so sessions
    recorded under different assigned durations stay comparable.
    """
    result = monitoring_session.result
    if result is None:
        raise MonitoringError(ERR_MISSING_RESULT)
    try:
        taps = tap_recording_features(result)
    except MissingResultShapeError as exc:
        raise MonitoringError(ERR_NON_TAP_RECORDING) from exc
    longitudinal = monitoring_session.longitudinal
    return Observation(
        session_id=monitoring_session.id,
        quality=result.quality,
        values=FeatureValues(
            taps_per_second=taps.taps_per_second,
            mean_inter_tap_interval_ms=taps.mean_inter_tap_interval_ms,
            inter_tap_variability_ms=taps.inter_tap_variability_ms,
            longest_pause_ms=taps.longest_pause_ms,
        ),
        # Sessions recorded before this layer existed resolve to unknown rather
        # than being retrofitted with a context they never had.
        medication_context=MedicationContext(longitudinal.medication_context)
        if longitudinal is not None
        else MedicationContext.UNKNOWN,
    )


def _baseline_from_row(stored: PatientBaseline) -> BaselineSnapshot:
    """Adapt a stored baseline row back into the pure comparison type."""
    return BaselineSnapshot(
        observation_count=stored.observation_count,
        valid_observation_count=stored.valid_observation_count,
        borderline_observation_count=stored.borderline_observation_count,
        values=FeatureValues(
            taps_per_second=stored.taps_per_second,
            mean_inter_tap_interval_ms=stored.mean_inter_tap_interval_ms,
            inter_tap_variability_ms=stored.inter_tap_variability_ms,
            longest_pause_ms=stored.longest_pause_ms,
        ),
        confidence=BaselineConfidence(stored.confidence),
    )


async def list_observations(
    *,
    session: AsyncSession,
    patient_id: int,
    assessment_definition_id: int,
    exclude_session_id: int | None = None,
) -> list[Observation]:
    """Return this patient's past observations for one assessment, oldest first.

    Scoped to a single patient and assessment, so one patient's history can
    never contribute to another's baseline. ``exclude_session_id`` keeps the
    session being completed out of the history it is judged against.
    """
    statement = (
        select(MonitoringSession)
        .options(
            selectinload(MonitoringSession.result),
            selectinload(MonitoringSession.longitudinal).selectinload(
                LongitudinalResult.medication_event
            ),
        )
        .join(MonitoringResult, MonitoringResult.session_id == MonitoringSession.id)
        .where(
            MonitoringSession.patient_id == patient_id,
            MonitoringSession.assessment_definition_id == assessment_definition_id,
            MonitoringSession.status == SessionStatus.COMPLETED.value,
            # The comparison layer is defined over finger-tapping features, so
            # a canvas recording can never leak into a baseline as zeros.
            MonitoringResult.total_taps.is_not(None),
        )
        .order_by(MonitoringSession.completed_at, MonitoringSession.id)
        # The session being completed is already in the identity map holding a
        # pre-write copy, with its `result` still unloaded; without this the
        # query would hand that stale row back and the newest observation would
        # be silently dropped from the history.
        .execution_options(populate_existing=True)
    )
    if exclude_session_id is not None:
        statement = statement.where(MonitoringSession.id != exclude_session_id)

    completed = [
        monitoring_session
        for monitoring_session in await session.scalars(statement)
        if monitoring_session.result is not None
    ]
    return [_observation_from_row(s) for s in completed]


async def get_baseline(
    *,
    session: AsyncSession,
    patient_id: int,
    assessment_definition_id: int,
) -> PatientBaseline | None:
    """Return the stored baseline for one patient and assessment, if any."""
    return await session.scalar(
        select(PatientBaseline).where(
            PatientBaseline.patient_id == patient_id,
            PatientBaseline.assessment_definition_id == assessment_definition_id,
        )
    )


async def rebuild_baseline(
    *,
    session: AsyncSession,
    patient_id: int,
    assessment_definition_id: int,
    observations: list[Observation] | None = None,
) -> PatientBaseline | None:
    """Recompute and persist the baseline from the patient's stored history.

    ``observations`` lets a caller that has already loaded this patient's
    history hand it over instead of paying for a second identical query. The
    result is the same either way: the baseline is a median over a set, so it
    does not depend on the order the observations arrive in.

    The stored row is a cache of this computation, so re-running it against the
    same observations yields the same values. That is what makes a baseline
    explainable: it can always be reproduced from the sessions that built it.

    Returns ``None`` when the minimum-history rule is not met, in which case
    any previously stored baseline is left untouched.
    """
    if observations is None:
        observations = await list_observations(
            session=session,
            patient_id=patient_id,
            assessment_definition_id=assessment_definition_id,
        )
    baseline = build_baseline(observations)
    if baseline is None:
        return None

    stored = await get_baseline(
        session=session,
        patient_id=patient_id,
        assessment_definition_id=assessment_definition_id,
    )
    now = datetime.now(UTC)
    if stored is None:
        stored = PatientBaseline(
            patient_id=patient_id,
            assessment_definition_id=assessment_definition_id,
            created_at=now,
            updated_at=now,
        )
        session.add(stored)
    else:
        stored.updated_at = now

    stored.taps_per_second = baseline.values.taps_per_second
    stored.mean_inter_tap_interval_ms = baseline.values.mean_inter_tap_interval_ms
    stored.inter_tap_variability_ms = baseline.values.inter_tap_variability_ms
    stored.longest_pause_ms = baseline.values.longest_pause_ms
    stored.observation_count = baseline.observation_count
    stored.valid_observation_count = baseline.valid_observation_count
    stored.borderline_observation_count = baseline.borderline_observation_count
    stored.confidence = baseline.confidence.value
    await session.flush()
    return stored


@dataclass(frozen=True, slots=True)
class LongitudinalRecording:
    """What one just-completed session contributes to the longitudinal layer.

    Grouped into one value so ``record_longitudinal_result`` takes a single
    description of the recording instead of a long list of loose arguments,
    and so the medication context can be resolved from the same facts the
    comparison uses.
    """

    monitoring_session_id: int
    assessment_definition_id: int
    quality: str
    values: FeatureValues
    # When the session was completed. This is the reference point for any
    # reported dose, so the elapsed time is measured against the end of the
    # assessment rather than when the patient started tapping.
    completed_at: datetime
    # Reported by the patient; None means they attached no dose event.
    medication_event_id: int | None = None
    # Already resolved by the caller, which is the single place the medication
    # module is consulted. Passing the result in rather than an id keeps one
    # dose event from being fetched twice per completion.
    medication_context: MedicationContextResult = field(
        default_factory=lambda: MedicationContextResult(context=MedicationContext.UNKNOWN)
    )
    # The event the context came from, when there was one.
    medication_event: MedicationEvent | None = None


async def record_longitudinal_result(
    *,
    session: AsyncSession,
    patient_id: int,
    recording: LongitudinalRecording,
) -> tuple[LongitudinalResult, LongitudinalAssessment]:
    """Assess one completed session and persist its longitudinal result.

    Two baselines are involved and they are deliberately different:

    * The **comparison** baseline is built from *prior* sessions only, so the
      session being completed can never contribute to the reference it is
      judged against.
    * The **stored** baseline is refreshed from *all* usable observations,
      including the one just completed, so the persisted reference always
      reflects the patient's history as it now stands.

    Medication context is resolved first and recorded as *supporting*
    information only. It never changes the baseline, never changes the
    longitudinal state, and is never inferred when the patient supplied no
    event. Resolving it first is what lets the current observation carry its
    own context, so later sessions can count how much earlier history was
    recorded under the same conditions.
    """
    context = recording.medication_context
    event = recording.medication_event
    current = Observation(
        session_id=recording.monitoring_session_id,
        quality=recording.quality,
        values=recording.values,
        medication_context=context.context,
    )
    history = await list_observations(
        session=session,
        patient_id=patient_id,
        assessment_definition_id=recording.assessment_definition_id,
        exclude_session_id=recording.monitoring_session_id,
    )
    # Comparison baseline: strictly prior observations. The stored row is not
    # used as a fallback here, because it already includes the current session.
    comparison_baseline = build_baseline(history)
    assessment = assess_observation(
        observations=history,
        current=current,
        persisted_baseline=comparison_baseline,
    )

    # Stored baseline: every usable observation so far, this one included.
    # The history is already in hand, so it is reused rather than re-queried.
    stored_baseline = await rebuild_baseline(
        session=session,
        patient_id=patient_id,
        assessment_definition_id=recording.assessment_definition_id,
        observations=[*history, current],
    )

    comparable_count = assessment.comparable_history_count(context.context)
    result = LongitudinalResult(
        session_id=recording.monitoring_session_id,
        baseline_id=stored_baseline.id if stored_baseline is not None else None,
        state=assessment.state.value,
        usable_history_count=assessment.usable_history_count,
        baseline_confidence=(
            comparison_baseline.confidence.value if comparison_baseline is not None else None
        ),
        changed_features=assessment.changed_features or None,
        medication_event_id=event.id if event is not None else None,
        medication_context=context.context.value,
        minutes_since_medication=context.minutes_since,
        evidence_strength=_evidence_strength(
            assessment=assessment,
            current_is_usable=current.is_usable,
            comparison_baseline=comparison_baseline,
            comparable_count=comparable_count,
            medication_context=context.context,
        ).value,
        comparable_observation_count=comparable_count,
    )
    session.add(result)
    await session.flush()

    await _route_for_specialist_review(
        session=session,
        patient_id=patient_id,
        longitudinal_result=result,
        assessment_definition_id=recording.assessment_definition_id,
    )
    return result, assessment


async def _route_for_specialist_review(
    *,
    session: AsyncSession,
    patient_id: int,
    longitudinal_result: LongitudinalResult,
    assessment_definition_id: int,
) -> None:
    """Offer a freshly computed result to the specialist review queue.

    Runs inside a savepoint so routing is genuinely optional. The comparison
    that produced the longitudinal result is the clinical record; the queue
    entry is an addition to it. If routing fails the savepoint is rolled back
    and the recording is still completed, because a patient should not lose a
    completed assessment because a queue row could not be written.

    Only database failures are swallowed, and they are logged. A programming
    error is left to fail the request rather than quietly disappearing.
    """
    try:
        async with session.begin_nested():
            await exception_service.route_longitudinal_result(
                session=session,
                longitudinal_result=longitudinal_result,
                patient_id=patient_id,
                assessment_definition_id=assessment_definition_id,
            )
    except SQLAlchemyError:
        logger.exception(
            "Specialist review routing failed for longitudinal result %s",
            longitudinal_result.id,
        )


async def resolve_medication_context_for_recording(
    *,
    session: AsyncSession,
    patient_id: int,
    recording: LongitudinalRecording,
) -> tuple[MedicationContextResult, MedicationEvent | None]:
    """Attach the patient's reported dose, or record that there was none.

    Called once per completion, before anything is written, so a dose event
    belonging to another patient is rejected outright rather than degrading
    into "unknown" - which would read as the patient declining to say.

    The event is never chosen automatically. With no event id the context is
    ``unknown`` and nothing else is looked up, so a session the patient
    completed without medication information keeps exactly the meaning it had
    before this layer existed.
    """
    try:
        return await medication_service.resolve_context_for_session(
            session=session,
            patient_id=patient_id,
            assessment_at=recording.completed_at,
            medication_event_id=recording.medication_event_id,
        )
    except MedicationEventNotFoundError as exc:
        # Someone else's event, or one that no longer exists.
        raise UnknownMedicationEventError from exc


def _evidence_strength(
    *,
    assessment: LongitudinalAssessment,
    current_is_usable: bool,
    comparison_baseline: BaselineSnapshot | None,
    comparable_count: int,
    medication_context: MedicationContext,
) -> EvidenceStrength:
    """Describe how much supporting information this interpretation rests on.

    A description of how much was recorded, not a confidence probability.
    Medication context never inflates it: an unknown context can still reach
    ``moderate`` on the strength of the comparison alone, but never
    ``stronger``.
    """
    return assess_evidence_strength(
        inputs=EvidenceInputs(
            session_is_usable=current_is_usable,
            baseline_established=(
                assessment.baseline is not None and assessment.baseline.is_established
            ),
            baseline_confidence_is_full=(
                comparison_baseline is not None
                and comparison_baseline.confidence is BaselineConfidence.FULL
            ),
            usable_history_count=assessment.usable_history_count,
            comparable_observation_count=comparable_count,
            medication_context=medication_context,
        )
    )
