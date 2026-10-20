from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.config.settings import settings
from neurosync.db import get_session
from neurosync.modules.auth.dependencies import get_current_patient, get_session_token
from neurosync.modules.auth.models import Patient
from neurosync.modules.auth.schemas import (
    AuthResponse,
    LoginRequest,
    PatientResponse,
    SignupRequest,
)
from neurosync.modules.auth.security import SESSION_COOKIE_NAME
from neurosync.modules.auth.service import (
    EmailAlreadyRegisteredError,
    InactivePatientError,
    InvalidCredentialsError,
    login_patient,
    revoke_session,
    signup_patient,
)
from neurosync.modules.auth.session_support import delete_session_cookie, set_session_cookie

router = APIRouter(prefix="/auth", tags=["auth"])

DbSession = Annotated[AsyncSession, Depends(get_session)]


def _patient_response(patient: Patient) -> PatientResponse:
    return PatientResponse(
        id=patient.id,
        email=patient.email,
        name=patient.name,
        created_at=patient.created_at,
    )


def _auth_response(patient: Patient, token: str, expires_at: datetime) -> AuthResponse:
    return AuthResponse(
        patient=_patient_response(patient),
        access_token=token,
        expires_at=expires_at,
    )


@router.post(
    "/signup",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a patient account",
    description="Creates a patient account and returns an authenticated session.",
)
async def signup(
    payload: SignupRequest,
    response: Response,
    session: DbSession,
) -> AuthResponse:
    try:
        patient, token, expires_at = await signup_patient(
            session=session,
            name=payload.name,
            email=payload.email,
            password=payload.password,
        )
    except EmailAlreadyRegisteredError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        ) from exc

    set_session_cookie(
        response,
        cookie_name=SESSION_COOKIE_NAME,
        token=token,
        expires_at=expires_at,
        secure=settings.is_production,
    )
    return _auth_response(patient, token, expires_at)


@router.post(
    "/login",
    response_model=AuthResponse,
    summary="Sign in",
    description="Verifies credentials and returns an authenticated session.",
)
async def login(
    payload: LoginRequest,
    response: Response,
    session: DbSession,
) -> AuthResponse:
    try:
        patient, token, expires_at = await login_patient(
            session=session,
            email=payload.email,
            password=payload.password,
        )
    except InvalidCredentialsError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except InactivePatientError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is inactive.",
        ) from exc

    set_session_cookie(
        response,
        cookie_name=SESSION_COOKIE_NAME,
        token=token,
        expires_at=expires_at,
        secure=settings.is_production,
    )
    return _auth_response(patient, token, expires_at)


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Revoke the current session",
    description="Revokes the session used for this request. Idempotent.",
)
async def logout(
    response: Response,
    session: DbSession,
    token: Annotated[str, Depends(get_session_token)],
) -> None:
    await revoke_session(session, token=token)
    delete_session_cookie(response, cookie_name=SESSION_COOKIE_NAME)


@router.get(
    "/me",
    response_model=PatientResponse,
    summary="Return the authenticated patient",
)
async def me(patient: Annotated[Patient, Depends(get_current_patient)]) -> PatientResponse:
    return _patient_response(patient)
