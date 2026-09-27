import pytest
from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.doctor_linking.models import DoctorLink
from tests.factories import (
    auth_headers,
    create_doctor,
    create_doctor_code,
    signup_patient,
)

# Two doctors with two codes produce two links for one patient.
_EXPECTED_LINK_COUNT = 2


@pytest.mark.asyncio
async def test_create_link_requires_authentication(client: AsyncClient) -> None:
    response = await client.post("/doctor-links", json={"doctor_code": "ABC123"})

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_valid_doctor_code_creates_a_pending_link(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db)
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    patient_id, token = await signup_patient(client)

    response = await client.post(
        "/doctor-links",
        json={"doctor_code": "  abc123 "},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CREATED
    body = response.json()
    assert body["doctor_id"] == doctor.id
    assert body["status"] == "pending"

    link = await db.scalar(select(DoctorLink).where(DoctorLink.doctor_id == doctor.id))
    assert link is not None
    assert link.patient_id == patient_id
    assert link.status == "pending"


@pytest.mark.asyncio
async def test_unknown_doctor_code_is_rejected(client: AsyncClient) -> None:
    _, token = await signup_patient(client)

    response = await client.post(
        "/doctor-links",
        json={"doctor_code": "NOPE99"},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.NOT_FOUND


@pytest.mark.asyncio
async def test_inactive_doctor_code_is_rejected(client: AsyncClient, db: AsyncSession) -> None:
    doctor = await create_doctor(db)
    await create_doctor_code(db, doctor_id=doctor.id, code="OLD123", is_active=False)
    _, token = await signup_patient(client)

    response = await client.post(
        "/doctor-links",
        json={"doctor_code": "OLD123"},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CONFLICT


@pytest.mark.asyncio
async def test_duplicate_pending_link_is_prevented(client: AsyncClient, db: AsyncSession) -> None:
    doctor = await create_doctor(db)
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    _, token = await signup_patient(client)
    headers = auth_headers(token)

    first = await client.post("/doctor-links", json={"doctor_code": "ABC123"}, headers=headers)
    second = await client.post("/doctor-links", json={"doctor_code": "ABC123"}, headers=headers)

    assert first.status_code == codes.CREATED
    assert second.status_code == codes.CONFLICT


@pytest.mark.asyncio
async def test_patient_sees_one_link_per_doctor(client: AsyncClient, db: AsyncSession) -> None:
    first_doctor = await create_doctor(db, name="Dr. One")
    second_doctor = await create_doctor(db, name="Dr. Two")
    await create_doctor_code(db, doctor_id=first_doctor.id, code="ONE111")
    await create_doctor_code(db, doctor_id=second_doctor.id, code="TWO222")
    _, token = await signup_patient(client)
    headers = auth_headers(token)

    await client.post("/doctor-links", json={"doctor_code": "ONE111"}, headers=headers)
    await client.post("/doctor-links", json={"doctor_code": "TWO222"}, headers=headers)
    response = await client.get("/doctor-links", headers=headers)

    assert response.status_code == codes.OK
    links = response.json()
    assert len(links) == _EXPECTED_LINK_COUNT
    assert {link["doctor_id"] for link in links} == {first_doctor.id, second_doctor.id}
    assert all(link["status"] == "pending" for link in links)


@pytest.mark.asyncio
async def test_multiple_patients_can_link_to_the_same_doctor(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db)
    await create_doctor_code(db, doctor_id=doctor.id, code="SHARED")
    _, first_token = await signup_patient(client, email="first@example.com")
    second_id, second_token = await signup_patient(client, email="second@example.com")

    first = await client.post(
        "/doctor-links",
        json={"doctor_code": "SHARED"},
        headers=auth_headers(first_token),
    )
    second = await client.post(
        "/doctor-links",
        json={"doctor_code": "SHARED"},
        headers=auth_headers(second_token),
    )

    assert first.status_code == codes.CREATED
    assert second.status_code == codes.CREATED
    link = await db.scalar(select(DoctorLink).where(DoctorLink.patient_id == second_id))
    assert link is not None
    assert link.doctor_id == doctor.id


@pytest.mark.asyncio
async def test_patient_cannot_see_another_patients_links(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db)
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    _, first_token = await signup_patient(client, email="first@example.com")
    _, second_token = await signup_patient(client, email="second@example.com")
    await client.post(
        "/doctor-links",
        json={"doctor_code": "ABC123"},
        headers=auth_headers(first_token),
    )

    response = await client.get("/doctor-links", headers=auth_headers(second_token))

    assert response.status_code == codes.OK
    assert response.json() == []
