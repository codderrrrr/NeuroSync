"""Authentication dependencies for doctor-only endpoints."""

from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import get_session
from neurosync.db.models import Doctor
from neurosync.modules.doctor.service import InvalidDoctorSessionError, resolve_doctor_for_session

_BEARER_SCHEME = "bearer"

# Separate from the patient cookie so the two apps can run side by side in one
# browser without their sessions colliding.
DOCTOR_SESSION_COOKIE_NAME = "neurosync_doctor_session"


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Doctor authentication required.",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def get_doctor_session_token(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    """Return the raw doctor session token from the header or cookie.

    The portal sends a bearer token; the same token is also set as an
    HTTP-only cookie so browser refreshes keep the session without exposing
    it to scripts.
    """
    if authorization:
        scheme, _, credentials = authorization.partition(" ")
        if scheme.lower() == _BEARER_SCHEME and credentials:
            return credentials

    cookie_token = request.cookies.get(DOCTOR_SESSION_COOKIE_NAME)
    if cookie_token:
        return cookie_token

    raise _unauthorized()


async def get_current_doctor(
    token: Annotated[str, Depends(get_doctor_session_token)],
    session: Annotated[AsyncSession, Depends(get_session)],
) -> Doctor:
    """Return the doctor authenticated by the current portal session.

    Doctor identity always comes from the session, never from the request, so
    a client cannot act on behalf of another doctor. Patient session tokens
    are stored in a different table and can never resolve here.
    """
    try:
        return await resolve_doctor_for_session(session, token=token)
    except InvalidDoctorSessionError as exc:
        raise _unauthorized() from exc
