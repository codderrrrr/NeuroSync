"""Doctor web portal API endpoints.

Doctor identity always comes from the authenticated session; no endpoint takes
a doctor identifier from the request. Errors map domain failures to explicit
HTTP statuses at this boundary only.
"""

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.config.settings import settings
from neurosync.db import get_session
from neurosync.db.models import Doctor
from neurosync.modules.doctor.dependencies import (
    DOCTOR_SESSION_COOKIE_NAME,
    get_current_doctor,
    get_doctor_session_token,
)
from neurosync.modules.doctor.schemas import (
    AcceptLinkResponse,
    CreateAssignmentRequest,
    DoctorAssignmentResponse,
    DoctorAuthResponse,
    DoctorLoginRequest,
    DoctorResponse,
    DoctorSignupRequest,
    PendingLinkResponse,
    RosterPatientResponse,
)
from neurosync.modules.doctor.service import (
    DoctorEmailAlreadyRegisteredError,
    DoctorNameAlreadyRegisteredError,
    InactiveDoctorError,
    InvalidDoctorCredentialsError,
    PatientLinkNotFoundError,
    PatientNotLinkedError,
    accept_patient_link,
    create_assignment,
    get_doctor_code,
    list_active_patients,
    list_assignments,
    list_pending_requests,
    login_doctor,
    revoke_doctor_session,
    signup_doctor,
)
from neurosync.modules.doctor_linking.models import DoctorLinkStatus
from neurosync.modules.exceptions import service as exception_service
from neurosync.modules.exceptions.models import ExceptionStatus
from neurosync.modules.exceptions.schemas import (
    BaselineFactsResponse,
    ExceptionDetailResponse,
    ExceptionSummaryResponse,
    ReviewExceptionRequest,
)
from neurosync.modules.monitoring import service as monitoring_service

router = APIRouter(prefix="/doctor", tags=["doctor"])

DbSession = Annotated[AsyncSession, Depends(get_session)]
CurrentDoctor = Annotated[Doctor, Depends(get_current_doctor)]


def _doctor_response(doctor: Doctor, code: str | None) -> DoctorResponse:
    # Login and /me guarantee an email; the column is nullable only for
    # doctors provisioned before the portal existed.
    return DoctorResponse(
        id=doctor.id,
        name=doctor.name,
        email=doctor.email or "",
        created_at=doctor.created_at,
        code=code,
    )


async def _auth_response(
    session: AsyncSession,
    doctor: Doctor,
    token: str,
    expires_at: datetime,
) -> DoctorAuthResponse:
    return DoctorAuthResponse(
        doctor=_doctor_response(doctor, await get_doctor_code(session, doctor.id)),
        access_token=token,
        expires_at=expires_at,
    )


def _set_session_cookie(response: Response, *, token: str, expires_at: datetime) -> None:
    response.set_cookie(
        key=DOCTOR_SESSION_COOKIE_NAME,
        value=token,
        httponly=True,
        secure=settings.is_production,
        samesite="lax",
        path="/",
        expires=expires_at,
    )


@router.post(
    "/auth/signup",
    response_model=DoctorAuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a doctor account",
    description=(
        "Creates a doctor account and returns an authenticated session. A "
        "unique personal link code is generated for the doctor; patients type "
        "it to request a link."
    ),
)
async def signup(
    payload: DoctorSignupRequest,
    response: Response,
    session: DbSession,
) -> DoctorAuthResponse:
    try:
        doctor, _code, token, expires_at = await signup_doctor(
            session=session,
            name=payload.name,
            email=payload.email,
            password=payload.password,
        )
    except DoctorEmailAlreadyRegisteredError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        ) from exc
    except DoctorNameAlreadyRegisteredError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A doctor with this name already exists.",
        ) from exc

    _set_session_cookie(response, token=token, expires_at=expires_at)
    return await _auth_response(session, doctor, token, expires_at)


@router.post(
    "/auth/login",
    response_model=DoctorAuthResponse,
    summary="Sign in to the doctor portal",
    description="Verifies doctor credentials and returns an authenticated portal session.",
)
async def login(
    payload: DoctorLoginRequest,
    response: Response,
    session: DbSession,
) -> DoctorAuthResponse:
    try:
        doctor, token, expires_at = await login_doctor(
            session=session,
            email=payload.email,
            password=payload.password,
        )
    except InvalidDoctorCredentialsError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except InactiveDoctorError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is inactive.",
        ) from exc

    _set_session_cookie(response, token=token, expires_at=expires_at)
    return await _auth_response(session, doctor, token, expires_at)


@router.post(
    "/auth/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoke the current portal session",
    description="Revokes the doctor session used for this request. Idempotent.",
)
async def logout(
    response: Response,
    session: DbSession,
    token: Annotated[str, Depends(get_doctor_session_token)],
) -> None:
    await revoke_doctor_session(session, token=token)
    response.delete_cookie(key=DOCTOR_SESSION_COOKIE_NAME, path="/", samesite="lax")


@router.get(
    "/auth/me",
    response_model=DoctorResponse,
    summary="Return the authenticated doctor",
)
async def me(doctor: CurrentDoctor, session: DbSession) -> DoctorResponse:
    return _doctor_response(doctor, await get_doctor_code(session, doctor.id))


@router.get(
    "/patients",
    response_model=list[RosterPatientResponse],
    summary="List the doctor's accepted patients",
    description=(
        "Returns the patients whose link requests this doctor has accepted, "
        "newest acceptance first. Only identity and relationship data are "
        "exposed; no clinical information."
    ),
)
async def list_patients(doctor: CurrentDoctor, session: DbSession) -> list[RosterPatientResponse]:
    roster = await list_active_patients(session=session, doctor_id=doctor.id)
    return [
        RosterPatientResponse(
            patient_id=entry.patient_id,
            patient_name=entry.patient_name,
            status=entry.status,
            linked_at=entry.linked_at,
        )
        for entry in roster
    ]


@router.get(
    "/patient-links/pending",
    response_model=list[PendingLinkResponse],
    summary="List pending patient link requests",
    description=(
        "Returns the patients waiting for this doctor's acceptance, longest-waiting first."
    ),
)
async def list_pending(doctor: CurrentDoctor, session: DbSession) -> list[PendingLinkResponse]:
    requests = await list_pending_requests(session=session, doctor_id=doctor.id)
    return [
        PendingLinkResponse(
            id=request.link_id,
            patient_id=request.patient_id,
            patient_name=request.patient_name,
            created_at=request.created_at,
        )
        for request in requests
    ]


@router.post(
    "/patient-links/{link_id}/accept",
    response_model=AcceptLinkResponse,
    summary="Accept a pending patient request",
    description=(
        "Moves the patient onto this doctor's active roster. Accepting an "
        "already-accepted link returns its current state unchanged. A link "
        "that does not exist or belongs to another doctor returns 404."
    ),
)
async def accept_link(
    link_id: int,
    doctor: CurrentDoctor,
    session: DbSession,
) -> AcceptLinkResponse:
    try:
        link, patient_name, _changed = await accept_patient_link(
            session=session,
            doctor_id=doctor.id,
            link_id=link_id,
        )
    except PatientLinkNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient request not found.",
        ) from exc

    return AcceptLinkResponse(
        id=link.id,
        patient_id=link.patient_id,
        patient_name=patient_name,
        status=DoctorLinkStatus(link.status),
        accepted_at=link.accepted_at,
    )


@router.get(
    "/patients/{patient_id}/assignments",
    response_model=list[DoctorAssignmentResponse],
    summary="List the doctor's assignments for one patient",
    description="Newest assignment first. The patient must be on the doctor's roster.",
)
async def list_patient_assignments(
    patient_id: int,
    doctor: CurrentDoctor,
    session: DbSession,
) -> list[DoctorAssignmentResponse]:
    try:
        assignments = await list_assignments(
            session=session,
            doctor_id=doctor.id,
            patient_id=patient_id,
        )
    except PatientNotLinkedError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient not found in your roster.",
        ) from exc
    return [
        DoctorAssignmentResponse(
            id=assignment.plan_id,
            title=assignment.title,
            status=assignment.status,
            created_at=assignment.created_at,
            assessment_title=assignment.assessment_title,
            duration_seconds=assignment.duration_seconds,
        )
        for assignment in assignments
    ]


@router.post(
    "/patients/{patient_id}/assignments",
    response_model=DoctorAssignmentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Assign an exercise to a linked patient",
    description=(
        "Creates an active monitoring plan for the patient with the given "
        "recording duration. Only assessments with a runner (currently finger "
        "tapping) can be assigned. The patient must be on the doctor's roster."
    ),
)
async def create_patient_assignment(
    patient_id: int,
    payload: CreateAssignmentRequest,
    doctor: CurrentDoctor,
    session: DbSession,
) -> DoctorAssignmentResponse:
    try:
        assignment = await create_assignment(
            session=session,
            doctor_id=doctor.id,
            patient_id=patient_id,
            title=payload.title,
            assessment_slug=payload.assessment_slug,
            duration_seconds=payload.duration_seconds,
        )
    except PatientNotLinkedError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient not found in your roster.",
        ) from exc
    except monitoring_service.UnsupportedAssessmentError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This assessment is not available for assignment.",
        ) from exc

    return DoctorAssignmentResponse(
        id=assignment.plan_id,
        title=assignment.title,
        status=assignment.status,
        created_at=assignment.created_at,
        assessment_title=assignment.assessment_title,
        duration_seconds=assignment.duration_seconds,
    )


# ------------------------------------------------------------ review queue
#
# Routing decisions the monitoring pipeline made automatically, and the doctor's
# side of them. The scope is the same active roster the assignment endpoints
# use: an exception for a patient this doctor is not linked to is reported as
# missing, exactly as it would be for an id that never existed.


def _exception_summary_response(
    summary: exception_service.ExceptionSummary,
) -> ExceptionSummaryResponse:
    return ExceptionSummaryResponse(
        id=summary.id,
        patient_id=summary.patient_id,
        patient_name=summary.patient_name,
        exception_type=summary.exception_type,
        status=summary.status,
        rationale=summary.rationale,
        created_at=summary.created_at,
        longitudinal_state=summary.longitudinal_state,
        evidence_strength=summary.evidence_strength,
        assessment_title=summary.assessment_title,
        medication_context=summary.medication_context,
        minutes_since_medication=summary.minutes_since_medication,
    )


def _exception_detail_response(
    detail: exception_service.ExceptionDetail,
) -> ExceptionDetailResponse:
    baseline = detail.baseline
    return ExceptionDetailResponse(
        summary=_exception_summary_response(detail.summary),
        routing_rule=detail.routing_rule,
        supporting_observations=detail.supporting_observations,
        longitudinal_result_id=detail.longitudinal_result_id,
        monitoring_session_id=detail.monitoring_session_id,
        usable_history_count=detail.usable_history_count,
        baseline_confidence=detail.baseline_confidence,
        changed_features=detail.changed_features,
        recording_quality=detail.recording_quality,
        total_taps=detail.total_taps,
        duration_ms=detail.duration_ms,
        taps_per_second=detail.taps_per_second,
        mean_inter_tap_interval_ms=detail.mean_inter_tap_interval_ms,
        inter_tap_variability_ms=detail.inter_tap_variability_ms,
        longest_pause_ms=detail.longest_pause_ms,
        baseline=(
            None
            if baseline is None
            else BaselineFactsResponse(
                observation_count=baseline.observation_count,
                confidence=baseline.confidence,
                taps_per_second=baseline.taps_per_second,
                mean_inter_tap_interval_ms=baseline.mean_inter_tap_interval_ms,
                inter_tap_variability_ms=baseline.inter_tap_variability_ms,
                longest_pause_ms=baseline.longest_pause_ms,
            )
        ),
        reviewed_by_doctor_id=detail.reviewed_by_doctor_id,
        reviewed_at=detail.reviewed_at,
        review_note=detail.review_note,
    )


@router.get(
    "/exceptions",
    response_model=list[ExceptionSummaryResponse],
    summary="List the doctor's specialist review queue",
    description=(
        "Observations the monitoring pipeline routed for review, newest first, "
        "for every patient on the doctor's active roster. Each row says why it "
        "was routed; opening one is a separate request."
    ),
)
async def list_exceptions(
    doctor: CurrentDoctor,
    session: DbSession,
    status_filter: Annotated[
        ExceptionStatus | None,
        Query(alias="status", description="Restrict to one queue state"),
    ] = None,
    patient_id: Annotated[
        int | None, Query(description="Restrict to one patient on the roster")
    ] = None,
    limit: Annotated[
        int,
        Query(
            ge=1,
            le=exception_service.MAX_LIST_LIMIT,
            description="How many rows to return at most",
        ),
    ] = exception_service.DEFAULT_LIST_LIMIT,
) -> list[ExceptionSummaryResponse]:
    summaries = await exception_service.list_exceptions(
        session=session,
        doctor_id=doctor.id,
        status=status_filter,
        patient_id=patient_id,
        limit=limit,
    )
    return [_exception_summary_response(summary) for summary in summaries]


@router.get(
    "/exceptions/{exception_id}",
    response_model=ExceptionDetailResponse,
    summary="Show one routed observation with its evidence",
    description=(
        "The recording behind the routing decision alongside the patient's own "
        "baseline it was compared against, so a reviewer can see what the "
        "decision actually rested on."
    ),
)
async def get_exception(
    exception_id: int,
    doctor: CurrentDoctor,
    session: DbSession,
) -> ExceptionDetailResponse:
    try:
        detail = await exception_service.get_exception(
            session=session,
            doctor_id=doctor.id,
            exception_id=exception_id,
        )
    except exception_service.ExceptionNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Exception not found in your roster.",
        ) from exc
    return _exception_detail_response(detail)


@router.post(
    "/exceptions/{exception_id}/review",
    response_model=ExceptionDetailResponse,
    summary="Record a doctor's decision about a routed observation",
    description=(
        "Closes the exception as reviewed or dismissed, recording who acted, "
        "when, and any note in the doctor's own words. An exception can be "
        "closed once; a second attempt is a conflict rather than a silent "
        "overwrite of the first review."
    ),
)
async def review_exception(
    exception_id: int,
    payload: ReviewExceptionRequest,
    doctor: CurrentDoctor,
    session: DbSession,
) -> ExceptionDetailResponse:
    try:
        detail = await exception_service.review_exception(
            session=session,
            doctor_id=doctor.id,
            exception_id=exception_id,
            status=ExceptionStatus(payload.status.value),
            note=payload.note,
        )
    except exception_service.ExceptionNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Exception not found in your roster.",
        ) from exc
    except exception_service.ReviewAlreadyClosedError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This exception has already been reviewed.",
        ) from exc
    return _exception_detail_response(detail)
