"""Doctor web portal API endpoints.

Doctor identity always comes from the authenticated session; no endpoint takes
a doctor identifier from the request. Errors map domain failures to explicit
HTTP statuses at this boundary only.
"""

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
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
