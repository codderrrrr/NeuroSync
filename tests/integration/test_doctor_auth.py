from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.auth.security import hash_session_token
from neurosync.modules.doctor.models import DoctorSession
from tests.factories import (
    DOCTOR_EMAIL,
    DOCTOR_PASSWORD,
    auth_headers,
    create_doctor,
    login_doctor,
    signup_patient,
)


@pytest.mark.asyncio
async def test_login_returns_an_authenticated_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, name="Dr. Chen", email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)

    response = await client.post(
        "/doctor/auth/login",
        json={"email": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD},
    )

    assert response.status_code == codes.OK, response.text
    body = response.json()
    assert body["doctor"]["name"] == "Dr. Chen"
    assert body["doctor"]["email"] == DOCTOR_EMAIL
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert body["expires_at"]

    session_row = await db.scalar(select(DoctorSession))
    assert session_row is not None
    # Only the hash of the token is persisted.
    assert session_row.token_hash == hash_session_token(body["access_token"])
    assert session_row.token_hash != body["access_token"]


@pytest.mark.asyncio
async def test_login_returns_every_field_the_doctor_app_parses(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Regression: the doctor payload must carry every field the app parses.

    ``Doctor.fromJson`` in the Flutter app reads ``created_at`` as a required
    String. When the API omitted it, a successful login raised a ``TypeError``
    that the controller's catch-all turned into "Something went wrong", and the
    session token was never stored -- the app could not sign a doctor in at all.
    """
    await create_doctor(db, name="Dr. Chen", email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)

    response = await client.post(
        "/doctor/auth/login",
        json={"email": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD},
    )

    assert response.status_code == codes.OK, response.text
    doctor = response.json()["doctor"]
    for field in ("id", "name", "email", "created_at", "code"):
        assert field in doctor, f"doctor payload is missing {field!r}: {doctor}"
    datetime.fromisoformat(doctor["created_at"])


@pytest.mark.asyncio
async def test_signup_and_me_return_the_same_doctor_fields_as_login(
    client: AsyncClient,
) -> None:
    """Signup and /me share one doctor builder, so they must agree with login."""
    signup = await client.post(
        "/doctor/auth/signup",
        json={
            "name": "Dr. Osei",
            "email": "osei@example.com",
            "password": DOCTOR_PASSWORD,
        },
    )
    assert signup.status_code == codes.CREATED, signup.text
    token = signup.json()["access_token"]

    me = await client.get("/doctor/auth/me", headers=auth_headers(token))

    assert me.status_code == codes.OK, me.text
    assert me.json() == signup.json()["doctor"]


@pytest.mark.asyncio
async def test_login_is_case_insensitive_about_the_email(
    client: AsyncClient, db: AsyncSession
) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)

    response = await client.post(
        "/doctor/auth/login",
        json={"email": "Doctor@Example.com", "password": DOCTOR_PASSWORD},
    )

    assert response.status_code == codes.OK


@pytest.mark.asyncio
async def test_login_rejects_a_wrong_password(client: AsyncClient, db: AsyncSession) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)

    response = await client.post(
        "/doctor/auth/login",
        json={"email": DOCTOR_EMAIL, "password": "a-wrong-password"},
    )

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_login_rejects_an_unknown_email(client: AsyncClient) -> None:
    response = await client.post(
        "/doctor/auth/login",
        json={"email": "nobody@example.com", "password": DOCTOR_PASSWORD},
    )

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_login_rejects_a_doctor_without_credentials(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # Doctors provisioned before the portal exist have no password.
    await create_doctor(db, name="Dr. Legacy", email=None, password=None)

    response = await client.post(
        "/doctor/auth/login",
        json={"email": "legacy@example.com", "password": DOCTOR_PASSWORD},
    )

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_login_rejects_an_inactive_doctor(client: AsyncClient, db: AsyncSession) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD, is_active=False)

    response = await client.post(
        "/doctor/auth/login",
        json={"email": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD},
    )

    assert response.status_code == codes.FORBIDDEN


@pytest.mark.asyncio
async def test_me_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/doctor/auth/me")

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_me_returns_the_authenticated_doctor(client: AsyncClient, db: AsyncSession) -> None:
    await create_doctor(db, name="Dr. Osei", email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    token = await login_doctor(client)

    response = await client.get("/doctor/auth/me", headers=auth_headers(token))

    assert response.status_code == codes.OK
    body = response.json()
    assert body["name"] == "Dr. Osei"
    assert body["email"] == DOCTOR_EMAIL


@pytest.mark.asyncio
async def test_cookie_session_authenticates_without_a_bearer_token(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    await login_doctor(client)

    # The login response set the portal cookie; no explicit header is sent.
    response = await client.get("/doctor/auth/me")

    assert response.status_code == codes.OK


@pytest.mark.asyncio
async def test_logout_revokes_the_session(client: AsyncClient, db: AsyncSession) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    token = await login_doctor(client)
    headers = auth_headers(token)

    response = await client.post("/doctor/auth/logout", headers=headers)

    assert response.status_code == codes.NO_CONTENT
    after = await client.get("/doctor/auth/me", headers=headers)
    assert after.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_logout_without_a_session_is_rejected(client: AsyncClient) -> None:
    response = await client.post("/doctor/auth/logout")

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_an_expired_doctor_session_cannot_authenticate(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    token = await login_doctor(client)
    session_row = await db.scalar(select(DoctorSession))
    assert session_row is not None
    session_row.expires_at = datetime.now(UTC) - timedelta(minutes=1)
    await db.commit()

    response = await client.get("/doctor/auth/me", headers=auth_headers(token))

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_a_patient_session_cannot_authenticate_doctor_endpoints(
    client: AsyncClient,
) -> None:
    _, patient_token = await signup_patient(client)

    response = await client.get("/doctor/auth/me", headers=auth_headers(patient_token))

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_a_doctor_session_cannot_authenticate_patient_endpoints(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    doctor_token = await login_doctor(client)

    response = await client.get("/auth/me", headers=auth_headers(doctor_token))

    assert response.status_code == codes.UNAUTHORIZED
