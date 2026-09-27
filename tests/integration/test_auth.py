from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient, codes
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.auth.models import Patient, PatientSession
from neurosync.modules.auth.security import hash_session_token, verify_password
from tests.factories import DEFAULT_EMAIL, VALID_PASSWORD, auth_headers, signup_patient

SIGNUP_PAYLOAD = {
    "name": "Ada Lovelace",
    "email": DEFAULT_EMAIL,
    "password": VALID_PASSWORD,
}

# Signup creates one session; a following login adds a second.
_EXPECTED_SESSIONS_AFTER_LOGIN = 2


@pytest.mark.asyncio
async def test_signup_creates_account_and_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    response = await client.post("/auth/signup", json=SIGNUP_PAYLOAD)

    assert response.status_code == codes.CREATED
    body = response.json()
    assert body["patient"]["email"] == DEFAULT_EMAIL
    assert body["patient"]["name"] == "Ada Lovelace"
    assert body["token_type"] == "bearer"
    assert body["access_token"]

    patient = await db.scalar(select(Patient).where(Patient.email == DEFAULT_EMAIL))
    assert patient is not None
    session_row = await db.scalar(
        select(PatientSession).where(PatientSession.patient_id == patient.id)
    )
    assert session_row is not None
    assert session_row.token_hash == hash_session_token(body["access_token"])
    assert session_row.token_hash != body["access_token"]
    assert session_row.revoked_at is None


@pytest.mark.asyncio
async def test_signup_sets_an_httponly_session_cookie(client: AsyncClient) -> None:
    response = await client.post("/auth/signup", json=SIGNUP_PAYLOAD)

    assert response.status_code == codes.CREATED
    cookie_header = response.headers["set-cookie"]
    assert "neurosync_session=" in cookie_header
    assert "HttpOnly" in cookie_header


@pytest.mark.asyncio
async def test_signup_rejects_duplicate_email(client: AsyncClient) -> None:
    first = await client.post("/auth/signup", json=SIGNUP_PAYLOAD)
    second = await client.post("/auth/signup", json=SIGNUP_PAYLOAD)

    assert first.status_code == codes.CREATED
    assert second.status_code == codes.CONFLICT


@pytest.mark.asyncio
async def test_signup_rejects_duplicate_email_regardless_of_case(client: AsyncClient) -> None:
    first = await client.post("/auth/signup", json=SIGNUP_PAYLOAD)
    second = await client.post(
        "/auth/signup",
        json={**SIGNUP_PAYLOAD, "email": "Patient@Example.com"},
    )

    assert first.status_code == codes.CREATED
    assert second.status_code == codes.CONFLICT


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "override",
    [
        {"email": "not-an-email"},
        {"password": "too-short"},
        {"name": "   "},
    ],
)
async def test_signup_rejects_invalid_input(
    client: AsyncClient,
    override: dict[str, str],
) -> None:
    response = await client.post("/auth/signup", json={**SIGNUP_PAYLOAD, **override})

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


@pytest.mark.asyncio
async def test_signup_stores_only_a_password_hash(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await signup_patient(client)

    patient = await db.scalar(select(Patient).where(Patient.email == DEFAULT_EMAIL))
    assert patient is not None
    assert patient.password_hash != VALID_PASSWORD
    assert VALID_PASSWORD not in patient.password_hash
    assert verify_password(VALID_PASSWORD, patient.password_hash) is True
    assert verify_password("another-wrong-password", patient.password_hash) is False


@pytest.mark.asyncio
async def test_login_creates_an_additional_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await signup_patient(client)

    response = await client.post(
        "/auth/login",
        json={"email": DEFAULT_EMAIL, "password": VALID_PASSWORD},
    )

    assert response.status_code == codes.OK
    assert response.json()["access_token"]
    session_count = await db.scalar(select(func.count()).select_from(PatientSession))
    assert session_count == _EXPECTED_SESSIONS_AFTER_LOGIN


@pytest.mark.asyncio
async def test_login_rejects_incorrect_password(client: AsyncClient) -> None:
    await signup_patient(client)

    response = await client.post(
        "/auth/login",
        json={"email": DEFAULT_EMAIL, "password": "definitely-wrong"},
    )

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_login_rejects_unknown_email(client: AsyncClient) -> None:
    response = await client.post(
        "/auth/login",
        json={"email": "nobody@example.com", "password": VALID_PASSWORD},
    )

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_login_rejects_inactive_patient(client: AsyncClient, db: AsyncSession) -> None:
    await signup_patient(client)
    patient = await db.scalar(select(Patient).where(Patient.email == DEFAULT_EMAIL))
    assert patient is not None
    patient.is_active = False
    await db.commit()

    response = await client.post(
        "/auth/login",
        json={"email": DEFAULT_EMAIL, "password": VALID_PASSWORD},
    )

    assert response.status_code == codes.FORBIDDEN


@pytest.mark.asyncio
async def test_me_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/auth/me")

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_me_rejects_an_unknown_token(client: AsyncClient) -> None:
    response = await client.get("/auth/me", headers=auth_headers("not-a-real-token"))

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_me_returns_the_authenticated_patient(client: AsyncClient) -> None:
    patient_id, token = await signup_patient(client)

    response = await client.get("/auth/me", headers=auth_headers(token))

    assert response.status_code == codes.OK
    body = response.json()
    assert body["id"] == patient_id
    assert body["email"] == DEFAULT_EMAIL


@pytest.mark.asyncio
async def test_cookie_session_authenticates_without_a_bearer_token(client: AsyncClient) -> None:
    await signup_patient(client)

    response = await client.get("/auth/me")

    assert response.status_code == codes.OK
    assert response.json()["email"] == DEFAULT_EMAIL


@pytest.mark.asyncio
async def test_logout_revokes_the_session(client: AsyncClient, db: AsyncSession) -> None:
    _, token = await signup_patient(client)
    headers = auth_headers(token)

    response = await client.post("/auth/logout", headers=headers)

    assert response.status_code == codes.NO_CONTENT
    session_row = await db.scalar(
        select(PatientSession).where(PatientSession.token_hash == hash_session_token(token))
    )
    assert session_row is not None
    assert session_row.revoked_at is not None


@pytest.mark.asyncio
async def test_revoked_session_cannot_authenticate(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    headers = auth_headers(token)
    await client.post("/auth/logout", headers=headers)

    response = await client.get("/auth/me", headers=headers)

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_expired_session_cannot_authenticate(client: AsyncClient, db: AsyncSession) -> None:
    _, token = await signup_patient(client)
    session_row = await db.scalar(
        select(PatientSession).where(PatientSession.token_hash == hash_session_token(token))
    )
    assert session_row is not None
    session_row.expires_at = datetime.now(UTC) - timedelta(minutes=1)
    await db.commit()

    response = await client.get("/auth/me", headers=auth_headers(token))

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_session_of_a_deactivated_patient_cannot_authenticate(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    _, token = await signup_patient(client)
    patient = await db.scalar(select(Patient).where(Patient.email == DEFAULT_EMAIL))
    assert patient is not None
    patient.is_active = False
    await db.commit()

    response = await client.get("/auth/me", headers=auth_headers(token))

    assert response.status_code == codes.UNAUTHORIZED
