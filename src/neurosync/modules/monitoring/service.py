"""Monitoring use cases: catalog, plans, sessions, and results.

Every patient-scoped lookup is filtered by the ``patient_id`` derived from the
authenticated session, so an object that exists but belongs to someone else is
indistinguishable from one that does not exist. Use cases that write own their
transaction, matching the other modules.
"""

import logging
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime, time

from sqlalchemy import func, select
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
from neurosync.modules.monitoring.assessment_catalog import ASSESSMENT_CATALOG
from neurosync.modules.monitoring.features import extract_tap_features
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
    AssessmentDefinition,
    BaselineConfidence,
    LongitudinalResult,
    MonitoringPlan,
    MonitoringPlanItem,
    MonitoringResult,
    MonitoringSession,
    MonitoringSessionEvent,
    PatientBaseline,
    PlanStatus,
    SessionStatus,
)
from neurosync.modules.monitoring.quality import evaluate_quality
from neurosync.modules.monitoring.schemas import (
    AssessmentResponse,
    CompleteSessionRequest,
    PlanItemResponse,
    TapEventRequest,
    event_offsets_ms,
)

logger = logging.getLogger(__name__)


class MonitoringError(Exception):
    """Base class for monitoring domain errors."""


class UnsupportedAssessmentError(MonitoringError):
    """Raised when an assessment without a runner would become a patient task."""


class PlanNeedsAssessmentsMessage:
    """Message for plans created without any assessment."""

    MESSAGE = "A monitoring plan needs at least one assessment."


class UnknownAssessmentsMessage:
    """Message for plans referencing assessments outside the catalog."""

    @staticmethod
    def for_ids(definition_ids: list[int]) -> str:
        return f"Unknown assessment definition ids: {definition_ids}"


class UnassignableAssessmentsMessage:
    """Message for assessments a plan may not contain."""

    @staticmethod
    def for_slugs(slugs: list[str]) -> str:
        return f"Assessments without a runner cannot be assigned: {slugs}"


class MissingDefinitionMessage:
    """Message for a session whose assessment definition vanished."""

    MESSAGE = "The session's assessment definition is missing."


class MissingPlanItemMessage:
    """Message for a session whose plan item vanished."""

    MESSAGE = "The session's monitoring plan item is missing."


class MissingResultMessage:
    """Message for a completed session that has no stored result."""

    MESSAGE = "The session's recording result is missing."


class PlanNotFoundError(MonitoringError):
    """Raised when the patient has no active monitoring plan."""


class PlanItemNotFoundError(MonitoringError):
    """Raised when a plan item does not exist for this patient."""


class InactiveSessionError(MonitoringError):
    """Raised when completing a session that is not in progress."""


class SessionNotFoundError(MonitoringError):
    """Raised when a session does not exist for this patient."""


class InvalidEventDataError(MonitoringError):
    """Raised when a session's event stream is not a valid tap recording."""


class UnknownMedicationEventError(MonitoringError):
    """Raised when a session references a dose event the patient does not own.

    Surfacing this instead of silently dropping the context keeps the
    ownership boundary honest: another patient's event must not quietly
    become "no medication information" for this session.
    """


def _utc_today_start() -> datetime:
    """Return midnight today (UTC), the boundary for daily availability."""
    now = datetime.now(UTC)
    return datetime.combine(now.date(), time.min, tzinfo=UTC)


def resolve_item_duration_seconds(
    item: MonitoringPlanItem,
    definition: AssessmentDefinition,
) -> int:
    """Return the recording target for one plan item, in seconds.

    A doctor-assigned ``duration_seconds`` wins; otherwise the assessment's
    catalog default applies. This is the single rule for "how long should this
    patient record for", so the plan the client is shown and the quality
    evaluation of the recording that came back can never disagree.
    """
    return (
        item.duration_seconds
        if item.duration_seconds is not None
        else definition.default_duration_seconds
    )


async def get_assessment_catalog(session: AsyncSession) -> list[AssessmentDefinition]:
    """Return all catalog entries in a stable, seeded order."""
    statement = select(AssessmentDefinition).order_by(AssessmentDefinition.id)
    return list(await session.scalars(statement))


async def get_assessment_definition(
    session: AsyncSession,
    *,
    slug: str,
) -> AssessmentDefinition | None:
    """Return one catalog entry by slug, or ``None``."""
    return await session.scalar(
        select(AssessmentDefinition).where(AssessmentDefinition.slug == slug)
    )


async def seed_assessment_catalog(session: AsyncSession) -> None:
    """Insert any catalog entries missing from the database.

    The code catalog is authoritative; seeding is additive so re-running never
    edits or removes existing rows (patients may reference them).
    """
    existing_slugs = set(await session.scalars(select(AssessmentDefinition.slug)))
    for spec in ASSESSMENT_CATALOG:
        if spec.slug in existing_slugs:
            continue
        session.add(
            AssessmentDefinition(
                slug=spec.slug,
                title=spec.title,
                description=spec.description,
                instructions=spec.instructions,
                execution_type=spec.execution_type.value,
                default_duration_seconds=spec.default_duration_seconds,
                is_supported=spec.is_supported,
            )
        )
    await session.commit()


async def create_plan(  # noqa: PLR0913 - explicit arguments beat a config object
    *,
    session: AsyncSession,
    patient_id: int,
    title: str,
    assessment_definition_ids: list[int],
    doctor_id: int | None = None,
    status: PlanStatus = PlanStatus.ACTIVE,
    duration_seconds: int | None = None,
) -> MonitoringPlan:
    """Create a plan from catalog assessments, in the given order.

    Every assessment must exist in the catalog and be supported: a plan is a
    promise that the patient can execute each item, so an assessment without a
    runner can never be assigned. Draft plans keep the same rule at item level;
    publishing (activating) a draft re-checks every item. ``duration_seconds``
    optionally overrides each item's recording target (a doctor-controlled
    exercise length); ``None`` keeps the catalog default.
    """
    if not assessment_definition_ids:
        raise MonitoringError(PlanNeedsAssessmentsMessage.MESSAGE)

    definitions = list(
        await session.scalars(
            select(AssessmentDefinition).where(
                AssessmentDefinition.id.in_(assessment_definition_ids)
            )
        )
    )
    by_id = {definition.id: definition for definition in definitions}
    missing = [
        definition_id for definition_id in assessment_definition_ids if definition_id not in by_id
    ]
    if missing:
        raise PlanItemNotFoundError(UnknownAssessmentsMessage.for_ids(missing))

    unsupported = [
        definition.slug
        for definition_id in assessment_definition_ids
        if not (definition := by_id[definition_id]).is_supported
    ]
    if unsupported:
        raise UnsupportedAssessmentError(UnassignableAssessmentsMessage.for_slugs(unsupported))

    plan = MonitoringPlan(
        patient_id=patient_id,
        doctor_id=doctor_id,
        title=title,
        status=status.value,
    )
    session.add(plan)
    await session.flush()

    for position, definition_id in enumerate(assessment_definition_ids):
        session.add(
            MonitoringPlanItem(
                plan_id=plan.id,
                assessment_definition_id=definition_id,
                position=position,
                duration_seconds=duration_seconds,
            )
        )
    await session.commit()
    return plan


async def get_patient_plan(
    *,
    session: AsyncSession,
    patient_id: int,
) -> tuple[MonitoringPlan, list[PlanItemResponse]]:
    """Return the patient's active plan with availability per item.

    ``completed_today`` counts sessions finished since midnight UTC so the
    client can show the next available assessment without deciding anything
    itself.
    """
    plan = await session.scalar(
        select(MonitoringPlan)
        .where(
            MonitoringPlan.patient_id == patient_id,
            MonitoringPlan.status == PlanStatus.ACTIVE.value,
        )
        .order_by(MonitoringPlan.created_at.desc(), MonitoringPlan.id.desc())
        .limit(1)
    )
    if plan is None:
        raise PlanNotFoundError

    items = list(
        await session.scalars(
            select(MonitoringPlanItem)
            .where(MonitoringPlanItem.plan_id == plan.id)
            .order_by(MonitoringPlanItem.position)
        )
    )

    # One grouped query for completion counts across all items.
    day_start = _utc_today_start()
    counts_rows = await session.execute(
        select(
            MonitoringSession.plan_item_id,
            func.count(MonitoringSession.id),
        )
        .where(
            MonitoringSession.patient_id == patient_id,
            MonitoringSession.status == SessionStatus.COMPLETED.value,
            MonitoringSession.completed_at >= day_start,
        )
        .group_by(MonitoringSession.plan_item_id)
    )
    completed_today = dict(counts_rows.all())

    definition_ids = [item.assessment_definition_id for item in items]
    definitions = {
        definition.id: definition
        for definition in await session.scalars(
            select(AssessmentDefinition).where(AssessmentDefinition.id.in_(definition_ids))
        )
    }

    item_responses = [
        PlanItemResponse(
            id=item.id,
            assessment=AssessmentResponse.model_validate(
                definitions[item.assessment_definition_id]
            ),
            position=item.position,
            completed_today=completed_today.get(item.id, 0),
            duration_seconds=resolve_item_duration_seconds(
                item, definitions[item.assessment_definition_id]
            ),
        )
        for item in items
    ]
    return plan, item_responses


async def get_plan_item_for_patient(
    *,
    session: AsyncSession,
    patient_id: int,
    plan_item_id: int,
) -> MonitoringPlanItem:
    """Return the plan item when it belongs to one of this patient's plans."""
    item = await session.scalar(
        select(MonitoringPlanItem)
        .join(MonitoringPlan, MonitoringPlan.id == MonitoringPlanItem.plan_id)
        .where(
            MonitoringPlanItem.id == plan_item_id,
            MonitoringPlan.patient_id == patient_id,
        )
    )
    if item is None:
        raise PlanItemNotFoundError
    return item


async def start_session(
    *,
    session: AsyncSession,
    patient_id: int,
    plan_item_id: int,
) -> MonitoringSession:
    """Open an in-progress session for one of the patient's plan items."""
    item = await get_plan_item_for_patient(
        session=session,
        patient_id=patient_id,
        plan_item_id=plan_item_id,
    )
    definition = await session.get(AssessmentDefinition, item.assessment_definition_id)
    if definition is None or not definition.is_supported:
        # A plan can only contain supported assessments, so reaching this guard
        # means the catalog changed under us; fail loudly rather than hand the
        # patient a task no runner can perform.
        raise UnsupportedAssessmentError(
            UnassignableAssessmentsMessage.for_slugs([str(item.assessment_definition_id)])
        )

    monitoring_session = MonitoringSession(
        patient_id=patient_id,
        plan_id=item.plan_id,
        plan_item_id=item.id,
        assessment_definition_id=item.assessment_definition_id,
        status=SessionStatus.IN_PROGRESS.value,
        started_at=datetime.now(UTC),
    )
    session.add(monitoring_session)
    await session.commit()
    # Re-read with the result relationship eagerly loaded: AsyncSession never
    # lazy-loads relationships implicitly, so the caller can serialize the
    # returned object without triggering IO.
    return await get_session_for_patient(
        session=session,
        patient_id=patient_id,
        monitoring_session_id=monitoring_session.id,
    )


class NonMonotonicOffsetsMessage:
    """Message for event streams whose offsets go backwards."""

    MESSAGE = "Event offsets must be non-decreasing."


def _to_tap_offsets(events: list[TapEventRequest]) -> list[int]:
    """Validate the raw event stream and reduce it to tap offsets."""
    try:
        offsets = event_offsets_ms(events)
    except ValueError as exc:
        raise InvalidEventDataError(str(exc)) from exc
    if sorted(offsets) != offsets:
        raise InvalidEventDataError(NonMonotonicOffsetsMessage.MESSAGE)
    return offsets


# ------------------------------------------------- longitudinal monitoring


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
        raise MonitoringError(MissingResultMessage.MESSAGE)
    longitudinal = monitoring_session.longitudinal
    return Observation(
        session_id=monitoring_session.id,
        quality=result.quality,
        values=FeatureValues(
            taps_per_second=result.taps_per_second,
            mean_inter_tap_interval_ms=result.mean_inter_tap_interval_ms,
            inter_tap_variability_ms=result.inter_tap_variability_ms,
            longest_pause_ms=result.longest_pause_ms,
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


async def complete_session(
    *,
    session: AsyncSession,
    patient_id: int,
    monitoring_session_id: int,
    payload: CompleteSessionRequest,
) -> tuple[MonitoringSession, MonitoringResult | None]:
    """Persist raw events, derive the result, and close the session.

    The event stream is stored exactly as captured; everything else in the
    result is derived deterministically from it. Completing twice fails
    explicitly instead of duplicating results.
    """
    monitoring_session = await get_session_for_patient(
        session=session,
        patient_id=patient_id,
        monitoring_session_id=monitoring_session_id,
    )
    if monitoring_session.status != SessionStatus.IN_PROGRESS.value:
        raise InactiveSessionError

    offsets = _to_tap_offsets(payload.events)
    features = extract_tap_features(offsets)
    definition = await session.get(
        AssessmentDefinition,
        monitoring_session.assessment_definition_id,
    )
    if definition is None:
        raise MonitoringError(MissingDefinitionMessage.MESSAGE)
    item = await session.get(MonitoringPlanItem, monitoring_session.plan_item_id)
    if item is None:
        raise MonitoringError(MissingPlanItemMessage.MESSAGE)
    # Judge the recording against the duration the plan actually asked for, not
    # the catalog default: a patient who complies with a longer assignment must
    # not be recorded as `invalid` for running past the shorter default.
    target_ms = resolve_item_duration_seconds(item, definition) * 1000
    quality = evaluate_quality(features=features, target_duration_ms=target_ms)

    now = datetime.now(UTC)
    # Classify the reported dose before writing anything, and do it exactly
    # once. Resolving here rather than inside the longitudinal step both
    # rejects another patient's event outright - instead of degrading it into
    # "no medication information" - and hands the result forward instead of
    # fetching the same event twice.
    recording = LongitudinalRecording(
        monitoring_session_id=monitoring_session.id,
        assessment_definition_id=monitoring_session.assessment_definition_id,
        quality=quality.value,
        values=FeatureValues(
            taps_per_second=features.taps_per_second,
            mean_inter_tap_interval_ms=features.mean_inter_tap_interval_ms,
            inter_tap_variability_ms=features.inter_tap_variability_ms,
            longest_pause_ms=features.longest_pause_ms,
        ),
        completed_at=now,
        medication_event_id=payload.medication_event_id,
    )
    context, event = await resolve_medication_context_for_recording(
        session=session,
        patient_id=patient_id,
        recording=recording,
    )

    for offset in offsets:
        session.add(
            MonitoringSessionEvent(
                session_id=monitoring_session.id,
                event_type="tap",
                offset_ms=offset,
            )
        )
    result = MonitoringResult(
        session_id=monitoring_session.id,
        total_taps=features.total_taps,
        duration_ms=features.duration_ms,
        mean_inter_tap_interval_ms=features.mean_inter_tap_interval_ms,
        inter_tap_variability_ms=features.inter_tap_variability_ms,
        longest_pause_ms=features.longest_pause_ms,
        taps_per_second=features.taps_per_second,
        quality=quality.value,
    )
    session.add(result)
    monitoring_session.status = SessionStatus.COMPLETED.value
    monitoring_session.completed_at = now
    # Flush the recording first so the longitudinal step sees it as committed
    # history for the sessions that follow, and because the comparison must
    # read back the quality just stored.
    await session.flush()

    # Longitudinal layer: compare this recording with the patient's own
    # history. The session being completed is excluded from that history, so it
    # is judged only against what came before it. The reported dose event, if
    # any, travels with the recording as supporting context.
    await record_longitudinal_result(
        session=session,
        patient_id=patient_id,
        recording=replace(
            recording,
            medication_context=context,
            medication_event=event,
        ),
    )

    await session.commit()
    await session.refresh(result)
    # Re-read with the result relationship eagerly loaded (see start_session).
    reloaded = await get_session_for_patient(
        session=session,
        patient_id=patient_id,
        monitoring_session_id=monitoring_session.id,
    )
    return reloaded, result


async def get_session_for_patient(
    *,
    session: AsyncSession,
    patient_id: int,
    monitoring_session_id: int,
) -> MonitoringSession:
    """Return the session when (and only when) the patient owns it."""
    monitoring_session = await session.scalar(
        select(MonitoringSession)
        .options(
            selectinload(MonitoringSession.result),
            selectinload(MonitoringSession.longitudinal).selectinload(
                LongitudinalResult.medication_event
            ),
        )
        .where(
            MonitoringSession.id == monitoring_session_id,
            MonitoringSession.patient_id == patient_id,
        )
        # A long-lived request session can hold a pre-write copy of this row;
        # the database, not the identity map, is authoritative.
        .execution_options(populate_existing=True)
    )
    if monitoring_session is None:
        raise SessionNotFoundError
    return monitoring_session


async def list_patient_sessions(
    *,
    session: AsyncSession,
    patient_id: int,
    limit: int,
) -> list[MonitoringSession]:
    """Return the patient's completed sessions, newest first."""
    statement = (
        select(MonitoringSession)
        .options(
            selectinload(MonitoringSession.result),
            selectinload(MonitoringSession.longitudinal).selectinload(
                LongitudinalResult.medication_event
            ),
        )
        .where(
            MonitoringSession.patient_id == patient_id,
            MonitoringSession.status == SessionStatus.COMPLETED.value,
        )
        .order_by(MonitoringSession.started_at.desc(), MonitoringSession.id.desc())
        .limit(limit)
    )
    return list(await session.scalars(statement))
