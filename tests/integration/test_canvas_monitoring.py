"""Canvas (tracing) assessment execution through the patient API.

Covers a canvas assessment end to end: assigning one, running it, storing the
raw stream, deriving its features, and reporting them honestly without
pretending to a longitudinal comparison that does not exist.

Spiral drawing and handwriting are held back, so the runnable canvas test today
is line tracing. Their exclusion from a patient's plan is covered here too.
"""

import httpx
import pytest
from httpx import AsyncClient, codes
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.monitoring.models import (
    LongitudinalResult,
    MonitoringResult,
    MonitoringSessionEvent,
)
from tests.factories import (
    auth_headers,
    create_historical_plan_item,
    create_medication_event,
    create_medication_record,
    create_plan_item,
    signup_patient,
    straight_line_strokes,
)

# The canvas tests a doctor may hand out today.
RUNNABLE_CANVAS_SLUGS = ["line_tracing"]

# Described in the catalog so the doctor app can show them as coming soon, but
# never assignable and never shown to a patient.
HELD_BACK_SLUGS = ["spiral_drawing", "handwriting"]


async def _complete(
    client: AsyncClient,
    token: str,
    plan_item_id: int,
    events: list[dict[str, object]],
    **body: object,
) -> dict[str, object]:
    """Start and complete one session, returning the completed body."""
    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    assert started.status_code == codes.CREATED, started.text
    response = await client.post(
        f"/monitoring/sessions/{started.json()['id']}/complete",
        headers=auth_headers(token),
        json={"events": events, **body},
    )
    assert response.status_code == codes.OK, response.text
    return response.json()


async def _complete_expecting_rejection(
    client: AsyncClient,
    token: str,
    plan_item_id: int,
    events: list[dict[str, object]],
    **body: object,
) -> httpx.Response:
    """Start a session and complete it, returning the raw rejection response."""
    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    assert started.status_code == codes.CREATED, started.text
    return await client.post(
        f"/monitoring/sessions/{started.json()['id']}/complete",
        headers=auth_headers(token),
        json={"events": events, **body},
    )


@pytest.mark.parametrize("slug", RUNNABLE_CANVAS_SLUGS)
async def test_every_canvas_assessment_can_be_assigned_and_run(
    client: AsyncClient,
    db: AsyncSession,
    slug: str,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(db, patient_id, assessment_slug=slug)

    plan = await client.get("/monitoring/plan", headers=auth_headers(token))
    body = await _complete(client, token, plan_item_id, straight_line_strokes(count=3))

    assert plan.status_code == codes.OK
    assert plan.json()["items"][0]["assessment"]["execution_type"] == "canvas_task"
    assert body["status"] == "completed"
    assert body["result"]["canvas"] is not None
    assert body["result"]["taps"] is None


async def test_a_canvas_recording_derives_its_features_deterministically(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(
        db,
        patient_id,
        assessment_slug="line_tracing",
        duration_seconds=30,
        parameters={"repetitions": 3},
    )

    body = await _complete(
        client,
        token,
        plan_item_id,
        straight_line_strokes(count=3, points_per_second=40, duration_ms=30_000),
    )

    # The fixture spreads three passes evenly over the 30-second assignment at
    # 40 samples a second: 400 samples per pass, 10 px between each.
    canvas = body["result"]["canvas"]
    assert canvas["stroke_count"] == 3
    assert canvas["total_points"] == 3 * 401
    assert canvas["duration_ms"] == 29_975
    assert canvas["path_length"] == 3 * 399 * 10
    assert canvas["mean_speed_px_per_second"] == 400.0
    assert canvas["longest_pause_ms"] == 25
    # Every pass went straight from one end to the other.
    assert canvas["path_efficiency"] == 1.0
    assert body["result"]["quality"] == "valid"


async def test_a_canvas_recording_is_stored_exactly_as_captured(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(db, patient_id, assessment_slug="line_tracing")
    events = straight_line_strokes(count=1)
    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    session_id = started.json()["id"]

    completed = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": events},
    )

    assert completed.status_code == codes.OK
    stored = list(
        await db.scalars(
            select(MonitoringSessionEvent)
            .where(MonitoringSessionEvent.session_id == session_id)
            .order_by(MonitoringSessionEvent.offset_ms)
        )
    )
    assert len(stored) == len(events)
    first = stored[0]
    assert first.event_type == "stroke_start"
    assert first.payload == {"x": 0.0, "y": 0.0}


async def test_a_canvas_recording_misses_no_repetitions(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # "Draw the line three times" is not satisfied by one pass, however long it
    # runs. The recording is kept and described as incomplete rather than
    # dropped or silently accepted.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(
        db,
        patient_id,
        assessment_slug="line_tracing",
        duration_seconds=30,
        parameters={"repetitions": 3},
    )

    body = await _complete(
        client,
        token,
        plan_item_id,
        straight_line_strokes(count=1, duration_ms=30_000),
    )

    assert body["result"]["quality"] == "incomplete"
    assert body["result"]["canvas"]["stroke_count"] == 1


async def test_a_canvas_recording_reports_no_longitudinal_comparison(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # There is no baseline for a tracing test yet, so the session reports none.
    # It must not borrow the finger-tapping comparison, which would mean
    # something the data cannot support.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(db, patient_id, assessment_slug="line_tracing")

    body = await _complete(client, token, plan_item_id, straight_line_strokes(count=2))

    assert body["longitudinal"] is None
    stored = await db.scalar(
        select(func.count())
        .select_from(LongitudinalResult)
        .where(LongitudinalResult.session_id == body["id"])
    )
    assert stored == 0


async def test_a_canvas_recording_rejects_a_reported_dose(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # The dose timing has nothing to support here. Accepting and dropping it
    # would read as the patient declining to give their medication.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(db, patient_id, assessment_slug="line_tracing")
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
    )

    response = await _complete_expecting_rejection(
        client,
        token,
        plan_item_id,
        straight_line_strokes(count=1),
        medication_event_id=event["id"],
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY
    assert "medication context" in response.json()["detail"].lower()


async def test_a_tap_stream_is_rejected_for_a_canvas_test(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # Which runner interprets a stream is decided by the catalog, never by what
    # the client sent.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(db, patient_id, assessment_slug="line_tracing")

    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    response = await client.post(
        f"/monitoring/sessions/{started.json()['id']}/complete",
        headers=auth_headers(token),
        json={"events": [{"event_type": "tap", "offset_ms": 10}]},
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


async def test_a_canvas_point_without_coordinates_is_rejected(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(db, patient_id, assessment_slug="line_tracing")

    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    response = await client.post(
        f"/monitoring/sessions/{started.json()['id']}/complete",
        headers=auth_headers(token),
        json={
            "events": [
                {"event_type": "stroke_start", "offset_ms": 0, "payload": {"x": 1.0}},
            ]
        },
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


async def test_a_tap_recording_keeps_its_tap_features(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # The tap and canvas shapes are exclusive in one table; a tap session must
    # still write exactly the tap columns.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_plan_item(db, patient_id, assessment_slug="finger_tapping")

    body = await _complete(
        client,
        token,
        plan_item_id,
        [{"event_type": "tap", "offset_ms": i * 1000} for i in range(40)],
    )
    assert body["result"]["quality"] == "valid"

    row = await db.scalar(select(MonitoringResult).where(MonitoringResult.session_id == body["id"]))
    assert row is not None
    assert row.total_taps == 40
    assert row.total_points is None
    assert row.stroke_count is None
    assert body["result"]["taps"]["total_taps"] == 40


async def test_the_patient_plan_shows_the_settings_the_doctor_chose(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    await create_plan_item(
        db,
        patient_id,
        assessment_slug="line_tracing",
        duration_seconds=45,
        parameters={"pacing": "slow", "repetitions": 4, "line_length_percent": 55},
    )

    response = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert response.status_code == codes.OK
    item = response.json()["items"][0]
    assert item["duration_seconds"] == 45
    assert item["parameters"] == {
        "pacing": "slow",
        "repetitions": 4,
        "line_length_percent": 55,
    }


async def test_a_plan_without_settings_reports_the_catalog_defaults(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # A row written before the settings existed still resolves a complete set,
    # so the client never has to know which ones a doctor actually chose.
    patient_id, token = await signup_patient(client)
    await create_plan_item(db, patient_id, assessment_slug="line_tracing")

    response = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert response.json()["items"][0]["parameters"] == {
        "pacing": "comfortable",
        "repetitions": 3,
        "line_length_percent": 70,
    }


@pytest.mark.parametrize("slug", HELD_BACK_SLUGS)
async def test_a_held_back_test_never_reaches_the_patient(
    client: AsyncClient,
    db: AsyncSession,
    slug: str,
) -> None:
    # A doctor assigned this before it was held back. The plan row and the raw
    # event table stay untouched, but the patient is not asked to do a test
    # NeuroSync has decided not to hand out.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_historical_plan_item(db, patient_id, assessment_slug=slug)

    plan = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert plan.status_code == codes.OK
    assert plan.json()["items"] == []

    # And it cannot be started by id either, so the exclusion is not just a
    # display filter over a session the patient could still open.
    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    assert started.status_code == codes.CONFLICT


async def test_a_held_back_test_does_not_hide_the_ones_that_are_ready(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # Excluding items must not exclude the whole plan: a patient with a mixed
    # plan still sees the tests they can actually do.
    patient_id, token = await signup_patient(client)
    await create_historical_plan_item(db, patient_id, assessment_slug="spiral_drawing")
    await create_plan_item(db, patient_id, assessment_slug="line_tracing")

    plan = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert plan.status_code == codes.OK
    assert [item["assessment"]["slug"] for item in plan.json()["items"]] == ["line_tracing"]
