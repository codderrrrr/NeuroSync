"""API integration tests for the monitoring vertical."""

from collections.abc import Awaitable, Callable
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient, codes
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.monitoring import service as monitoring_service
from neurosync.modules.monitoring.models import (
    AssessmentDefinition,
    MonitoringPlanItem,
    MonitoringResult,
    MonitoringSession,
    MonitoringSessionEvent,
)
from tests.factories import (
    auth_headers,
    create_default_plan,
    seed_assessment_catalog,
    signup_patient,
)

# The `without_runner` fixture: puts a catalog assessment into the "no runner"
# state and restores it afterwards.
WithoutRunner = Callable[[str], Awaitable[None]]


def _steady_taps(count: int = 90, interval_ms: int = 333) -> list[dict[str, object]]:
    """A steady recording: taps every ``interval_ms`` for ``count`` taps."""
    return [{"event_type": "tap", "offset_ms": i * interval_ms} for i in range(count)]


async def _start_session(
    client: AsyncClient,
    token: str,
    plan_item_id: int,
) -> dict[str, object]:
    response = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    assert response.status_code == codes.CREATED, response.text
    return response.json()


async def _start_session(
    client: AsyncClient,
    token: str,
    plan_item_id: int,
) -> dict[str, object]:
    response = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )
    assert response.status_code == codes.CREATED, response.text
    return response.json()


# ---------------------------------------------------------------- catalog


async def test_catalog_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/assessments")
    assert response.status_code == codes.UNAUTHORIZED


async def test_catalog_lists_all_assessments_with_support_flags(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await seed_assessment_catalog(db)
    _, token = await signup_patient(client)

    response = await client.get("/assessments", headers=auth_headers(token))

    assert response.status_code == codes.OK
    items = response.json()
    by_slug = {item["slug"]: item for item in items}
    assert set(by_slug) == {
        "finger_tapping",
        "spiral_drawing",
        "line_tracing",
        "handwriting",
    }
    assert by_slug["finger_tapping"]["execution_type"] == "tap_task"
    assert by_slug["finger_tapping"]["default_duration_seconds"] == 30
    # Finger tapping and line tracing are the two a doctor may assign. Spiral
    # drawing and handwriting are held back, so they report themselves as
    # unsupported while staying listed with everything else.
    for slug in ("finger_tapping", "line_tracing"):
        assert by_slug[slug]["is_supported"] is True, slug
    for slug in ("spiral_drawing", "handwriting"):
        assert by_slug[slug]["is_supported"] is False, slug
    for slug, item in by_slug.items():
        # Every entry keeps describing itself, supported or not, so a client can
        # render a held-back one without special-casing it.
        assert item["title"], slug
        assert item["instructions"], slug
        assert item["parameters"], slug
    for canvas_slug in ("spiral_drawing", "line_tracing", "handwriting"):
        assert by_slug[canvas_slug]["execution_type"] == "canvas_task"


async def test_catalog_describes_what_a_doctor_can_change_about_each_test(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await seed_assessment_catalog(db)
    _, token = await signup_patient(client)

    response = await client.get("/assessments", headers=auth_headers(token))

    assert response.status_code == codes.OK
    by_slug = {item["slug"]: item for item in response.json()}
    hand = next(p for p in by_slug["finger_tapping"]["parameters"] if p["key"] == "hand")
    assert hand["kind"] == "choice"
    assert hand["choices"] == ["left", "right"]
    assert hand["default"] == "right"
    phrase = next(p for p in by_slug["handwriting"]["parameters"] if p["key"] == "phrase")
    assert phrase["kind"] == "text"
    assert phrase["max_length"] == 60
    turns = next(p for p in by_slug["spiral_drawing"]["parameters"] if p["key"] == "turns")
    assert (turns["minimum"], turns["maximum"]) == (1, 6)


async def test_catalog_is_seeded_by_migration(client: AsyncClient) -> None:
    # No explicit seeding: the migration already inserted the catalog.
    _, token = await signup_patient(client)

    response = await client.get("/assessments", headers=auth_headers(token))

    assert response.status_code == codes.OK
    assert {item["slug"] for item in response.json()} >= {"finger_tapping"}


# ---------------------------------------------------------------- plan


async def test_plan_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/monitoring/plan")
    assert response.status_code == codes.UNAUTHORIZED


async def test_plan_returns_not_found_without_a_plan(client: AsyncClient) -> None:
    _, token = await signup_patient(client)

    response = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert response.status_code == codes.NOT_FOUND


async def test_patient_receives_the_seeded_plan_through_the_api(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    await create_default_plan(db, patient_id)

    response = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert response.status_code == codes.OK
    body = response.json()
    assert body["title"] == "Daily motor check-in"
    assert body["status"] == "active"
    assert len(body["items"]) == 1
    item = body["items"][0]
    assert item["assessment"]["slug"] == "finger_tapping"
    assert item["assessment"]["is_supported"] is True
    assert item["position"] == 0
    assert item["completed_today"] == 0


async def test_plan_hides_other_patients_plans(client: AsyncClient, db: AsyncSession) -> None:
    other_patient_id, _ = await signup_patient(client, email="other@example.com")
    await create_default_plan(db, other_patient_id)
    _, token = await signup_patient(client, email="me@example.com")

    response = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert response.status_code == codes.NOT_FOUND


# ---------------------------------------------------- unsupported protection


async def test_plan_creation_rejects_unsupported_assessments(
    client: AsyncClient,
    db: AsyncSession,
    without_runner: WithoutRunner,
) -> None:
    await signup_patient(client)
    await without_runner("spiral_drawing")
    spiral = await db.scalar(
        select(AssessmentDefinition).where(AssessmentDefinition.slug == "spiral_drawing")
    )
    assert spiral is not None

    with pytest.raises(monitoring_service.UnsupportedAssessmentError):
        await monitoring_service.create_plan(
            session=db,
            patient_id=1,
            title="Should never exist",
            assessment_definition_ids=[spiral.id],
        )


async def test_starting_session_for_unsupported_assessment_is_rejected(
    client: AsyncClient,
    db: AsyncSession,
    without_runner: WithoutRunner,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    await without_runner("spiral_drawing")
    spiral = await db.scalar(
        select(AssessmentDefinition).where(AssessmentDefinition.slug == "spiral_drawing")
    )
    assert spiral is not None

    # Simulate a legacy row pointing at an unsupported assessment: the API must
    # still refuse to open a session the client cannot run.
    await db.execute(
        MonitoringPlanItem.__table__.update()
        .where(MonitoringPlanItem.id == plan_item_id)
        .values(assessment_definition_id=spiral.id)
    )
    await db.commit()

    response = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )

    assert response.status_code == codes.CONFLICT
    assert "not available" in response.json()["detail"].lower()


# ---------------------------------------------------------------- sessions


async def test_start_session_requires_authentication(client: AsyncClient) -> None:
    response = await client.post("/monitoring/sessions", json={"plan_item_id": 1})
    assert response.status_code == codes.UNAUTHORIZED


async def test_start_session_returns_in_progress_with_assessment(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    body = await _start_session(client, token, plan_item_id)

    assert body["status"] == "in_progress"
    assert body["assessment"]["slug"] == "finger_tapping"
    assert body["result"] is None
    assert body["completed_at"] is None


async def test_start_session_for_unknown_item_returns_404(client: AsyncClient) -> None:
    _, token = await signup_patient(client)

    response = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": 999_999},
    )

    assert response.status_code == codes.NOT_FOUND


async def test_start_session_for_other_patients_item_returns_404(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    other_patient_id, _ = await signup_patient(client, email="owner@example.com")
    plan_item_id = await create_default_plan(db, other_patient_id)
    _, token = await signup_patient(client, email="intruder@example.com")

    response = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(token),
        json={"plan_item_id": plan_item_id},
    )

    assert response.status_code == codes.NOT_FOUND


async def test_complete_session_persists_events_and_result(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    session_body = await _start_session(client, token, plan_item_id)
    session_id = session_body["id"]

    response = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": _steady_taps(count=6, interval_ms=1000)},
    )

    assert response.status_code == codes.OK, response.text
    body = response.json()
    assert body["status"] == "completed"
    assert body["completed_at"] is not None
    result = body["result"]
    assert result["quality"] == "incomplete"
    # A finger-tapping recording fills the tap block and leaves the canvas one
    # empty, so a client never has to guess which features it is looking at.
    assert result["canvas"] is None
    assert result["taps"]["total_taps"] == 6
    assert result["taps"]["duration_ms"] == 5000
    assert result["taps"]["mean_inter_tap_interval_ms"] == 1000
    assert result["taps"]["longest_pause_ms"] == 1000

    row = await db.scalar(select(MonitoringResult).where(MonitoringResult.session_id == session_id))
    assert row is not None
    assert row.total_taps == 6
    event_count = await db.scalar(
        select(func.count())
        .select_from(MonitoringSessionEvent)
        .where(MonitoringSessionEvent.session_id == session_id)
    )
    assert event_count == 6


async def test_completing_twice_returns_409(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    session_id = (await _start_session(client, token, plan_item_id))["id"]

    first = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": _steady_taps(count=6)},
    )
    assert first.status_code == codes.OK
    second = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": _steady_taps(count=6)},
    )

    assert second.status_code == codes.CONFLICT


async def test_completing_with_non_tap_events_returns_422(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    session_id = (await _start_session(client, token, plan_item_id))["id"]

    response = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": [{"event_type": "swipe", "offset_ms": 10}]},
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


async def test_completing_unknown_session_returns_404(client: AsyncClient) -> None:
    _, token = await signup_patient(client)

    response = await client.post(
        "/monitoring/sessions/999999/complete",
        headers=auth_headers(token),
        json={"events": []},
    )

    assert response.status_code == codes.NOT_FOUND


async def test_completing_other_patients_session_returns_404(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    owner_patient_id, owner_token = await signup_patient(client, email="owner@example.com")
    plan_item_id = await create_default_plan(db, owner_patient_id)
    session_id = (await _start_session(client, owner_token, plan_item_id))["id"]
    _, intruder_token = await signup_patient(client, email="intruder@example.com")

    response = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(intruder_token),
        json={"events": []},
    )

    assert response.status_code == codes.NOT_FOUND


# ---------------------------------------------------------------- history


async def test_history_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/monitoring/sessions")
    assert response.status_code == codes.UNAUTHORIZED


async def test_history_lists_own_completed_sessions_newest_first(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    completed_ids: list[int] = []
    for _ in range(3):
        body = await _start_session(client, token, plan_item_id)
        response = await client.post(
            f"/monitoring/sessions/{body['id']}/complete",
            headers=auth_headers(token),
            json={"events": _steady_taps(count=6)},
        )
        assert response.status_code == codes.OK
        completed_ids.append(body["id"])

    response = await client.get("/monitoring/sessions", headers=auth_headers(token))

    assert response.status_code == codes.OK
    items = response.json()
    assert [item["id"] for item in items] == list(reversed(completed_ids))
    assert all(item["status"] == "completed" for item in items)
    assert all(item["result"] is not None for item in items)


async def test_history_excludes_in_progress_sessions(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    await _start_session(client, token, plan_item_id)  # left in progress

    response = await client.get("/monitoring/sessions", headers=auth_headers(token))

    assert response.status_code == codes.OK
    assert response.json() == []


async def test_history_is_scoped_to_the_patient(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    other_patient_id, other_token = await signup_patient(client, email="other@example.com")
    plan_item_id = await create_default_plan(db, other_patient_id)
    body = await _start_session(client, other_token, plan_item_id)
    await client.post(
        f"/monitoring/sessions/{body['id']}/complete",
        headers=auth_headers(other_token),
        json={"events": _steady_taps(count=6)},
    )

    _, token = await signup_patient(client, email="me@example.com")
    response = await client.get("/monitoring/sessions", headers=auth_headers(token))

    assert response.status_code == codes.OK
    assert response.json() == []


async def test_history_respects_limit(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(3):
        body = await _start_session(client, token, plan_item_id)
        await client.post(
            f"/monitoring/sessions/{body['id']}/complete",
            headers=auth_headers(token),
            json={"events": _steady_taps(count=6)},
        )

    response = await client.get(
        "/monitoring/sessions",
        headers=auth_headers(token),
        params={"limit": 2},
    )

    assert response.status_code == codes.OK
    assert len(response.json()) == 2


async def test_session_detail_returns_own_session_with_result(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    session_id = (await _start_session(client, token, plan_item_id))["id"]
    await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": _steady_taps(count=6)},
    )

    response = await client.get(f"/monitoring/sessions/{session_id}", headers=auth_headers(token))

    assert response.status_code == codes.OK
    body = response.json()
    assert body["id"] == session_id
    assert body["result"]["quality"] == "incomplete"


async def test_session_detail_hides_other_patients_sessions(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    other_patient_id, other_token = await signup_patient(client, email="other@example.com")
    plan_item_id = await create_default_plan(db, other_patient_id)
    session_id = (await _start_session(client, other_token, plan_item_id))["id"]
    _, token = await signup_patient(client, email="me@example.com")

    response = await client.get(f"/monitoring/sessions/{session_id}", headers=auth_headers(token))

    assert response.status_code == codes.NOT_FOUND


# ------------------------------------------------------------- plan details


async def test_plan_returns_the_newest_active_plan(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    await create_default_plan(db, patient_id)

    response = await client.get("/monitoring/plan", headers=auth_headers(token))

    assert response.status_code == codes.OK
    body = response.json()
    assert body["status"] == "active"
    assert body["items"], "the seeded plan must contain at least one item"
    positions = [item["position"] for item in body["items"]]
    assert positions == sorted(positions)


async def test_completed_today_counts_sessions_finished_today(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    response = await client.get("/monitoring/plan", headers=auth_headers(token))
    assert response.json()["items"][0]["completed_today"] == 0

    for _ in range(2):
        body = await _start_session(client, token, plan_item_id)
        completed = await client.post(
            f"/monitoring/sessions/{body['id']}/complete",
            headers=auth_headers(token),
            json={"events": _steady_taps(count=6)},
        )
        assert completed.status_code == codes.OK

    response = await client.get("/monitoring/plan", headers=auth_headers(token))
    assert response.json()["items"][0]["completed_today"] == 2


# --------------------------------------------- assigned recording duration


async def test_quality_judges_a_recording_against_the_assigned_duration(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # Regression: quality was evaluated against the catalog default (30s), so a
    # patient who correctly recorded for a doctor-assigned 120s exceeded
    # 2.0 x 30s and every such session was stored as `invalid`.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id, duration_seconds=120)
    session_id = (await _start_session(client, token, plan_item_id))["id"]

    response = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        # 120 taps a second apart: a full 119 seconds of steady tapping.
        json={"events": _steady_taps(count=120, interval_ms=1000)},
    )

    assert response.status_code == codes.OK, response.text
    result = response.json()["result"]
    assert result["taps"]["duration_ms"] == 119_000
    assert result["taps"]["total_taps"] == 120
    assert result["quality"] == "valid"


async def test_quality_falls_back_to_the_catalog_default_without_an_assignment(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # The other half of the rule: with no duration_seconds on the item the
    # catalog default (30s) is still the target.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    session_id = (await _start_session(client, token, plan_item_id))["id"]

    response = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": _steady_taps(count=30, interval_ms=1000)},
    )

    assert response.status_code == codes.OK, response.text
    result = response.json()["result"]
    assert result["taps"]["duration_ms"] == 29_000
    assert result["quality"] == "valid"


async def test_an_assigned_duration_still_rejects_an_over_long_recording(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # The assigned target must be a real target: a recording that overruns it
    # is still `invalid`, so the fix did not simply disable the duration check.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id, duration_seconds=60)
    session_id = (await _start_session(client, token, plan_item_id))["id"]

    response = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        # 150 seconds against a 60-second assignment: over 2.0 x target.
        json={"events": _steady_taps(count=150, interval_ms=1000)},
    )

    assert response.status_code == codes.OK, response.text
    assert response.json()["result"]["quality"] == "invalid"


async def test_plan_and_completion_agree_on_the_target_duration(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # The plan the patient is shown and the evaluation of the recording that
    # came back must resolve the target the same way, so both resolve through
    # `resolve_item_duration_seconds`.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id, duration_seconds=120)

    plan = await client.get("/monitoring/plan", headers=auth_headers(token))
    assert plan.status_code == codes.OK
    assert plan.json()["items"][0]["duration_seconds"] == 120

    session_id = (await _start_session(client, token, plan_item_id))["id"]
    completed = await client.post(
        f"/monitoring/sessions/{session_id}/complete",
        headers=auth_headers(token),
        json={"events": _steady_taps(count=120, interval_ms=1000)},
    )
    assert completed.status_code == codes.OK
    assert completed.json()["result"]["quality"] == "valid"


async def test_started_at_is_stored_timezone_aware(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    body = await _start_session(client, token, plan_item_id)

    row = await db.scalar(select(MonitoringSession).where(MonitoringSession.id == body["id"]))
    assert row is not None
    assert row.started_at.tzinfo is not None
    assert abs(datetime.now(UTC) - row.started_at).total_seconds() < 60
