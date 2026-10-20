"""The mechanism shared by every authenticated session, whoever owns it.

A patient and a doctor each sign in with an email, a password and an opaque
token, and each keeps that token in their own table under their own cookie.
What is *how* a session is carried, checked and handed back is identical, so
it lives here once.

What is deliberately **not** here: the tables, the cookie names, the session
lifetimes and the error types. Those are the boundary between the two roles,
and a doctor token must never authenticate a patient request. Keeping them
apart is a property of the schema, not of this module.
"""

from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, cast

from fastapi import Header, HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.auth.security import hash_session_token

BEARER_SCHEME = "bearer"

ERR_AUTH_REQUIRED = "Authentication required."
ERR_DOCTOR_AUTH_REQUIRED = "Doctor authentication required."
ERR_NO_SESSION_OWNER = "No active owner for that session token."


def unauthorized(detail: str) -> HTTPException:
    """The 401 every unauthenticated request answers with."""
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def extract_session_token(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
    *,
    cookie_name: str,
) -> str:
    """Return the raw session token from the Authorization header or the cookie.

    The applications send a bearer token. The same token is also set as an
    HTTP-only cookie so browser clients work without exposing it to scripts.
    """
    if authorization:
        scheme, _, credentials = authorization.partition(" ")
        if scheme.lower() == BEARER_SCHEME and credentials:
            return credentials

    cookie_token = request.cookies.get(cookie_name)
    if cookie_token:
        return cookie_token

    raise unauthorized(ERR_AUTH_REQUIRED)


def set_session_cookie(
    response: Response,
    *,
    cookie_name: str,
    token: str,
    expires_at: datetime,
    secure: bool,
) -> None:
    """Hand the session token back as an HTTP-only cookie."""
    response.set_cookie(
        key=cookie_name,
        value=token,
        httponly=True,
        secure=secure,
        samesite="lax",
        path="/",
        expires=expires_at,
    )


def delete_session_cookie(response: Response, *, cookie_name: str) -> None:
    """Take the session cookie back."""
    response.delete_cookie(key=cookie_name, path="/", samesite="lax")


async def resolve_owner_for_session[TOwner](  # noqa: PLR0913 - the models are the point
    session: AsyncSession,
    *,
    token_hash: str,
    owner_model: type[Any],
    session_model: type[Any],
    owner_id_column: Any,
) -> TOwner:
    """Return the active owner of a usable session token.

    Both roles store a digest of the token on their own session table, and
    both require an unrevoked, unexpired session belonging to an active
    account. Only the two models differ, so they are passed in.

    A single indexed lookup resolves the session and its owner, and the query
    only succeeds while the session is unrevoked, unexpired and the account is
    active.
    """
    statement = (
        select(owner_model)
        .join(session_model, owner_id_column == owner_model.id)
        .where(
            session_model.token_hash == token_hash,
            session_model.revoked_at.is_(None),
            session_model.expires_at > datetime.now(UTC),
            owner_model.is_active.is_(True),
        )
        .limit(1)
    )
    owner = await session.scalar(statement)
    if owner is None:
        raise LookupError(ERR_NO_SESSION_OWNER)
    return cast(TOwner, owner)


async def revoke_session_token(
    session: AsyncSession,
    *,
    token_hash: str,
    session_model: type[Any],
) -> None:
    """Revoke a session. Unknown or already-revoked tokens are ignored."""
    session_row = await session.scalar(
        select(session_model).where(
            session_model.token_hash == token_hash,
            session_model.revoked_at.is_(None),
        )
    )
    if session_row is None:
        return

    session_row.revoked_at = datetime.now(UTC)
    await session.commit()


async def issue_session_token(  # noqa: PLR0913 - the models are the point
    session: AsyncSession,
    *,
    session_model: type[Any],
    owner_id_column: str,
    owner_id: int,
    token: str,
    ttl: timedelta,
) -> tuple[str, datetime]:
    """Persist a new session, returning its raw token and expiry.

    Only the digest of the token is stored. ``owner_id_column`` is the name of
    the foreign key on the session table (``patient_id`` for one role,
    ``doctor_id`` for the other).
    """
    moment = datetime.now(UTC)
    expires_at = moment + ttl
    session.add(
        session_model(
            **{owner_id_column: owner_id},
            token_hash=hash_session_token(token),
            expires_at=expires_at,
            created_at=moment,
        )
    )
    await session.flush()
    return token, expires_at
