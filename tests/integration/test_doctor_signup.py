"""Doctor signup and personal link code tests."""

import pytest
from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.doctor.service import _DOCTOR_CODE_ALPHABET, DOCTOR_CODE_LENGTH
from neurosync.modules.doctor_linking.models import DoctorCode
from tests.factories import DOCTOR_EMAIL, DOCTOR_PASSWORD, create_doctor

SIGNUP_PAYLOAD = {
    "name": "Dr. New",
    "email": "new.doctor@example.com",
    "password": "a-clinical-passphrase",
}


@pytest.mark.asyncio
async def test_signup_creates_account_code_and_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    response = await client.post("/doctor/auth/signup", json=SIGNUP_PAYLOAD)

    assert response.status_code == codes.CREATED, response.text
    body = response.json()
    assert body["doctor"]["name"] == "Dr. New"
    assert body["doctor"]["email"] == "new.doctor@example.com"
    assert body["access_token"]

    code = body["doctor"]["code"]
    assert isinstance(code, str)
    assert len(code) == DOCTOR_CODE_LENGTH
    assert all(char in _DOCTOR_CODE_ALPHABET for char in code)

    stored = await db.scalar(select(DoctorCode).where(DoctorCode.code == code))
    assert stored is not None
    assert stored.is_active is True


@pytest.mark.asyncio
async def test_signup_rejects_a_duplicate_email(client: AsyncClient, db: AsyncSession) -> None:
    await create_doctor(db, email="new.doctor@example.com")

    response = await client.post("/doctor/auth/signup", json=SIGNUP_PAYLOAD)

    assert response.status_code == codes.CONFLICT


@pytest.mark.asyncio
async def test_signup_rejects_a_weak_password(client: AsyncClient) -> None:
    response = await client.post(
        "/doctor/auth/signup",
        json={**SIGNUP_PAYLOAD, "password": "short"},
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


@pytest.mark.asyncio
async def test_generated_codes_differ_between_doctors(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    first = await client.post("/doctor/auth/signup", json=SIGNUP_PAYLOAD)
    second = await client.post(
        "/doctor/auth/signup",
        json={**SIGNUP_PAYLOAD, "name": "Dr. Second", "email": "other.doctor@example.com"},
    )

    assert first.status_code == codes.CREATED
    assert second.status_code == codes.CREATED
    first_code = first.json()["doctor"]["code"]
    second_code = second.json()["doctor"]["code"]
    assert first_code != second_code

    codes_in_db = (await db.scalars(select(DoctorCode.code))).all()
    assert len(codes_in_db) == 2


@pytest.mark.asyncio
async def test_login_and_me_return_the_doctor_code(client: AsyncClient) -> None:
    signup = await client.post("/doctor/auth/signup", json=SIGNUP_PAYLOAD)
    expected_code = signup.json()["doctor"]["code"]

    login = await client.post(
        "/doctor/auth/login",
        json={"email": "new.doctor@example.com", "password": "a-clinical-passphrase"},
    )
    assert login.status_code == codes.OK
    assert login.json()["doctor"]["code"] == expected_code

    me = await client.get(
        "/doctor/auth/me",
        headers={"Authorization": f"Bearer {login.json()['access_token']}"},
    )
    assert me.status_code == codes.OK
    assert me.json()["code"] == expected_code


@pytest.mark.asyncio
async def test_doctors_provisioned_without_a_code_report_none(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, name="Dr. Legacy", email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)

    login = await client.post(
        "/doctor/auth/login",
        json={"email": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD},
    )
    assert login.status_code == codes.OK
    assert login.json()["doctor"]["code"] is None
