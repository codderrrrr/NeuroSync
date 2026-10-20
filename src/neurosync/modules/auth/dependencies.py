from typing import Annotated

from fastapi import Depends, Header, Request
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import get_session
from neurosync.modules.auth.models import Patient
from neurosync.modules.auth.security import SESSION_COOKIE_NAME
from neurosync.modules.auth.service import InvalidSessionError, resolve_patient_for_session
from neurosync.modules.auth.session_support import (
    ERR_AUTH_REQUIRED,
    extract_session_token,
    unauthorized,
)


async def get_session_token(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    """Return the raw session token from the Authorization header or cookie.

    The patient application sends a bearer token. The same token is also set as
    an HTTP-only cookie so browser clients work without exposing it to scripts.
    """
    return extract_session_token(request, authorization, cookie_name=SESSION_COOKIE_NAME)


async def get_current_patient(
    token: Annotated[str, Depends(get_session_token)],
    session: Annotated[AsyncSession, Depends(get_session)],
) -> Patient:
    """Return the patient authenticated by the current session.

    Patient identity always comes from the session, never from the request, so
    clients cannot act on behalf of another patient.
    """
    try:
        return await resolve_patient_for_session(session, token=token)
    except InvalidSessionError as exc:
        raise unauthorized(ERR_AUTH_REQUIRED) from exc
