"""Helpers for data the public API cannot create yet (doctors, doctor codes).

Patient accounts are always created through the public API so tests exercise
the same path the application uses.
"""

from httpx import AsyncClient, codes
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import Doctor
from neurosync.modules.doctor_linking.models import DoctorCode

VALID_PASSWORD = "correct-horse-battery"
DEFAULT_EMAIL = "patient@example.com"


def auth_headers(token: str) -> dict[str, str]:
    """Return bearer authentication headers for a session token."""
    return {"Authorization": f"Bearer {token}"}


async def create_doctor(session: AsyncSession, *, name: str = "Dr. Test") -> Doctor:
    """Create a doctor directly, since no doctor endpoint exists yet."""
    doctor = Doctor(name=name)
    session.add(doctor)
    await session.commit()
    await session.refresh(doctor)
    return doctor


async def create_doctor_code(
    session: AsyncSession,
    *,
    doctor_id: int,
    code: str = "ABC123",
    is_active: bool = True,
) -> DoctorCode:
    """Create a doctor code directly, since no doctor endpoint exists yet."""
    doctor_code = DoctorCode(doctor_id=doctor_id, code=code, is_active=is_active)
    session.add(doctor_code)
    await session.commit()
    await session.refresh(doctor_code)
    return doctor_code


async def signup_patient(
    client: AsyncClient,
    *,
    email: str = DEFAULT_EMAIL,
    password: str = VALID_PASSWORD,
    name: str = "Test Patient",
) -> tuple[int, str]:
    """Sign a patient up through the API and return their id and token."""
    response = await client.post(
        "/auth/signup",
        json={"name": name, "email": email, "password": password},
    )
    assert response.status_code == codes.CREATED, response.text
    body = response.json()
    return int(body["patient"]["id"]), str(body["access_token"])


async def login_patient(
    client: AsyncClient,
    *,
    email: str = DEFAULT_EMAIL,
    password: str = VALID_PASSWORD,
) -> str:
    """Log a patient in through the API and return their session token."""
    response = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert response.status_code == codes.OK, response.text
    return str(response.json()["access_token"])
