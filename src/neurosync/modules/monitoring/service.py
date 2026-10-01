"""Monitoring use cases: catalog, plans, sessions, and results.

Every patient-scoped lookup is filtered by the ``patient_id`` derived from the
authenticated session, so an object that exists but belongs to someone else is
indistinguishable from one that does not exist. Use cases that write own their
transaction, matching the other modules.
"""

from datetime import UTC, datetime, time

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from neurosync.modules.monitoring.assessment_catalog import ASSESSMENT_CATALOG
from neurosync.modules.monitoring.features import extract_tap_features
from neurosync.modules.monitoring.models import (
    AssessmentDefinition,
    MonitoringPlan,
    MonitoringPlanItem,
    MonitoringResult,
    MonitoringSession,
    MonitoringSessionEvent,
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


def _utc_today_start() -> datetime:
    """Return midnight today (UTC), the boundary for daily availability."""
    now = datetime.now(UTC)
    return datetime.combine(now.date(), time.min, tzinfo=UTC)


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


class CreatePlanRequest:
    """Defaults for plan creation, kept together for readability."""

    DOCTOR_ID = None
    STATUS = PlanStatus.ACTIVE


async def create_plan(  # noqa: PLR0913 - explicit arguments beat a config object
    *,
    session: AsyncSession,
    patient_id: int,
    title: str,
    assessment_definition_ids: list[int],
    doctor_id: int | None = CreatePlanRequest.DOCTOR_ID,
    status: PlanStatus = CreatePlanRequest.STATUS,
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
            # A doctor-assigned override wins; otherwise the catalog default.
            duration_seconds=(
                item.duration_seconds
                if item.duration_seconds is not None
                else definitions[item.assessment_definition_id].default_duration_seconds
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
    if definition is None or not definition.is_supported:  # noqa: PLR2004
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


class UnsupportedEventMessage:
    """Message for event streams that contain non-tap events."""

    @staticmethod
    def for_type(event_type: str) -> str:
        return f"Unsupported event type: {event_type!r}"


def _to_tap_offsets(events: list[TapEventRequest]) -> list[int]:
    """Validate the raw event stream and reduce it to tap offsets."""
    try:
        offsets = event_offsets_ms(events)
    except ValueError as exc:
        raise InvalidEventDataError(str(exc)) from exc
    if sorted(offsets) != offsets:
        raise InvalidEventDataError(NonMonotonicOffsetsMessage.MESSAGE)
    return offsets


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
    target_ms = definition.default_duration_seconds * 1000
    quality = evaluate_quality(features=features, target_duration_ms=target_ms)

    now = datetime.now(UTC)
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
        .options(selectinload(MonitoringSession.result))
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
        .options(selectinload(MonitoringSession.result))
        .where(
            MonitoringSession.patient_id == patient_id,
            MonitoringSession.status == SessionStatus.COMPLETED.value,
        )
        .order_by(MonitoringSession.started_at.desc(), MonitoringSession.id.desc())
        .limit(limit)
    )
    return list(await session.scalars(statement))
