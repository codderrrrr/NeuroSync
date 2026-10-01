"""Helpers for data the public API cannot create yet (doctors, doctor codes).

Patient accounts are always created through the public API so tests exercise
the same path the application uses.
"""

from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import Doctor
from neurosync.modules.auth.security import hash_password
from neurosync.modules.doctor_linking.models import DoctorCode, DoctorLink
from neurosync.modules.monitoring import service as monitoring_service
from neurosync.modules.monitoring.assessment_catalog import SUPPORTED_ASSESSMENT_SLUGS
from neurosync.modules.monitoring.models import AssessmentDefinition, MonitoringPlanItem

VALID_PASSWORD = "correct-horse-battery"
DEFAULT_EMAIL = "patient@example.com"
DOCTOR_PASSWORD = "clinical-workspace-pass"
DOCTOR_EMAIL = "doctor@example.com"


def auth_headers(token: str) -> dict[str, str]:
    """Return bearer authentication headers for a session token."""
    return {"Authorization": f"Bearer {token}"}


async def create_doctor(
    session: AsyncSession,
    *,
    name: str = "Dr. Test",
    email: str | None = None,
    password: str | None = None,
    is_active: bool = True,
) -> Doctor:
    """Create a doctor, without portal credentials by default.

    Pass ``email`` and ``password`` to give the doctor portal credentials so
    they can sign in through ``/doctor/auth/login``.
    """
    doctor = Doctor(
        name=name,
        email=email,
        password_hash=hash_password(password) if password is not None else None,
        is_active=is_active,
    )
    session.add(doctor)
    await session.commit()
    await session.refresh(doctor)
    return doctor


async def create_doctor_link(
    session: AsyncSession,
    *,
    doctor_id: int,
    patient_id: int,
    status: str = "pending",
) -> DoctorLink:
    """Create a doctor link directly, as a patient request would."""
    link = DoctorLink(doctor_id=doctor_id, patient_id=patient_id, status=status)
    session.add(link)
    await session.commit()
    await session.refresh(link)
    return link


async def login_doctor(
    client: AsyncClient,
    *,
    email: str = DOCTOR_EMAIL,
    password: str = DOCTOR_PASSWORD,
) -> str:
    """Log a doctor in through the API and return their session token."""
    response = await client.post("/doctor/auth/login", json={"email": email, "password": password})
    assert response.status_code == codes.OK, response.text
    return str(response.json()["access_token"])


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


async def seed_assessment_catalog(session: AsyncSession) -> list[AssessmentDefinition]:
    """Insert the code catalog into the database and return the rows."""
    await monitoring_service.seed_assessment_catalog(session)
    definitions = list(await session.scalars(select(AssessmentDefinition)))
    return definitions


async def create_default_plan(session: AsyncSession, patient_id: int) -> int:
    """Create the deterministic default monitoring plan for a patient.

    Mirrors the development seed: one active plan whose only item is the
    supported finger-tapping assessment. Returns the plan item id.
    """
    definitions = await seed_assessment_catalog(session)
    by_slug = {definition.slug: definition.id for definition in definitions}
    finger_tapping_id = by_slug["finger_tapping"]
    plan = await monitoring_service.create_plan(
        session=session,
        patient_id=patient_id,
        title="Daily motor check-in",
        assessment_definition_ids=[finger_tapping_id],
    )
    items = list(
        await session.scalars(
            select(MonitoringPlanItem).where(MonitoringPlanItem.plan_id == plan.id)
        )
    )
    return int(items[0].id)


async def supported_assessment_ids(session: AsyncSession) -> list[int]:
    """Return definition ids for every supported assessment in the catalog."""
    definitions = await seed_assessment_catalog(session)
    return [
        definition.id for definition in definitions if definition.slug in SUPPORTED_ASSESSMENT_SLUGS
    ]
