"""Doctor assignment (exercise creation) endpoint tests."""

import pytest
from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.doctor_linking.models import DoctorLink
from neurosync.modules.monitoring.models import MonitoringPlan, MonitoringPlanItem
from tests.factories import (
    DOCTOR_EMAIL,
    DOCTOR_PASSWORD,
    auth_headers,
    create_doctor,
    create_doctor_link,
    login_doctor,
    signup_patient,
)

TITLE_OVERRIDE = "Morning tapping"


async def create_linked_patient(
    client: AsyncClient,
    db: AsyncSession,
    *,
    email: str = "linked.patient@example.com",
) -> tuple[int, str, int]:
    """Create a doctor and an actively linked patient; return ids and token."""
    doctor = await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    patient_id, patient_token = await signup_patient(client, email=email)
    await create_doctor_link(
        db,
        doctor_id=doctor.id,
        patient_id=patient_id,
        status="active",
    )
    return patient_id, patient_token, doctor.id


@pytest.mark.asyncio
async def test_assignments_require_authentication(client: AsyncClient) -> None:
    response = await client.post(
        "/doctor/patients/1/assignments",
        json={"duration_seconds": 30},
    )

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_doctor_assigns_finger_tapping_with_custom_duration(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"title": TITLE_OVERRIDE, "duration_seconds": 60},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CREATED, response.text
    body = response.json()
    assert body["title"] == TITLE_OVERRIDE
    assert body["assessment_title"] == "Finger Tapping"
    assert body["duration_seconds"] == 60
    assert body["status"] == "active"

    plan = await db.scalar(select(MonitoringPlan).where(MonitoringPlan.id == body["id"]))
    assert plan is not None
    assert plan.doctor_id is not None
    item = await db.scalar(select(MonitoringPlanItem).where(MonitoringPlanItem.plan_id == plan.id))
    assert item is not None
    assert item.duration_seconds == 60


@pytest.mark.asyncio
async def test_assignment_defaults_to_the_assessment_title(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 45},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CREATED
    assert response.json()["title"] == "Finger Tapping"


@pytest.mark.asyncio
async def test_patient_plan_reflects_the_assigned_duration(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 90},
        headers=auth_headers(token),
    )
    assert created.status_code == codes.CREATED

    plan = await client.get("/monitoring/plan", headers=auth_headers(patient_token))

    assert plan.status_code == codes.OK
    items = plan.json()["items"]
    assert len(items) == 1
    assert items[0]["duration_seconds"] == 90
    assert items[0]["assessment"]["default_duration_seconds"] == 30


@pytest.mark.asyncio
async def test_assignment_listing_is_newest_first(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)

    first = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"title": "First", "duration_seconds": 30},
        headers=headers,
    )
    second = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"title": "Second", "duration_seconds": 45},
        headers=headers,
    )
    assert first.status_code == codes.CREATED
    assert second.status_code == codes.CREATED

    listing = await client.get(
        f"/doctor/patients/{patient_id}/assignments",
        headers=headers,
    )

    assert listing.status_code == codes.OK
    titles = [entry["title"] for entry in listing.json()]
    assert titles == ["Second", "First"]


@pytest.mark.asyncio
async def test_cannot_assign_to_a_patient_outside_the_roster(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    token = await login_doctor(client)
    stranger_id, _stranger_token = await signup_patient(client)

    response = await client.post(
        f"/doctor/patients/{stranger_id}/assignments",
        json={"duration_seconds": 30},
        headers=auth_headers(token),
    )

    # Ownership-safe: a patient who never linked looks like a missing patient.
    assert response.status_code == codes.NOT_FOUND


@pytest.mark.asyncio
async def test_cannot_assign_to_another_doctors_patient(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, owner_doctor_id = await create_linked_patient(client, db)
    link = await db.scalar(select(DoctorLink).where(DoctorLink.patient_id == patient_id))
    assert link is not None
    assert link.doctor_id == owner_doctor_id

    await create_doctor(
        db,
        name="Dr. Other",
        email="other.doctor@example.com",
        password=DOCTOR_PASSWORD,
    )
    intruder_token = await login_doctor(client, email="other.doctor@example.com")

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 30},
        headers=auth_headers(intruder_token),
    )

    assert response.status_code == codes.NOT_FOUND


@pytest.mark.asyncio
async def test_assignment_rejects_durations_outside_the_allowed_range(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)

    too_short = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 5},
        headers=headers,
    )
    too_long = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 601},
        headers=headers,
    )
    missing = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={},
        headers=headers,
    )

    assert too_short.status_code == codes.UNPROCESSABLE_ENTITY
    assert too_long.status_code == codes.UNPROCESSABLE_ENTITY
    assert missing.status_code == codes.CREATED  # default duration applies
    assert missing.json()["duration_seconds"] == 30


@pytest.mark.asyncio
async def test_assignment_rejects_unsupported_assessments(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "spiral_drawing", "duration_seconds": 30},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CONFLICT
