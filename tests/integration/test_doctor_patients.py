import pytest
from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.doctor_linking.models import DoctorLink
from tests.factories import (
    DEFAULT_EMAIL,
    DOCTOR_EMAIL,
    DOCTOR_PASSWORD,
    auth_headers,
    create_doctor,
    create_doctor_code,
    login_doctor,
    signup_patient,
)


def credentialed(**overrides: object) -> dict[str, object]:
    """Keyword arguments giving a doctor portal credentials."""
    return {"email": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD, **overrides}


async def request_link_through_patient_api(
    client: AsyncClient,
    *,
    code: str = "ABC123",
    email: str = DEFAULT_EMAIL,
) -> int:
    """Have a freshly signed-up patient request a link; return the patient id."""
    patient_id, token = await signup_patient(client, email=email)
    response = await client.post(
        "/doctor-links",
        json={"doctor_code": code},
        headers=auth_headers(token),
    )
    assert response.status_code == codes.CREATED, response.text
    return patient_id


@pytest.mark.asyncio
async def test_roster_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/doctor/patients")

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_pending_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/doctor/patient-links/pending")

    assert response.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_doctor_sees_the_pending_request_from_their_code(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db, **credentialed())
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    await request_link_through_patient_api(client)
    token = await login_doctor(client)

    response = await client.get("/doctor/patient-links/pending", headers=auth_headers(token))

    assert response.status_code == codes.OK
    requests = response.json()
    assert len(requests) == 1
    assert requests[0]["patient_name"] == "Test Patient"
    assert "created_at" in requests[0]
    assert isinstance(requests[0]["id"], int)


@pytest.mark.asyncio
async def test_pending_requests_list_only_the_doctors_own(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    first = await create_doctor(db, name="Dr. First", **credentialed())
    second = await create_doctor(
        db, name="Dr. Second", email="second@example.com", password=DOCTOR_PASSWORD
    )
    await create_doctor_code(db, doctor_id=first.id, code="ONE111")
    await create_doctor_code(db, doctor_id=second.id, code="TWO222")
    own_patient_id = await request_link_through_patient_api(client, code="ONE111")
    await request_link_through_patient_api(client, code="TWO222", email="other@example.com")
    token = await login_doctor(client)

    response = await client.get("/doctor/patient-links/pending", headers=auth_headers(token))

    assert response.status_code == codes.OK
    requests = response.json()
    assert len(requests) == 1
    assert requests[0]["patient_id"] == own_patient_id


@pytest.mark.asyncio
async def test_accepting_a_pending_request_actives_the_link(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db, **credentialed())
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    await request_link_through_patient_api(client)
    token = await login_doctor(client)
    link = await db.scalar(select(DoctorLink))
    assert link is not None

    response = await client.post(
        f"/doctor/patient-links/{link.id}/accept",
        headers=auth_headers(token),
    )

    assert response.status_code == codes.OK
    body = response.json()
    assert body["status"] == "active"
    assert body["accepted_at"] is not None
    assert body["patient_name"] == "Test Patient"

    # The db session cached this row before the API's own transaction; read it
    # back from the database, not the identity map.
    reloaded = await db.scalar(
        select(DoctorLink).where(DoctorLink.id == link.id).execution_options(populate_existing=True)
    )
    assert reloaded is not None
    assert reloaded.status == "active"
    assert reloaded.accepted_at is not None


@pytest.mark.asyncio
async def test_accepted_patient_appears_on_the_roster(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db, **credentialed())
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    await request_link_through_patient_api(client)
    token = await login_doctor(client)
    link = await db.scalar(select(DoctorLink))
    assert link is not None
    await client.post(f"/doctor/patient-links/{link.id}/accept", headers=auth_headers(token))

    response = await client.get("/doctor/patients", headers=auth_headers(token))

    assert response.status_code == codes.OK
    roster = response.json()
    assert len(roster) == 1
    assert roster[0]["patient_name"] == "Test Patient"
    assert roster[0]["status"] == "active"
    assert roster[0]["linked_at"]

    # Accepted patients leave the pending queue.
    pending = await client.get("/doctor/patient-links/pending", headers=auth_headers(token))
    assert pending.json() == []


@pytest.mark.asyncio
async def test_accepting_another_doctors_request_fails_safely(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    owner = await create_doctor(db, name="Dr. Owner", **credentialed())
    await create_doctor(
        db, name="Dr. Intruder", email="intruder@example.com", password=DOCTOR_PASSWORD
    )
    await create_doctor_code(db, doctor_id=owner.id, code="ABC123")
    await request_link_through_patient_api(client)
    intruder_token = await login_doctor(client, email="intruder@example.com")
    link = await db.scalar(select(DoctorLink))
    assert link is not None
    assert link.doctor_id == owner.id

    response = await client.post(
        f"/doctor/patient-links/{link.id}/accept",
        headers=auth_headers(intruder_token),
    )

    # Ownership-safe: another doctor's request looks like a missing one.
    assert response.status_code == codes.NOT_FOUND

    # And the link is untouched (read from the database, not the identity map).
    reloaded = await db.scalar(
        select(DoctorLink).where(DoctorLink.id == link.id).execution_options(populate_existing=True)
    )
    assert reloaded is not None
    assert reloaded.status == "pending"
    assert reloaded.accepted_at is None


@pytest.mark.asyncio
async def test_accepting_an_already_accepted_link_is_idempotent(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db, **credentialed())
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    await request_link_through_patient_api(client)
    token = await login_doctor(client)
    link = await db.scalar(select(DoctorLink))
    assert link is not None

    first = await client.post(
        f"/doctor/patient-links/{link.id}/accept",
        headers=auth_headers(token),
    )
    second = await client.post(
        f"/doctor/patient-links/{link.id}/accept",
        headers=auth_headers(token),
    )

    assert first.status_code == codes.OK
    assert second.status_code == codes.OK
    assert second.json()["status"] == "active"
    assert second.json()["accepted_at"] == first.json()["accepted_at"]

    links = (await db.scalars(select(DoctorLink).execution_options(populate_existing=True))).all()
    assert len(links) == 1


@pytest.mark.asyncio
async def test_accepting_an_unknown_link_returns_404(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, **credentialed())
    token = await login_doctor(client)

    response = await client.post(
        "/doctor/patient-links/9999/accept",
        headers=auth_headers(token),
    )

    assert response.status_code == codes.NOT_FOUND


@pytest.mark.asyncio
async def test_unrelated_patients_are_invisible_to_the_doctor(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await create_doctor(db, **credentialed())
    await create_doctor_code(db, doctor_id=doctor.id, code="ABC123")
    await request_link_through_patient_api(client)
    # A patient who never requested a link to anyone.
    await signup_patient(client, email="bystander@example.com", name="Bystander Patient")
    token = await login_doctor(client)

    pending = await client.get("/doctor/patient-links/pending", headers=auth_headers(token))
    roster = await client.get("/doctor/patients", headers=auth_headers(token))

    assert pending.status_code == codes.OK
    assert [entry["patient_name"] for entry in pending.json()] == ["Test Patient"]
    assert roster.status_code == codes.OK
    assert roster.json() == []


@pytest.mark.asyncio
async def test_legacy_doctor_row_without_credentials_cannot_use_the_portal(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, name="Dr. Legacy", email=None, password=None)
    await create_doctor_code(db, doctor_id=1, code="ABC123")
    await request_link_through_patient_api(client)

    # A doctor who cannot log in also cannot list or accept.
    me = await client.get("/doctor/auth/me")
    assert me.status_code == codes.UNAUTHORIZED

    roster = await client.get("/doctor/patients")
    assert roster.status_code == codes.UNAUTHORIZED
