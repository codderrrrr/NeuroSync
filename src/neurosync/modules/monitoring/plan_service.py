"""Plan service: what a patient has been asked to do, and for how long.

A plan groups ordered assessment items. The rules that decide *how long* a
recording should run and *what settings* it uses live here, so the plan the
client is shown and the quality evaluation of the recording that came back can
never disagree about either.
"""

from datetime import UTC, datetime, time

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.monitoring.assessment_catalog import get_spec, resolve_parameters
from neurosync.modules.monitoring.catalog_service import assessment_response
from neurosync.modules.monitoring.errors import (
    ERR_PLAN_NEEDS_ASSESSMENTS,
    ERR_UNASSIGNABLE_ASSESSMENTS,
    ERR_UNKNOWN_ASSESSMENTS,
    MonitoringError,
    PlanItemNotFoundError,
    PlanNotFoundError,
    UnsupportedAssessmentError,
)
from neurosync.modules.monitoring.models import (
    AssessmentDefinition,
    MonitoringPlan,
    MonitoringPlanItem,
    MonitoringSession,
    PlanStatus,
    SessionStatus,
)
from neurosync.modules.monitoring.schemas import PlanItemResponse


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


def resolve_item_parameters(
    item: MonitoringPlanItem,
    definition: AssessmentDefinition,
) -> dict[str, int | str]:
    """Return every doctor-set parameter for one plan item.

    Stored values win, catalog defaults fill the gaps, and an assessment that
    declares no parameters resolves to an empty set. This is the single rule
    for "what exactly was this patient asked to do", so the plan the client is
    shown and the quality evaluation of the recording that came back can never
    disagree.
    """
    spec = get_spec(definition.slug)
    if spec is None:
        return {}
    return resolve_parameters(item.parameters, spec)


async def create_plan(  # noqa: PLR0913 - explicit arguments beat a config object
    *,
    session: AsyncSession,
    patient_id: int,
    title: str,
    assessment_definition_ids: list[int],
    doctor_id: int | None = None,
    status: PlanStatus = PlanStatus.ACTIVE,
    duration_seconds: int | None = None,
    parameters: dict[str, int | str] | None = None,
) -> MonitoringPlan:
    """Create a plan from catalog assessments, in the given order.

    Every assessment must exist in the catalog and be supported: a plan is a
    promise that the patient can execute each item, so an assessment without a
    runner can never be assigned. Draft plans keep the same rule at item level;
    publishing (activating) a draft re-checks every item. ``duration_seconds``
    optionally overrides each item's recording target (a doctor-controlled
    exercise length); ``None`` keeps the catalog default. ``parameters`` is the
    rest of what the doctor set, already validated against the assessment's
    catalog specs by the API boundary.
    """
    if not assessment_definition_ids:
        raise MonitoringError(ERR_PLAN_NEEDS_ASSESSMENTS)

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
        raise PlanItemNotFoundError(ERR_UNKNOWN_ASSESSMENTS.format(ids=missing))

    unsupported = [
        definition.slug
        for definition_id in assessment_definition_ids
        if not (definition := by_id[definition_id]).is_supported
    ]
    if unsupported:
        raise UnsupportedAssessmentError(ERR_UNASSIGNABLE_ASSESSMENTS.format(slugs=unsupported))

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
                parameters=parameters,
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

    Items whose assessment is not supported are left out. A test can be held
    back after a doctor assigned it -- that is what ``is_supported`` is for --
    and a patient must not be shown a task NeuroSync has decided not to ask
    for. The plan item and any recordings made against it stay in the database;
    only the patient's view of what to do next changes.
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
            .join(
                AssessmentDefinition,
                AssessmentDefinition.id == MonitoringPlanItem.assessment_definition_id,
            )
            .where(
                MonitoringPlanItem.plan_id == plan.id,
                AssessmentDefinition.is_supported.is_(True),
            )
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
            assessment=assessment_response(definitions[item.assessment_definition_id]),
            position=item.position,
            completed_today=completed_today.get(item.id, 0),
            duration_seconds=resolve_item_duration_seconds(
                item, definitions[item.assessment_definition_id]
            ),
            parameters=resolve_item_parameters(item, definitions[item.assessment_definition_id]),
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
