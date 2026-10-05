"""Doctor assignment (exercise creation) endpoint tests."""

from collections.abc import Awaitable, Callable

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
    create_historical_plan_item,
    login_doctor,
    signup_patient,
)

TITLE_OVERRIDE = "Morning tapping"

# The `without_runner` fixture: puts a catalog assessment into the "no runner"
# state and restores it afterwards.
WithoutRunner = Callable[[str], Awaitable[None]]


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
async def test_doctor_can_choose_which_test_to_assign(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "line_tracing", "duration_seconds": 45},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CREATED, response.text
    assert response.json()["assessment_slug"] == "line_tracing"
    assert response.json()["assessment_title"] == "Line Tracing"


@pytest.mark.asyncio
async def test_assignment_stores_the_settings_the_doctor_chose(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={
            "assessment_slug": "line_tracing",
            "duration_seconds": 45,
            "parameters": {"pacing": "slow", "repetitions": 4, "line_length_percent": 90},
        },
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CREATED, response.text
    assert response.json()["parameters"] == {
        "pacing": "slow",
        "repetitions": 4,
        "line_length_percent": 90,
    }
    item = await db.scalar(
        select(MonitoringPlanItem).where(MonitoringPlanItem.plan_id == response.json()["id"])
    )
    assert item is not None
    assert item.parameters == {"pacing": "slow", "repetitions": 4, "line_length_percent": 90}


@pytest.mark.asyncio
async def test_omitted_settings_keep_their_catalog_defaults(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={
            "assessment_slug": "line_tracing",
            "parameters": {"repetitions": 6},
        },
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CREATED, response.text
    assert response.json()["parameters"] == {
        "pacing": "comfortable",
        "repetitions": 6,
        "line_length_percent": 70,
    }


@pytest.mark.parametrize(
    ("slug", "parameters"),
    [
        ("spiral_drawing", {"turns": 9}),
        ("spiral_drawing", {"turns": 0}),
        ("line_tracing", {"repetitions": 11}),
        ("handwriting", {"phrase": "x" * 61}),
        ("handwriting", {"phrase": "   "}),
        ("finger_tapping", {"hand": "both"}),
        ("finger_tapping", {"elbow": "left"}),
        ("spiral_drawing", {"repetitions": 2}),
    ],
)
@pytest.mark.asyncio
async def test_assignment_rejects_settings_that_break_their_bounds(
    client: AsyncClient,
    db: AsyncSession,
    slug: str,
    parameters: dict[str, object],
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": slug, "parameters": parameters},
        headers=auth_headers(token),
    )

    # Rejected rather than quietly corrected: the test the patient is given has
    # to be the test the doctor thinks they assigned.
    assert response.status_code == codes.UNPROCESSABLE_ENTITY, response.text


@pytest.mark.asyncio
async def test_doctor_can_read_the_tests_and_their_settings(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.get("/doctor/assessments", headers=auth_headers(token))

    assert response.status_code == codes.OK, response.text
    by_slug = {item["slug"]: item for item in response.json()}
    assert set(by_slug) == {
        "finger_tapping",
        "spiral_drawing",
        "line_tracing",
        "handwriting",
    }
    turns = next(p for p in by_slug["spiral_drawing"]["parameters"] if p["key"] == "turns")
    assert (turns["minimum"], turns["maximum"], turns["default"]) == (1, 6, 2)


@pytest.mark.asyncio
async def test_reading_the_tests_requires_authentication(client: AsyncClient) -> None:
    assert (await client.get("/doctor/assessments")).status_code == codes.UNAUTHORIZED


# ------------------------------------------------------------------ editing


@pytest.mark.asyncio
async def test_doctor_changes_the_settings_of_an_assigned_test(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={
            "assessment_slug": "line_tracing",
            "duration_seconds": 30,
            "parameters": {"pacing": "slow", "repetitions": 3},
        },
        headers=headers,
    )
    plan_id = created.json()["id"]

    response = await client.patch(
        f"/doctor/patients/{patient_id}/assignments/{plan_id}",
        json={"parameters": {"pacing": "fast", "repetitions": 7, "line_length_percent": 50}},
        headers=headers,
    )

    assert response.status_code == codes.OK, response.text
    body = response.json()
    assert body["parameters"]["repetitions"] == 7
    assert body["parameters"]["pacing"] == "fast"
    # Only the settings were sent, so the title and length are untouched.
    assert body["duration_seconds"] == 30
    assert body["title"] == "Line Tracing"


@pytest.mark.asyncio
async def test_editing_the_length_leaves_the_settings_alone(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "line_tracing", "parameters": {"repetitions": 2}},
        headers=headers,
    )
    plan_id = created.json()["id"]

    response = await client.patch(
        f"/doctor/patients/{patient_id}/assignments/{plan_id}",
        json={"duration_seconds": 90, "title": "Morning tracing"},
        headers=headers,
    )

    assert response.status_code == codes.OK, response.text
    body = response.json()
    assert body["duration_seconds"] == 90
    assert body["title"] == "Morning tracing"
    assert body["parameters"] == {
        "pacing": "comfortable",
        "repetitions": 2,
        "line_length_percent": 70,
    }


@pytest.mark.asyncio
async def test_the_patient_sees_the_edited_test(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "line_tracing", "duration_seconds": 30},
        headers=headers,
    )

    edited = await client.patch(
        f"/doctor/patients/{patient_id}/assignments/{created.json()['id']}",
        json={
            "duration_seconds": 60,
            "parameters": {
                "repetitions": 5,
                "pacing": "slow",
                "line_length_percent": 100,
            },
        },
        headers=headers,
    )
    assert edited.status_code == codes.OK, edited.text

    plan = await client.get("/monitoring/plan", headers=auth_headers(patient_token))

    assert plan.status_code == codes.OK
    item = plan.json()["items"][0]
    assert item["duration_seconds"] == 60
    assert item["parameters"] == {
        "pacing": "slow",
        "repetitions": 5,
        "line_length_percent": 100,
    }


@pytest.mark.asyncio
async def test_editing_rejects_settings_that_break_their_bounds(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "line_tracing"},
        headers=headers,
    )
    plan_id = created.json()["id"]

    response = await client.patch(
        f"/doctor/patients/{patient_id}/assignments/{plan_id}",
        json={"parameters": {"turns": 20}},
        headers=headers,
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY
    item = await db.scalar(select(MonitoringPlanItem).where(MonitoringPlanItem.plan_id == plan_id))
    assert item is not None
    # A rejected edit leaves the assignment exactly as it was.
    assert item.parameters is None


@pytest.mark.asyncio
async def test_cannot_edit_another_doctors_exercise(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 30},
        headers=auth_headers(token),
    )
    await create_doctor(
        db,
        name="Dr. Other",
        email="other.doctor@example.com",
        password=DOCTOR_PASSWORD,
    )
    intruder = await login_doctor(client, email="other.doctor@example.com")

    response = await client.patch(
        f"/doctor/patients/{patient_id}/assignments/{created.json()['id']}",
        json={"duration_seconds": 120},
        headers=auth_headers(intruder),
    )

    assert response.status_code == codes.NOT_FOUND


# ----------------------------------------------------------------- removing


@pytest.mark.asyncio
async def test_doctor_removes_a_test_from_a_patient(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "line_tracing", "duration_seconds": 30},
        headers=headers,
    )
    plan_id = created.json()["id"]

    removed = await client.delete(
        f"/doctor/patients/{patient_id}/assignments/{plan_id}",
        headers=headers,
    )

    assert removed.status_code == codes.NO_CONTENT
    # The patient no longer has an active plan to perform.
    assert (
        await client.get("/monitoring/plan", headers=auth_headers(patient_token))
    ).status_code == (codes.NOT_FOUND)
    # The doctor can still see what they removed.
    listing = await client.get(
        f"/doctor/patients/{patient_id}/assignments",
        headers=headers,
    )
    assert listing.json()[0]["status"] == "archived"


@pytest.mark.asyncio
async def test_removing_a_test_keeps_what_the_patient_recorded(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # A recording is a clinical record. Removing a task must not take the
    # patient's history with it.
    patient_id, patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "finger_tapping", "duration_seconds": 30},
        headers=headers,
    )
    plan_id = created.json()["id"]
    plan = await client.get("/monitoring/plan", headers=auth_headers(patient_token))
    plan_item_id = plan.json()["items"][0]["id"]
    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(patient_token),
        json={"plan_item_id": plan_item_id},
    )
    completed = await client.post(
        f"/monitoring/sessions/{started.json()['id']}/complete",
        headers=auth_headers(patient_token),
        json={"events": [{"event_type": "tap", "offset_ms": i * 300} for i in range(100)]},
    )
    assert completed.status_code == codes.OK
    session_id = completed.json()["id"]

    await client.delete(f"/doctor/patients/{patient_id}/assignments/{plan_id}", headers=headers)

    history = await client.get("/monitoring/sessions", headers=auth_headers(patient_token))
    detail = await client.get(
        f"/monitoring/sessions/{session_id}",
        headers=auth_headers(patient_token),
    )
    assert history.status_code == codes.OK
    assert [row["id"] for row in history.json()] == [session_id]
    assert detail.status_code == codes.OK
    assert detail.json()["result"]["taps"]["total_taps"] == 100


@pytest.mark.asyncio
async def test_a_removed_test_can_no_longer_be_edited(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # The patient will never be asked to do this exercise again, so an edit
    # that reported success would be a change the patient never sees.
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={
            "assessment_slug": "line_tracing",
            "duration_seconds": 30,
            "parameters": {"repetitions": 2, "line_length_percent": 60, "pacing": "comfortable"},
        },
        headers=headers,
    )
    plan_id = created.json()["id"]
    url = f"/doctor/patients/{patient_id}/assignments/{plan_id}"
    assert (await client.delete(url, headers=headers)).status_code == codes.NO_CONTENT

    edited = await client.patch(
        url,
        json={"duration_seconds": 90, "parameters": {"repetitions": 4}},
        headers=headers,
    )

    assert edited.status_code == codes.NOT_FOUND
    # The rejected edit left the archived row exactly as it was.
    listing = await client.get(
        f"/doctor/patients/{patient_id}/assignments",
        headers=headers,
    )
    row = next(item for item in listing.json() if item["id"] == plan_id)
    assert row["status"] == "archived"
    assert row["duration_seconds"] == 30
    assert row["parameters"] == {
        "repetitions": 2,
        "line_length_percent": 60,
        "pacing": "comfortable",
    }


@pytest.mark.asyncio
async def test_removing_a_test_twice_is_not_an_error(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 30},
        headers=headers,
    )
    url = f"/doctor/patients/{patient_id}/assignments/{created.json()['id']}"

    first = await client.delete(url, headers=headers)
    second = await client.delete(url, headers=headers)

    assert first.status_code == codes.NO_CONTENT
    assert second.status_code == codes.NO_CONTENT


@pytest.mark.asyncio
async def test_a_previous_assignment_returns_when_the_newest_is_removed(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    first = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "finger_tapping", "duration_seconds": 30},
        headers=headers,
    )
    second = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "line_tracing", "duration_seconds": 60},
        headers=headers,
    )

    await client.delete(
        f"/doctor/patients/{patient_id}/assignments/{second.json()['id']}",
        headers=headers,
    )

    plan = await client.get("/monitoring/plan", headers=auth_headers(patient_token))
    assert plan.status_code == codes.OK
    assert plan.json()["items"][0]["assessment"]["slug"] == "finger_tapping"
    assert plan.json()["items"][0]["duration_seconds"] == 30
    assert first.status_code == codes.CREATED


@pytest.mark.asyncio
async def test_cannot_remove_another_doctors_exercise(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    created = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"duration_seconds": 30},
        headers=auth_headers(token),
    )
    await create_doctor(
        db,
        name="Dr. Other",
        email="other.doctor@example.com",
        password=DOCTOR_PASSWORD,
    )
    intruder = await login_doctor(client, email="other.doctor@example.com")

    response = await client.delete(
        f"/doctor/patients/{patient_id}/assignments/{created.json()['id']}",
        headers=auth_headers(intruder),
    )

    assert response.status_code == codes.NOT_FOUND
    plan = await db.get(MonitoringPlan, created.json()["id"])
    assert plan is not None
    assert plan.status == "active"


@pytest.mark.asyncio
async def test_cannot_remove_an_exercise_for_a_patient_outside_the_roster(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await create_doctor(db, email=DOCTOR_EMAIL, password=DOCTOR_PASSWORD)
    token = await login_doctor(client)
    stranger_id, _stranger_token = await signup_patient(client)

    response = await client.delete(
        f"/doctor/patients/{stranger_id}/assignments/1",
        headers=auth_headers(token),
    )

    assert response.status_code == codes.NOT_FOUND


@pytest.mark.asyncio
async def test_removing_an_unknown_exercise_returns_404(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.delete(
        f"/doctor/patients/{patient_id}/assignments/999999",
        headers=auth_headers(token),
    )

    assert response.status_code == codes.NOT_FOUND


@pytest.mark.asyncio
async def test_editing_and_removing_require_authentication(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)

    edit = await client.patch(
        f"/doctor/patients/{patient_id}/assignments/1",
        json={"duration_seconds": 60},
    )
    remove = await client.delete(f"/doctor/patients/{patient_id}/assignments/1")

    assert edit.status_code == codes.UNAUTHORIZED
    assert remove.status_code == codes.UNAUTHORIZED


@pytest.mark.asyncio
async def test_assignment_rejects_unknown_assessments(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "foot_tapping", "duration_seconds": 30},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CONFLICT


@pytest.mark.asyncio
async def test_assignment_rejects_assessments_without_a_runner(
    client: AsyncClient,
    db: AsyncSession,
    without_runner: WithoutRunner,
) -> None:
    # The guard is exercised on a test that is normally assignable, so this
    # stays a test of the guard rather than of the held-back catalog entries.
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    await without_runner("line_tracing")

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": "line_tracing", "duration_seconds": 30},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CONFLICT


# -------------------------------------------------------------- held back


@pytest.mark.parametrize("slug", ["spiral_drawing", "handwriting"])
@pytest.mark.asyncio
async def test_a_held_back_test_cannot_be_assigned(
    client: AsyncClient,
    db: AsyncSession,
    slug: str,
) -> None:
    # Visible in the catalog so the doctor app can show it as coming soon, but
    # a doctor cannot hand it to a patient.
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.post(
        f"/doctor/patients/{patient_id}/assignments",
        json={"assessment_slug": slug, "duration_seconds": 30},
        headers=auth_headers(token),
    )

    assert response.status_code == codes.CONFLICT, response.text


@pytest.mark.asyncio
async def test_the_doctor_still_sees_the_held_back_tests(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # Held back is not hidden. A doctor has to be able to see what is coming,
    # and the flag is what tells the app to render it as unavailable.
    patient_id, _patient_token, _doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)

    response = await client.get("/doctor/assessments", headers=auth_headers(token))

    assert response.status_code == codes.OK, response.text
    by_slug = {item["slug"]: item for item in response.json()}
    assert by_slug["finger_tapping"]["is_supported"] is True
    assert by_slug["line_tracing"]["is_supported"] is True
    assert by_slug["spiral_drawing"]["is_supported"] is False
    assert by_slug["handwriting"]["is_supported"] is False
    # They keep describing themselves, so the app can still show what they are.
    for slug in ("spiral_drawing", "handwriting"):
        assert by_slug[slug]["title"]
        assert by_slug[slug]["parameters"]


@pytest.mark.parametrize("slug", ["spiral_drawing", "handwriting"])
@pytest.mark.asyncio
async def test_a_held_back_test_can_no_longer_be_edited(
    client: AsyncClient,
    db: AsyncSession,
    slug: str,
) -> None:
    # A doctor who assigned this test before it was held back still sees it in
    # their list, but the patient will never be asked to do it, so an edit that
    # reported success would be a change nobody ever sees. The way out is to
    # remove it, which the other test below covers.
    patient_id, _patient_token, doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    await create_historical_plan_item(
        db,
        patient_id,
        assessment_slug=slug,
        doctor_id=doctor_id,
        duration_seconds=30,
        parameters={"turns": 2, "size_percent": 60},
    )
    listing = await client.get(
        f"/doctor/patients/{patient_id}/assignments",
        headers=headers,
    )
    assert listing.status_code == codes.OK, listing.text
    row = next(item for item in listing.json() if item["assessment_slug"] == slug)
    url = f"/doctor/patients/{patient_id}/assignments/{row['id']}"

    edited = await client.patch(
        url,
        json={"duration_seconds": 90},
        headers=headers,
    )

    assert edited.status_code == codes.CONFLICT, edited.text
    # The refused edit left the stored settings exactly as they were.
    after = await client.get(
        f"/doctor/patients/{patient_id}/assignments",
        headers=headers,
    )
    unchanged = next(item for item in after.json() if item["id"] == row["id"])
    assert unchanged["duration_seconds"] == 30
    assert unchanged["title"] == row["title"]


@pytest.mark.parametrize("slug", ["spiral_drawing", "handwriting"])
@pytest.mark.asyncio
async def test_a_held_back_test_can_still_be_removed(
    client: AsyncClient,
    db: AsyncSession,
    slug: str,
) -> None:
    # Refusing the edit must not strand the doctor with an exercise they cannot
    # get rid of: removing it is how a held-back assignment goes away.
    patient_id, _patient_token, doctor_id = await create_linked_patient(client, db)
    token = await login_doctor(client)
    headers = auth_headers(token)
    await create_historical_plan_item(
        db,
        patient_id,
        assessment_slug=slug,
        doctor_id=doctor_id,
    )
    listing = await client.get(
        f"/doctor/patients/{patient_id}/assignments",
        headers=headers,
    )
    row = next(item for item in listing.json() if item["assessment_slug"] == slug)

    removed = await client.delete(
        f"/doctor/patients/{patient_id}/assignments/{row['id']}",
        headers=headers,
    )

    assert removed.status_code == codes.NO_CONTENT, removed.text
    after = await client.get(
        f"/doctor/patients/{patient_id}/assignments",
        headers=headers,
    )
    assert next(item for item in after.json() if item["id"] == row["id"])["status"] == "archived"
