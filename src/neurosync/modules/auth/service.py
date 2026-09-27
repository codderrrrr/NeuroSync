"""Patient authentication use cases.

Each use case that writes owns its transaction, so a failure surfaces where the
write happens rather than after the response has been produced.
"""

import asyncio
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.auth.models import Patient, PatientSession
from neurosync.modules.auth.security import (
    SESSION_TTL,
    generate_session_token,
    hash_password,
    hash_session_token,
    verify_password,
)

# Verifying against this hash when no account exists keeps response time similar
# for known and unknown emails, which resists account enumeration.
_DUMMY_PASSWORD_HASH = hash_password("neurosync-timing-equalisation")


class AuthError(Exception):
    """Base class for patient authentication errors."""


class EmailAlreadyRegisteredError(AuthError):
    """Raised when a signup email is already registered."""


class InvalidCredentialsError(AuthError):
    """Raised when the email/password pair is not valid."""


class InactivePatientError(AuthError):
    """Raised when the account exists but is not active."""


class InvalidSessionError(AuthError):
    """Raised when a session token is absent, revoked, expired or not owned."""


def _now() -> datetime:
    return datetime.now(UTC)


def normalize_email(email: str) -> str:
    """Normalise an email address for storage and lookup."""
    return email.strip().lower()


async def _issue_session(session: AsyncSession, patient_id: int) -> tuple[str, datetime]:
    """Persist a new session, returning its raw token and expiry."""
    token = generate_session_token()
    now = _now()
    expires_at = now + SESSION_TTL
    session.add(
        PatientSession(
            patient_id=patient_id,
            token_hash=hash_session_token(token),
            expires_at=expires_at,
            created_at=now,
        )
    )
    await session.flush()
    return token, expires_at


async def signup_patient(
    *,
    session: AsyncSession,
    name: str,
    email: str,
    password: str,
) -> tuple[Patient, str, datetime]:
    """Create a patient account and an authenticated session."""
    normalized_email = normalize_email(email)
    existing_patient_id = await session.scalar(
        select(Patient.id).where(Patient.email == normalized_email)
    )
    if existing_patient_id is not None:
        raise EmailAlreadyRegisteredError

    password_hash = await asyncio.to_thread(hash_password, password)
    now = _now()
    patient = Patient(
        email=normalized_email,
        password_hash=password_hash,
        name=name,
        is_active=True,
        created_at=now,
        updated_at=now,
    )
    session.add(patient)
    await session.flush()

    token, expires_at = await _issue_session(session, patient.id)
    await session.commit()
    return patient, token, expires_at


async def login_patient(
    *,
    session: AsyncSession,
    email: str,
    password: str,
) -> tuple[Patient, str, datetime]:
    """Verify credentials and start a session."""
    patient = await session.scalar(select(Patient).where(Patient.email == normalize_email(email)))
    if patient is None:
        await asyncio.to_thread(verify_password, password, _DUMMY_PASSWORD_HASH)
        raise InvalidCredentialsError

    if not await asyncio.to_thread(verify_password, password, patient.password_hash):
        raise InvalidCredentialsError

    if not patient.is_active:
        raise InactivePatientError

    token, expires_at = await _issue_session(session, patient.id)
    await session.commit()
    return patient, token, expires_at


async def resolve_patient_for_session(session: AsyncSession, *, token: str) -> Patient:
    """Return the active patient that owns a usable session token.

    A single indexed lookup resolves the session and its patient, and the query
    only succeeds while the session is unrevoked, unexpired and the account is
    active.
    """
    statement = (
        select(Patient)
        .join(PatientSession, PatientSession.patient_id == Patient.id)
        .where(
            PatientSession.token_hash == hash_session_token(token),
            PatientSession.revoked_at.is_(None),
            PatientSession.expires_at > _now(),
            Patient.is_active.is_(True),
        )
        .limit(1)
    )
    patient = await session.scalar(statement)
    if patient is None:
        raise InvalidSessionError
    return patient


async def revoke_session(session: AsyncSession, *, token: str) -> None:
    """Revoke a session. Unknown or already-revoked tokens are ignored."""
    patient_session = await session.scalar(
        select(PatientSession).where(
            PatientSession.token_hash == hash_session_token(token),
            PatientSession.revoked_at.is_(None),
        )
    )
    if patient_session is None:
        return

    patient_session.revoked_at = _now()
    await session.commit()
