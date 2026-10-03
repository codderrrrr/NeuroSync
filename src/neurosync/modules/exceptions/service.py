"""Exception use cases: routing an observation, and the doctor's review queue.

Two responsibilities, kept apart on purpose:

* **Routing** happens automatically at the end of the monitoring pipeline and
  only ever *adds* to the queue. It reads already-computed longitudinal
  results; it never recomputes one.
* **Review** is a doctor acting. Every read and every write here is scoped to
  the patients that doctor is actively linked to, reusing the same
  ``DoctorLink`` relationship the assignment endpoints already use. An exception
  for anyone else is reported as missing, never as forbidden.

Nothing in this module interprets evidence. It routes it, and it records what
the reviewing doctor said about it.
"""

from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.auth.models import Patient
from neurosync.modules.doctor_linking.models import DoctorLink, DoctorLinkStatus
from neurosync.modules.exceptions.models import (
    REVIEWABLE_STATUSES,
    ExceptionStatus,
    ReviewException,
)
from neurosync.modules.exceptions.routing import (
    PERSISTENCE_OBSERVATIONS,
    RoutingObservation,
    route_observation,
)
from neurosync.modules.medication.models import EvidenceStrength, MedicationContext
from neurosync.modules.monitoring.longitudinal import USABLE_QUALITIES
from neurosync.modules.monitoring.models import (
    AssessmentDefinition,
    LongitudinalResult,
    LongitudinalState,
    MonitoringResult,
    MonitoringSession,
    PatientBaseline,
)

DEFAULT_LIST_LIMIT = 50
MAX_LIST_LIMIT = 100


class ExceptionNotFoundError(Exception):
    """Raised when an exception does not exist for this doctor.

    Also the answer for an exception belonging to a patient the doctor is not
    actively linked to. One message for both, so probing the queue cannot
    reveal that another doctor's patient has a queue at all.
    """


class ReviewAlreadyClosedError(Exception):
    """Raised when a doctor tries to review an exception twice."""


class UnreviewableStatusError(Exception):
    """Raised when a caller tries to close an exception with an arrival state."""


async def _linked_patient_ids(session: AsyncSession, *, doctor_id: int) -> set[int]:
    """Every patient this doctor is actively linked to.

    One query for the whole roster rather than one existence check per row,
    which is what keeps listing the queue free of N+1 behaviour.
    """
    rows = await session.scalars(
        select(DoctorLink.patient_id).where(
            DoctorLink.doctor_id == doctor_id,
            DoctorLink.status == DoctorLinkStatus.ACTIVE.value,
        )
    )
    return set(rows)


# ----------------------------------------------------------------- routing


async def recent_usable_states(
    session: AsyncSession,
    *,
    patient_id: int,
    assessment_definition_id: int,
    exclude_session_id: int,
    limit: int,
) -> tuple[LongitudinalState, ...]:
    """This patient's most recent usable longitudinal states, newest first.

    Reads states that were already computed and stored; it does not redo the
    comparison. Unusable sessions are filtered out entirely, so a failed
    recording can neither break a run of good ones nor count towards
    persistence.
    """
    statement = (
        select(LongitudinalResult.state)
        .join(MonitoringSession, MonitoringSession.id == LongitudinalResult.session_id)
        .join(MonitoringResult, MonitoringResult.session_id == MonitoringSession.id)
        .where(
            MonitoringSession.patient_id == patient_id,
            MonitoringSession.assessment_definition_id == assessment_definition_id,
            MonitoringSession.id != exclude_session_id,
            MonitoringResult.quality.in_(USABLE_QUALITIES),
        )
        .order_by(MonitoringSession.completed_at.desc(), MonitoringSession.id.desc())
        .limit(limit)
    )
    return tuple(LongitudinalState(state) for state in await session.scalars(statement))


async def route_longitudinal_result(
    session: AsyncSession,
    *,
    longitudinal_result: LongitudinalResult,
    patient_id: int,
    assessment_definition_id: int,
    persistence_observations: int = PERSISTENCE_OBSERVATIONS,
) -> ReviewException | None:
    """Route one freshly computed longitudinal result, at most once.

    Returns the existing exception when one is already there, so calling this
    twice for the same observation is a no-op rather than a second queue entry.
    The unique constraint on ``longitudinal_result_id`` is what actually
    guarantees that; this function simply avoids the collision instead of
    relying on an IntegrityError round trip.

    Returns ``None`` whenever the rules decline to route. That is the expected
    outcome for most recordings and is not an error.
    """
    existing = await session.scalar(
        select(ReviewException).where(
            ReviewException.longitudinal_result_id == longitudinal_result.id
        )
    )
    if existing is not None:
        return existing

    recent = await recent_usable_states(
        session,
        patient_id=patient_id,
        assessment_definition_id=assessment_definition_id,
        exclude_session_id=longitudinal_result.session_id,
        limit=persistence_observations,
    )
    decision = route_observation(
        current=RoutingObservation(
            state=LongitudinalState(longitudinal_result.state),
            evidence_strength=EvidenceStrength(longitudinal_result.evidence_strength),
            medication_context=MedicationContext(longitudinal_result.medication_context),
            comparable_observation_count=longitudinal_result.comparable_observation_count,
        ),
        recent_states=recent,
        persistence_observations=persistence_observations,
    )
    if not decision.should_route:
        return None

    assert decision.exception_type is not None  # guaranteed by should_route
    assert decision.rule is not None
    exception = ReviewException(
        longitudinal_result_id=longitudinal_result.id,
        patient_id=patient_id,
        exception_type=decision.exception_type.value,
        routing_rule=decision.rule.value,
        rationale=decision.rationale,
        supporting_observations=decision.supporting_observations,
        status=ExceptionStatus.OPEN.value,
    )
    session.add(exception)
    await session.flush()
    return exception


# ------------------------------------------------------------------- queue


@dataclass(frozen=True, slots=True)
class ExceptionSummary:
    """One queue row: enough to decide whether to open it, and no more."""

    id: int
    patient_id: int
    patient_name: str
    exception_type: str
    status: str
    rationale: str
    created_at: datetime
    longitudinal_state: str
    evidence_strength: str
    assessment_title: str
    medication_context: str
    minutes_since_medication: int | None


@dataclass(frozen=True, slots=True)
class BaselineFacts:
    """The patient's own reference the observation was compared against."""

    observation_count: int
    confidence: str
    taps_per_second: float
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int


@dataclass(frozen=True, slots=True)
class ExceptionDetail:
    """One exception with the underlying evidence attached."""

    summary: ExceptionSummary
    routing_rule: str
    supporting_observations: int
    longitudinal_result_id: int
    monitoring_session_id: int
    usable_history_count: int
    baseline_confidence: str | None
    changed_features: tuple[str, ...]
    recording_quality: str
    total_taps: int
    duration_ms: int
    taps_per_second: float
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int
    baseline: BaselineFacts | None
    reviewed_by_doctor_id: int | None
    reviewed_at: datetime | None
    review_note: str | None


def _summary(
    exception: ReviewException,
    *,
    patient_name: str,
    assessment_title: str,
) -> ExceptionSummary:
    """Project one exception row, reading only what the list view shows.

    Every caller reaches this after a query that has joined the longitudinal
    result into the same row, so the relationship is already populated and no
    per-row query is issued. There is deliberately no baseline or raw recording
    here: those belong to the detail view, which is opened on purpose.
    """
    result = exception.longitudinal_result
    return ExceptionSummary(
        id=exception.id,
        patient_id=exception.patient_id,
        patient_name=patient_name,
        exception_type=exception.exception_type,
        status=exception.status,
        rationale=exception.rationale,
        created_at=exception.created_at,
        longitudinal_state=result.state,
        evidence_strength=result.evidence_strength,
        assessment_title=assessment_title,
        medication_context=result.medication_context,
        minutes_since_medication=result.minutes_since_medication,
    )


def _baseline_facts(baseline: PatientBaseline | None) -> BaselineFacts | None:
    """The stored reference values, or nothing when no baseline existed."""
    if baseline is None:
        return None
    return BaselineFacts(
        observation_count=baseline.observation_count,
        confidence=baseline.confidence,
        taps_per_second=baseline.taps_per_second,
        mean_inter_tap_interval_ms=baseline.mean_inter_tap_interval_ms,
        inter_tap_variability_ms=baseline.inter_tap_variability_ms,
        longest_pause_ms=baseline.longest_pause_ms,
    )


def _detail(
    exception: ReviewException,
    *,
    patient_name: str,
    assessment_title: str,
    recording: MonitoringResult,
    baseline: PatientBaseline | None,
) -> ExceptionDetail:
    """One exception plus the recording and reference behind it."""
    result = exception.longitudinal_result
    return ExceptionDetail(
        summary=_summary(exception, patient_name=patient_name, assessment_title=assessment_title),
        routing_rule=exception.routing_rule,
        supporting_observations=exception.supporting_observations,
        longitudinal_result_id=result.id,
        monitoring_session_id=result.session_id,
        usable_history_count=result.usable_history_count,
        baseline_confidence=result.baseline_confidence,
        changed_features=tuple(result.changed_features or ()),
        recording_quality=recording.quality,
        total_taps=recording.total_taps,
        duration_ms=recording.duration_ms,
        taps_per_second=recording.taps_per_second,
        mean_inter_tap_interval_ms=recording.mean_inter_tap_interval_ms,
        inter_tap_variability_ms=recording.inter_tap_variability_ms,
        longest_pause_ms=recording.longest_pause_ms,
        baseline=_baseline_facts(baseline),
        reviewed_by_doctor_id=exception.reviewed_by_doctor_id,
        reviewed_at=exception.reviewed_at,
        review_note=exception.review_note,
    )


async def list_exceptions(
    session: AsyncSession,
    *,
    doctor_id: int,
    status: ExceptionStatus | None = None,
    patient_id: int | None = None,
    limit: int = DEFAULT_LIST_LIMIT,
) -> list[ExceptionSummary]:
    """The doctor's queue, newest first.

    Scoped to the patients this doctor is actively linked to in the same
    statement, so a queue row can never leak across the roster boundary no
    matter what the caller asks for. The whole chain - exception, longitudinal
    result, session, assessment, patient - is joined in one query, so a page of
    any length costs the same.
    """
    linked = await _linked_patient_ids(session, doctor_id=doctor_id)
    if not linked:
        return []

    statement = (
        select(ReviewException, LongitudinalResult, Patient.name, AssessmentDefinition.title)
        .select_from(ReviewException)
        .join(Patient, Patient.id == ReviewException.patient_id)
        .join(
            LongitudinalResult,
            LongitudinalResult.id == ReviewException.longitudinal_result_id,
        )
        .join(MonitoringSession, MonitoringSession.id == LongitudinalResult.session_id)
        .join(
            AssessmentDefinition,
            AssessmentDefinition.id == MonitoringSession.assessment_definition_id,
        )
        .where(ReviewException.patient_id.in_(linked))
        .order_by(ReviewException.created_at.desc(), ReviewException.id.desc())
        .limit(max(1, min(limit, MAX_LIST_LIMIT)))
    )
    if status is not None:
        statement = statement.where(ReviewException.status == status.value)
    if patient_id is not None:
        statement = statement.where(ReviewException.patient_id == patient_id)

    rows = (await session.execute(statement)).all()
    return [
        _summary(exception, patient_name=name, assessment_title=title)
        for exception, _, name, title in rows
    ]


async def get_exception(
    session: AsyncSession,
    *,
    doctor_id: int,
    exception_id: int,
) -> ExceptionDetail:
    """One exception with its evidence, for a patient this doctor is linked to.

    Raises ``ExceptionNotFoundError`` for an id that does not exist and for one
    that belongs to someone else's patient, in one case, so the queue cannot be
    probed for patients outside the roster.
    """
    linked = await _linked_patient_ids(session, doctor_id=doctor_id)
    if not linked:
        raise ExceptionNotFoundError

    # A longitudinal result is only ever written alongside its recording, so the
    # join is an inner one; a baseline is optional, so that join is not.
    row = (
        await session.execute(
            select(
                ReviewException,
                LongitudinalResult,
                Patient.name,
                AssessmentDefinition.title,
                MonitoringResult,
                PatientBaseline,
            )
            .select_from(ReviewException)
            .join(Patient, Patient.id == ReviewException.patient_id)
            .join(
                LongitudinalResult,
                LongitudinalResult.id == ReviewException.longitudinal_result_id,
            )
            .join(MonitoringSession, MonitoringSession.id == LongitudinalResult.session_id)
            .join(
                AssessmentDefinition,
                AssessmentDefinition.id == MonitoringSession.assessment_definition_id,
            )
            .join(MonitoringResult, MonitoringResult.session_id == MonitoringSession.id)
            .outerjoin(PatientBaseline, PatientBaseline.id == LongitudinalResult.baseline_id)
            .where(
                ReviewException.id == exception_id,
                ReviewException.patient_id.in_(linked),
            )
        )
    ).one_or_none()
    if row is None:
        raise ExceptionNotFoundError

    exception, _, patient_name, assessment_title, recording, baseline = row
    return _detail(
        exception,
        patient_name=patient_name,
        assessment_title=assessment_title,
        recording=recording,
        baseline=baseline,
    )


async def review_exception(
    session: AsyncSession,
    *,
    doctor_id: int,
    exception_id: int,
    status: ExceptionStatus,
    note: str | None = None,
) -> ExceptionDetail:
    """Record this doctor's review of an exception and return it, refreshed.

    Writes only what the doctor supplied plus the two facts the database cannot
    know on its own: who acted, and when. The status must be a *closing*
    status; ``open`` is the arrival state, not an outcome a reviewer picks, so
    setting it back would silently un-review the row.
    """
    if status.value not in REVIEWABLE_STATUSES:
        raise UnreviewableStatusError

    exception = await _load_for_review(session, doctor_id=doctor_id, exception_id=exception_id)
    exception.status = status.value
    exception.reviewed_by_doctor_id = doctor_id
    exception.reviewed_at = datetime.now(UTC)
    exception.review_note = note
    await session.flush()
    await session.refresh(exception, attribute_names=["longitudinal_result"])
    return await get_exception(session, doctor_id=doctor_id, exception_id=exception_id)


async def _load_for_review(
    session: AsyncSession,
    *,
    doctor_id: int,
    exception_id: int,
) -> ReviewException:
    """Fetch an open exception, scoped to the reviewing doctor's roster."""
    linked = await _linked_patient_ids(session, doctor_id=doctor_id)
    if not linked:
        raise ExceptionNotFoundError
    exception = await session.scalar(
        select(ReviewException).where(
            ReviewException.id == exception_id,
            ReviewException.patient_id.in_(linked),
        )
    )
    if exception is None:
        raise ExceptionNotFoundError
    if exception.status != ExceptionStatus.OPEN.value:
        raise ReviewAlreadyClosedError
    return exception
