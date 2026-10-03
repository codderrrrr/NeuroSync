"""Helpers for data the public API cannot create directly (doctors, doctor
codes, and some test-only plan shapes).

Patient accounts are always created through the public API so tests exercise
the same path the application uses.
"""

from dataclasses import dataclass
from datetime import datetime

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
    """Create a doctor code directly, for tests that do not sign a doctor up."""
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


async def create_default_plan(
    session: AsyncSession,
    patient_id: int,
    *,
    duration_seconds: int | None = None,
) -> int:
    """Create the deterministic default monitoring plan for a patient.

    Mirrors the development seed: one active plan whose only item is the
    supported finger-tapping assessment. Pass ``duration_seconds`` to give the
    item a doctor-assigned recording target; ``None`` leaves the catalog
    default in place. Returns the plan item id.
    """
    definitions = await seed_assessment_catalog(session)
    by_slug = {definition.slug: definition.id for definition in definitions}
    finger_tapping_id = by_slug["finger_tapping"]
    plan = await monitoring_service.create_plan(
        session=session,
        patient_id=patient_id,
        title="Daily motor check-in",
        assessment_definition_ids=[finger_tapping_id],
        duration_seconds=duration_seconds,
    )
    items = list(
        await session.scalars(
            select(MonitoringPlanItem).where(MonitoringPlanItem.plan_id == plan.id)
        )
    )
    return int(items[0].id)


def steady_taps(count: int = 30, interval_ms: int = 1000) -> list[dict[str, object]]:
    """A steady recording: taps every ``interval_ms`` for ``count`` taps.

    The features are fully determined by ``interval_ms`` and ``count``, so a
    test can stage a patient's history precisely by choosing them.
    """
    return [{"event_type": "tap", "offset_ms": i * interval_ms} for i in range(count)]


async def create_medication_record(
    client: AsyncClient,
    *,
    token: str,
    name: str = "Levodopa",
    dose_label: str | None = "100mg",
    frequency_label: str | None = "4 times daily",
) -> dict[str, object]:
    """Record a medication through the API and return the created row."""
    response = await client.post(
        "/medications",
        headers=auth_headers(token),
        json={
            "name": name,
            "dose_label": dose_label,
            "frequency_label": frequency_label,
        },
    )
    assert response.status_code == codes.CREATED, response.text
    return dict(response.json())


@dataclass(frozen=True)
class ReportedDose:
    """What a patient reported about one dose.

    Grouped into one value so a test reads as "this patient said they took it
    30 minutes ago" rather than as a list of positional arguments.
    """

    adherence: str = "taken"
    taken_at: datetime | None = None
    scheduled_at: datetime | None = None


async def create_medication_event(
    client: AsyncClient,
    *,
    token: str,
    medication_id: int,
    dose: ReportedDose | None = None,
) -> dict[str, object]:
    """Record one reported dose through the API and return the created row.

    Defaults to a dose with no timestamps, which is what a patient who cannot
    recall the time actually reports.
    """
    reported = dose or ReportedDose()
    payload: dict[str, object] = {
        "medication_id": medication_id,
        "adherence": reported.adherence,
    }
    if reported.taken_at is not None:
        payload["taken_at"] = reported.taken_at.isoformat()
    if reported.scheduled_at is not None:
        payload["scheduled_at"] = reported.scheduled_at.isoformat()
    response = await client.post(
        "/medications/events",
        headers=auth_headers(token),
        json=payload,
    )
    assert response.status_code == codes.CREATED, response.text
    return dict(response.json())


async def complete_a_session(
    client: AsyncClient,
    *,
    token: str,
    plan_item_id: int,
    events: list[dict[str, object]],
    medication_event_id: int | None = None,
) -> dict[str, object]:
    """Start and complete one monitoring session, returning the response body.

    Returns the session body including its ``longitudinal`` block, which is
    what the longitudinal tests assert against. ``medication_event_id``
    attaches a reported dose as supporting context; leaving it out must leave
    the medication context unknown.
    """
    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    assert started.status_code == codes.CREATED, started.text
    completed = await client.post(
        f"/monitoring/sessions/{started.json()['id']}/complete",
        headers=auth_headers(token),
        json={"events": events, "medication_event_id": medication_event_id},
    )
    assert completed.status_code == codes.OK, completed.text
    return completed.json()


async def supported_assessment_ids(session: AsyncSession) -> list[int]:
    """Return definition ids for every supported assessment in the catalog."""
    definitions = await seed_assessment_catalog(session)
    return [
        definition.id for definition in definitions if definition.slug in SUPPORTED_ASSESSMENT_SLUGS
    ]
