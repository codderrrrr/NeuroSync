"""Monitoring API endpoints.

Patient identity always comes from the authenticated session; no endpoint takes
a patient identifier from the request. Errors map domain failures to explicit
HTTP statuses at this boundary only.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import get_session
from neurosync.modules.auth.dependencies import get_current_patient
from neurosync.modules.auth.models import Patient
from neurosync.modules.medication.context import MedicationContextResult
from neurosync.modules.medication.models import (
    EvidenceStrength,
    MedicationContext,
)
from neurosync.modules.monitoring import service
from neurosync.modules.monitoring.models import (
    AssessmentDefinition,
    LongitudinalResult,
    LongitudinalState,
    MonitoringSession,
    RecordingQuality,
)
from neurosync.modules.monitoring.schemas import (
    AssessmentResponse,
    CompleteSessionRequest,
    LongitudinalSummaryResponse,
    MonitoringPlanResponse,
    MonitoringSessionResponse,
    PatientBaselineResponse,
    SessionResultResponse,
    StartSessionRequest,
)

# Catalog and plan routers are mounted separately so paths stay clear.
catalog_router = APIRouter(prefix="/assessments", tags=["assessments"])
router = APIRouter(prefix="/monitoring", tags=["monitoring"])

DbSession = Annotated[AsyncSession, Depends(get_session)]
CurrentPatient = Annotated[Patient, Depends(get_current_patient)]

DEFAULT_LIST_LIMIT = 30
MAX_LIST_LIMIT = 100


def _assessment_response(definition: AssessmentDefinition) -> AssessmentResponse:
    return AssessmentResponse.model_validate(definition)


def _session_response(
    monitoring_session: MonitoringSession,
    definition: AssessmentDefinition,
) -> MonitoringSessionResponse:
    result: SessionResultResponse | None = None
    stored = monitoring_session.result
    if stored is not None:
        result = SessionResultResponse(
            total_taps=stored.total_taps,
            duration_ms=stored.duration_ms,
            mean_inter_tap_interval_ms=stored.mean_inter_tap_interval_ms,
            inter_tap_variability_ms=stored.inter_tap_variability_ms,
            longest_pause_ms=stored.longest_pause_ms,
            taps_per_second=stored.taps_per_second,
            quality=RecordingQuality(stored.quality),
        )
    return MonitoringSessionResponse(
        id=monitoring_session.id,
        status=monitoring_session.status,
        assessment=_assessment_response(definition),
        started_at=monitoring_session.started_at,
        completed_at=monitoring_session.completed_at,
        result=result,
        longitudinal=_longitudinal_summary(monitoring_session.longitudinal),
    )


def _longitudinal_summary(
    stored: LongitudinalResult | None,
) -> LongitudinalSummaryResponse | None:
    """Render one session's longitudinal state, with its supporting context.

    ``is_confident`` is false whenever the state rests on a reduced-confidence
    baseline or on no baseline at all, so the client can soften its wording
    rather than presenting a weakly-supported conclusion as settled.

    The medication block is derived from the stored columns, never recomputed
    here, so what the client reads is exactly what was persisted at the time.
    """
    if stored is None:
        return None
    confidence = stored.baseline_confidence
    context = MedicationContext(stored.medication_context)
    medication_note = MedicationContextResult(
        context=context,
        minutes_since=stored.minutes_since_medication,
    ).explanation()
    event = stored.medication_event
    return LongitudinalSummaryResponse(
        state=LongitudinalState(stored.state),
        usable_history_count=stored.usable_history_count,
        baseline_observation_count=(
            stored.usable_history_count if confidence is not None else None
        ),
        baseline_confidence=confidence,
        changed_features=list(stored.changed_features or []),
        is_confident=confidence is not None and confidence == "full",
        medication_context=context,
        medication_name=event.medication.name if event is not None else None,
        minutes_since_medication=stored.minutes_since_medication,
        evidence_strength=EvidenceStrength(stored.evidence_strength),
        comparable_observation_count=stored.comparable_observation_count,
        medication_note=medication_note,
    )


@catalog_router.get(
    "",
    response_model=list[AssessmentResponse],
    summary="List the assessment catalog",
    description=(
        "Returns every assessment NeuroSync defines. ``is_supported`` marks "
        "assessments with an executable runner; the rest are 'Not available yet' "
        "and can never be assigned to a patient."
    ),
)
async def list_assessments(
    patient: CurrentPatient,  # noqa: ARG001 - authentication is the gate
    session: DbSession,
) -> list[AssessmentResponse]:
    definitions = await service.get_assessment_catalog(session)
    return [_assessment_response(definition) for definition in definitions]


@router.get(
    "/plan",
    response_model=MonitoringPlanResponse,
    summary="Return the patient's active monitoring plan",
    description=(
        "Returns the active plan with its ordered items and how many times each "
        "was completed today (UTC). The client decides nothing about which tests "
        "exist; it renders what the API returns."
    ),
)
async def get_plan(patient: CurrentPatient, session: DbSession) -> MonitoringPlanResponse:
    try:
        plan, items = await service.get_patient_plan(
            session=session,
            patient_id=patient.id,
        )
    except service.PlanNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active monitoring plan found.",
        ) from exc
    return MonitoringPlanResponse(
        id=plan.id,
        title=plan.title,
        status=plan.status,
        items=items,
    )


@router.get(
    "/baseline",
    response_model=PatientBaselineResponse,
    summary="Return the patient's own finger-tapping baseline",
    description=(
        "Returns the patient's own historical reference for the supported "
        "assessment: the median of their usable recordings, how many produced "
        "it, and how much of that history was borderline. Derived from this "
        "patient's sessions only; there are no population norms. Returns 404 "
        "until enough usable history exists to establish one."
    ),
)
async def get_baseline(
    patient: CurrentPatient,
    session: DbSession,
) -> PatientBaselineResponse:
    definition = await _supported_definition(session)
    stored = await service.get_baseline(
        session=session,
        patient_id=patient.id,
        assessment_definition_id=definition.id,
    )
    if stored is None or not stored.observation_count:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not enough usable sessions yet to establish a baseline.",
        )
    return PatientBaselineResponse(
        assessment=_assessment_response(definition),
        observation_count=stored.observation_count,
        valid_observation_count=stored.valid_observation_count,
        borderline_observation_count=stored.borderline_observation_count,
        confidence=stored.confidence,
        taps_per_second=stored.taps_per_second,
        mean_inter_tap_interval_ms=stored.mean_inter_tap_interval_ms,
        inter_tap_variability_ms=stored.inter_tap_variability_ms,
        longest_pause_ms=stored.longest_pause_ms,
        explanation=service.baseline_explanation(stored),
    )


async def _supported_definition(db_session: AsyncSession) -> AssessmentDefinition:
    """Return the supported assessment the longitudinal layer covers."""
    definition = await db_session.scalar(
        select(AssessmentDefinition)
        .where(AssessmentDefinition.is_supported.is_(True))
        .order_by(AssessmentDefinition.id)
        .limit(1)
    )
    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No supported assessment is available.",
        )
    return definition


@router.post(
    "/sessions",
    response_model=MonitoringSessionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Start a monitoring session",
    description=(
        "Opens an in-progress session for one of the patient's plan items. The "
        "plan item must belong to the authenticated patient's plan and its "
        "assessment must have a runner."
    ),
)
async def start_session(
    payload: StartSessionRequest,
    patient: CurrentPatient,
    session: DbSession,
) -> MonitoringSessionResponse:
    try:
        monitoring_session = await service.start_session(
            session=session,
            patient_id=patient.id,
            plan_item_id=payload.plan_item_id,
        )
    except service.PlanItemNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Monitoring task not found.",
        ) from exc
    except service.UnsupportedAssessmentError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This assessment is not available yet.",
        ) from exc

    definition = await _definition_for(
        session,
        monitoring_session.assessment_definition_id,
    )
    return _session_response(monitoring_session, definition)


@router.post(
    "/sessions/{session_id}/complete",
    response_model=MonitoringSessionResponse,
    summary="Complete a monitoring session",
    description=(
        "Stores the raw event stream, derives the recording summary and quality "
        "deterministically, and closes the session. Completing twice returns 409."
    ),
)
async def complete_session(
    session_id: int,
    payload: CompleteSessionRequest,
    patient: CurrentPatient,
    session: DbSession,
) -> MonitoringSessionResponse:
    try:
        monitoring_session, _ = await service.complete_session(
            session=session,
            patient_id=patient.id,
            monitoring_session_id=session_id,
            payload=payload,
        )
    except service.SessionNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Monitoring session not found.",
        ) from exc
    except service.InactiveSessionError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This session has already been completed.",
        ) from exc
    except service.InvalidEventDataError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    except service.UnknownMedicationEventError as exc:
        # Another patient's dose event is indistinguishable from a missing one.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Medication event not found.",
        ) from exc

    definition = await _definition_for(
        session,
        monitoring_session.assessment_definition_id,
    )
    return _session_response(monitoring_session, definition)


@router.get(
    "/sessions",
    response_model=list[MonitoringSessionResponse],
    summary="List the patient's completed monitoring sessions",
)
async def list_sessions(
    patient: CurrentPatient,
    session: DbSession,
    limit: Annotated[int, Query(ge=1, le=MAX_LIST_LIMIT)] = DEFAULT_LIST_LIMIT,
) -> list[MonitoringSessionResponse]:
    sessions = await service.list_patient_sessions(
        session=session,
        patient_id=patient.id,
        limit=limit,
    )
    # One lookup for the whole page rather than one per session. Every session
    # in a plan item shares an assessment definition, and loading them
    # individually issues the same query once per row.
    definitions = await _definitions_by_id(
        session,
        {s.assessment_definition_id for s in sessions},
    )
    return [_session_response(s, definitions[s.assessment_definition_id]) for s in sessions]


@router.get(
    "/sessions/{session_id}",
    response_model=MonitoringSessionResponse,
    summary="Return one monitoring session",
    description=(
        "Returns a single session with its result. A session that does not "
        "exist or does not belong to the patient returns 404."
    ),
)
async def get_session_detail(
    session_id: int,
    patient: CurrentPatient,
    session: DbSession,
) -> MonitoringSessionResponse:
    try:
        monitoring_session = await service.get_session_for_patient(
            session=session,
            patient_id=patient.id,
            monitoring_session_id=session_id,
        )
    except service.SessionNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Monitoring session not found.",
        ) from exc
    return await _session_with_definition(session, monitoring_session)


async def _definitions_by_id(
    db_session: AsyncSession,
    definition_ids: set[int],
) -> dict[int, AssessmentDefinition]:
    """Load every assessment definition a page of sessions refers to, at once."""
    if not definition_ids:
        return {}
    rows = await db_session.scalars(
        select(AssessmentDefinition).where(AssessmentDefinition.id.in_(definition_ids))
    )
    by_id = {definition.id: definition for definition in rows}
    missing = definition_ids - set(by_id)
    if missing:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The session's assessment definition is missing.",
        )
    return by_id


async def _definition_for(
    db_session: AsyncSession,
    definition_id: int,
) -> AssessmentDefinition:
    """Load a session's assessment definition or fail the request loudly."""
    definition = await db_session.get(AssessmentDefinition, definition_id)
    if definition is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The session's assessment definition is missing.",
        )
    return definition


async def _session_with_definition(
    db_session: AsyncSession,
    monitoring_session: MonitoringSession,
) -> MonitoringSessionResponse:
    definition = await _definition_for(
        db_session,
        monitoring_session.assessment_definition_id,
    )
    return _session_response(monitoring_session, definition)
