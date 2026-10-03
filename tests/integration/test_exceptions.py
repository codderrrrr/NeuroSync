"""Integration tests for exception routing and the specialist review queue.

These drive the whole slice through the API: a patient records sessions, the
pipeline decides for itself what to route, and a doctor opens the queue and
records what they decided. Nothing is inserted behind the application's back,
so a test that passes here is a behaviour a real deployment has.
"""

from typing import Any

import pytest
from httpx import AsyncClient, codes
from sqlalchemy import event, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import Doctor
from neurosync.modules.exceptions import service as exception_service
from neurosync.modules.exceptions.models import ExceptionStatus, ReviewException
from neurosync.modules.monitoring import service as monitoring_service
from neurosync.modules.monitoring.models import LongitudinalResult, MonitoringSession
from tests.conftest import test_engine
from tests.factories import (
    DOCTOR_EMAIL,
    DOCTOR_PASSWORD,
    auth_headers,
    complete_a_session,
    create_default_plan,
    create_doctor,
    create_doctor_link,
    login_doctor,
    signup_patient,
    steady_taps,
)

# A steady 30-second recording at one tap per second.
USUAL_TAPS = steady_taps(count=30, interval_ms=1000)
# Clearly slower: a tap roughly every three seconds.
SLOW_TAPS = steady_taps(count=10, interval_ms=3000)
# Too short to compare against anything.
TOO_SHORT_TAPS = steady_taps(count=4, interval_ms=1000)

# Usual sessions needed before a comparison can reach routable evidence: three
# establish a baseline, and a fourth lifts it past the evidence floor.
USUAL_SESSIONS_BEFORE_CHANGE = 4

OTHER_DOCTOR_EMAIL = "other.doctor@example.com"


# ------------------------------------------------------------------- helpers


async def _patient_with_a_change(
    client: AsyncClient,
    db: AsyncSession,
    *,
    email: str,
    tail: list[list[dict[str, object]]] | None = None,
) -> tuple[int, str, int]:
    """A patient who recorded a baseline and then something notable.

    Returns their id, their token, and the id of the last session. Roster
    membership is left to the caller, because linking is what several of these
    tests are actually about and it belongs in the test, not hidden in a helper.
    """
    patient_id, token = await signup_patient(client, email=email)
    plan_item_id = await create_default_plan(db, patient_id)
    sessions = [USUAL_TAPS] * USUAL_SESSIONS_BEFORE_CHANGE
    sessions += tail if tail is not None else [SLOW_TAPS]
    last = None
    for events in sessions:
        last = await complete_a_session(
            client, token=token, plan_item_id=plan_item_id, events=events
        )
    return patient_id, token, int(last["id"])


async def _sign_in_doctor(
    db: AsyncSession,
    *,
    name: str = "Dr. Test",
    email: str = DOCTOR_EMAIL,
) -> Doctor:
    """A doctor with portal credentials, ready to be linked and to log in."""
    return await create_doctor(db, name=name, email=email, password=DOCTOR_PASSWORD)


async def _link(
    db: AsyncSession,
    *,
    doctor_id: int,
    patient_id: int,
    status: str = "active",
) -> None:
    """Put a patient on a doctor's roster, or have them request to be."""
    await create_doctor_link(db, doctor_id=doctor_id, patient_id=patient_id, status=status)


async def _queued_patient(
    client: AsyncClient,
    db: AsyncSession,
    *,
    email: str = "linked.patient@example.com",
    link_status: str = "active",
    tail: list[list[dict[str, object]]] | None = None,
) -> tuple[int, str, int]:
    """One doctor, one linked patient, and at least one routed exception.

    Returns the patient id, the patient's token, and the last session recorded.
    Every test whose real subject is not the roster boundary starts here.
    """
    doctor = await _sign_in_doctor(db)
    patient_id, token, session_id = await _patient_with_a_change(client, db, email=email, tail=tail)
    await _link(db, doctor_id=doctor.id, patient_id=patient_id, status=link_status)
    return patient_id, token, session_id


async def _stored_exceptions(db: AsyncSession) -> list[ReviewException]:
    return list(await db.scalars(select(ReviewException).order_by(ReviewException.id)))


async def _only_exception_id(client: AsyncClient, token: str) -> int:
    listing = await client.get("/doctor/exceptions", headers=auth_headers(token))
    assert listing.status_code == codes.OK, listing.text
    rows = listing.json()
    assert rows, "expected a routed exception in the queue"
    return int(rows[0]["id"])


# ------------------------------------------------------- the routing pipeline


async def test_a_steady_patient_never_reaches_the_queue(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Normal recordings are the overwhelming majority and must stay invisible."""
    doctor = await _sign_in_doctor(db)
    patient_id, token, _session_id = await _patient_with_a_change(
        client, db, email="steady@example.com", tail=[USUAL_TAPS] * 4
    )
    await _link(db, doctor_id=doctor.id, patient_id=patient_id)

    assert await _stored_exceptions(db) == []

    doctor_token = await login_doctor(client)
    response = await client.get("/doctor/exceptions", headers=auth_headers(doctor_token))
    assert response.status_code == codes.OK
    assert response.json() == []


async def test_a_single_change_is_routed_for_review(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """One well-evidenced change reaches the queue with its reason attached."""
    await _queued_patient(client, db)

    rows = await _stored_exceptions(db)

    assert len(rows) == 1
    exception = rows[0]
    assert exception.exception_type == "review_requested"
    assert exception.routing_rule == "supported_single_change"
    assert exception.status == "open"
    assert exception.supporting_observations == 1
    assert exception.reviewed_by_doctor_id is None
    assert exception.reviewed_at is None
    # The queue entry explains itself without any decision being re-run.
    assert "single change" in exception.rationale


async def test_a_third_consecutive_change_is_routed_as_persistent(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """The run is recognised only once it actually reaches the threshold."""
    await _queued_patient(client, db, email="persistent@example.com", tail=[SLOW_TAPS] * 3)

    rows = await _stored_exceptions(db)

    assert [row.exception_type for row in rows] == [
        "review_requested",
        "review_requested",
        "persistent_change",
    ]
    assert rows[-1].routing_rule == "repeated_change"
    assert rows[-1].supporting_observations == 3


async def test_a_change_interrupted_by_a_steady_recording_is_not_persistent(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Change, back to usual, change: two findings, not one growing run."""
    await _queued_patient(
        client, db, email="interrupted@example.com", tail=[SLOW_TAPS, USUAL_TAPS, SLOW_TAPS]
    )

    rows = await _stored_exceptions(db)

    assert [row.exception_type for row in rows] == ["review_requested", "review_requested"]
    assert all(row.supporting_observations == 1 for row in rows)


async def test_an_unusable_recording_is_never_routed(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """A recording too short to compare against is not a finding."""
    doctor = await _sign_in_doctor(db)
    patient_id, token, _session_id = await _patient_with_a_change(
        client, db, email="unusable@example.com", tail=[TOO_SHORT_TAPS] * 3
    )
    await _link(db, doctor_id=doctor.id, patient_id=patient_id)

    assert await _stored_exceptions(db) == []


async def test_a_routing_failure_never_costs_the_patient_their_recording(
    client: AsyncClient,
    db: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The comparison is the record; a queue row is an addition to it.

    A patient should not lose a completed assessment because the review queue
    could not be written, so routing runs in a savepoint that rolls back on its
    own and leaves the recording intact.
    """
    doctor = await _sign_in_doctor(db)
    patient_id, token, _session_id = await _patient_with_a_change(
        client, db, email="resilient@example.com", tail=[USUAL_TAPS] * 6
    )
    await _link(db, doctor_id=doctor.id, patient_id=patient_id)

    async def _unavailable(*_args: object, **_kwargs: object) -> None:
        raise SQLAlchemyError

    monkeypatch.setattr(
        monitoring_service.exception_service,
        "route_longitudinal_result",
        _unavailable,
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=await create_default_plan(db, patient_id),
        events=SLOW_TAPS,
    )

    assert body["result"]["quality"] == "valid"
    assert body["longitudinal"]["state"] == "changed"
    stored = await db.scalar(
        select(LongitudinalResult).where(LongitudinalResult.session_id == int(body["id"]))
    )
    assert stored is not None
    assert stored.state == "changed"
    # This change would have been routed had the queue been reachable, so an
    # empty queue is the outage showing through - not a lost recording.
    assert await _stored_exceptions(db) == []


async def test_reprocessing_one_observation_does_not_duplicate_it(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Routing the same result again returns the row that is already there."""
    patient_id, _token, session_id = await _queued_patient(client, db)

    result = await db.scalar(
        select(LongitudinalResult).where(LongitudinalResult.session_id == session_id)
    )
    definition_id = await db.scalar(
        select(MonitoringSession.assessment_definition_id).where(MonitoringSession.id == session_id)
    )
    assert result is not None
    assert definition_id is not None

    again = await exception_service.route_longitudinal_result(
        db,
        longitudinal_result=result,
        patient_id=patient_id,
        assessment_definition_id=definition_id,
    )
    await db.commit()

    assert again is not None
    assert again.id == (await _stored_exceptions(db))[0].id
    assert len(await _stored_exceptions(db)) == 1


# ------------------------------------------------------------------- scoping


async def test_the_queue_only_shows_the_doctors_own_patients(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Two doctors, two patients, and no crossover in either direction."""
    owner = await _sign_in_doctor(db, name="Dr. Owner", email=DOCTOR_EMAIL)
    other = await _sign_in_doctor(db, name="Dr. Other", email=OTHER_DOCTOR_EMAIL)
    owner_patient, _token, _session = await _patient_with_a_change(
        client, db, email="mine@example.com"
    )
    other_patient, _token2, _session2 = await _patient_with_a_change(
        client, db, email="theirs@example.com"
    )
    await _link(db, doctor_id=owner.id, patient_id=owner_patient)
    await _link(db, doctor_id=other.id, patient_id=other_patient)

    owner_token = await login_doctor(client, email=DOCTOR_EMAIL)
    other_token = await login_doctor(client, email=OTHER_DOCTOR_EMAIL)
    owner_rows = (await client.get("/doctor/exceptions", headers=auth_headers(owner_token))).json()
    other_rows = (await client.get("/doctor/exceptions", headers=auth_headers(other_token))).json()

    assert {row["patient_id"] for row in owner_rows} == {owner_patient}
    assert {row["patient_id"] for row in other_rows} == {other_patient}


async def test_another_doctor_cannot_open_the_exception(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Someone else's queue entry is missing, not forbidden."""
    await _queued_patient(client, db)
    owner_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, owner_token)

    await _sign_in_doctor(db, name="Dr. Stranger", email=OTHER_DOCTOR_EMAIL)
    stranger_token = await login_doctor(client, email=OTHER_DOCTOR_EMAIL)
    response = await client.get(
        f"/doctor/exceptions/{exception_id}", headers=auth_headers(stranger_token)
    )

    assert response.status_code == codes.NOT_FOUND
    assert response.json()["detail"] == "Exception not found in your roster."


async def test_another_doctor_cannot_review_it_either(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    _patient_id, _token, _session = await _queued_patient(client, db)
    owner_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, owner_token)

    await _sign_in_doctor(db, name="Dr. Stranger", email=OTHER_DOCTOR_EMAIL)
    stranger_token = await login_doctor(client, email=OTHER_DOCTOR_EMAIL)
    response = await client.post(
        f"/doctor/exceptions/{exception_id}/review",
        headers=auth_headers(stranger_token),
        json={"status": "reviewed"},
    )

    assert response.status_code == codes.NOT_FOUND
    assert (await _stored_exceptions(db))[0].status == "open"


async def test_a_patient_token_cannot_reach_the_queue(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """A patient session lives in a different table and never resolves here."""
    _patient_id, patient_token, _session = await _queued_patient(client, db)

    response = await client.get("/doctor/exceptions", headers=auth_headers(patient_token))

    assert response.status_code == codes.UNAUTHORIZED


async def test_a_pending_link_is_not_a_roster_membership(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """A requested link shows nothing, exactly as an absent one does."""
    await _queued_patient(client, db, email="pending@example.com", link_status="pending")
    doctor_token = await login_doctor(client)

    listing = await client.get("/doctor/exceptions", headers=auth_headers(doctor_token))
    detail = await client.get("/doctor/exceptions/1", headers=auth_headers(doctor_token))

    assert listing.json() == []
    assert detail.status_code == codes.NOT_FOUND


async def test_an_unknown_exception_is_not_found(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)

    response = await client.get("/doctor/exceptions/9999", headers=auth_headers(doctor_token))

    assert response.status_code == codes.NOT_FOUND


async def test_the_queue_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/doctor/exceptions")

    assert response.status_code == codes.UNAUTHORIZED


# -------------------------------------------------------------------- detail


async def test_the_detail_carries_the_evidence_behind_the_decision(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """A reviewer sees what was recorded and what it was compared against."""
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, doctor_token)

    response = await client.get(
        f"/doctor/exceptions/{exception_id}", headers=auth_headers(doctor_token)
    )

    assert response.status_code == codes.OK
    body = response.json()
    assert body["summary"]["id"] == exception_id
    assert body["routing_rule"] == "supported_single_change"
    assert body["supporting_observations"] == 1
    assert body["recording_quality"] == "valid"
    assert body["total_taps"] == 10
    assert body["mean_inter_tap_interval_ms"] == 3000
    assert body["changed_features"]
    assert body["baseline"] is not None
    assert body["baseline"]["observation_count"] >= 5
    assert body["usable_history_count"] >= 4
    assert body["reviewed_by_doctor_id"] is None
    assert body["review_note"] is None


async def test_the_queue_row_omits_the_raw_recording(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Listing stays a triage view; the motor detail is fetched on purpose."""
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)

    listing = await client.get("/doctor/exceptions", headers=auth_headers(doctor_token))

    row = listing.json()[0]
    assert "total_taps" not in row
    assert "baseline" not in row
    assert row["rationale"]
    assert row["patient_name"]


# -------------------------------------------------------------------- review


async def test_reviewing_records_who_when_and_what(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """The doctor's own words, plus the two facts only they can supply."""
    doctor = await _sign_in_doctor(db)
    patient_id, _token, _session = await _patient_with_a_change(client, db, email="r@example.com")
    await _link(db, doctor_id=doctor.id, patient_id=patient_id)
    doctor_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, doctor_token)

    response = await client.post(
        f"/doctor/exceptions/{exception_id}/review",
        headers=auth_headers(doctor_token),
        json={"status": "reviewed", "note": "Discussed at the 12 September clinic."},
    )

    assert response.status_code == codes.OK
    body = response.json()
    assert body["summary"]["status"] == "reviewed"
    assert body["reviewed_by_doctor_id"] == doctor.id
    assert body["reviewed_at"] is not None
    assert body["review_note"] == "Discussed at the 12 September clinic."

    stored = (await _stored_exceptions(db))[0]
    assert stored.reviewed_by_doctor_id == doctor.id
    assert stored.reviewed_at is not None


async def test_a_dismissal_is_a_distinct_outcome(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Judged and needing no action is a real answer, not an absent one."""
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, doctor_token)

    response = await client.post(
        f"/doctor/exceptions/{exception_id}/review",
        headers=auth_headers(doctor_token),
        json={"status": "dismissed"},
    )

    assert response.status_code == codes.OK
    assert response.json()["summary"]["status"] == "dismissed"
    assert response.json()["review_note"] is None


async def test_an_exception_cannot_be_reviewed_twice(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """The first review stands; a second is a conflict, not a silent overwrite."""
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, doctor_token)

    first = await client.post(
        f"/doctor/exceptions/{exception_id}/review",
        headers=auth_headers(doctor_token),
        json={"status": "reviewed", "note": "First word on it."},
    )
    second = await client.post(
        f"/doctor/exceptions/{exception_id}/review",
        headers=auth_headers(doctor_token),
        json={"status": "dismissed", "note": "Actually, no."},
    )

    assert first.status_code == codes.OK
    assert second.status_code == codes.CONFLICT
    assert second.json()["detail"] == "This exception has already been reviewed."
    stored = (await _stored_exceptions(db))[0]
    assert stored.status == "reviewed"
    assert stored.review_note == "First word on it."


@pytest.mark.parametrize("payload", [{"status": "open"}, {"status": "resolved"}, {}])
async def test_only_a_closing_status_is_accepted(
    client: AsyncClient,
    db: AsyncSession,
    payload: dict[str, Any],
) -> None:
    """``open`` is the arrival state; setting it back would undo a review."""
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, doctor_token)

    response = await client.post(
        f"/doctor/exceptions/{exception_id}/review",
        headers=auth_headers(doctor_token),
        json=payload,
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY
    assert (await _stored_exceptions(db))[0].status == "open"


async def test_the_service_refuses_an_arrival_state_as_a_review(
    db: AsyncSession,
) -> None:
    """Defence at the service boundary, not just the schema.

    The API rejects `open` with a 422 before a request reaches here, so this
    guard is what stops any other caller from quietly un-reviewing a closed
    exception by setting it back.
    """
    with pytest.raises(exception_service.UnreviewableStatusError):
        await exception_service.review_exception(
            db,
            doctor_id=1,
            exception_id=1,
            status=ExceptionStatus.OPEN,
        )


async def test_reviewing_something_that_does_not_exist_is_not_found(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)

    response = await client.post(
        "/doctor/exceptions/9999/review",
        headers=auth_headers(doctor_token),
        json={"status": "reviewed"},
    )

    assert response.status_code == codes.NOT_FOUND


# ------------------------------------------------------------------- filters


async def test_the_queue_can_be_filtered_by_status(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Triage means asking for only what is still waiting."""
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)
    exception_id = await _only_exception_id(client, doctor_token)
    await client.post(
        f"/doctor/exceptions/{exception_id}/review",
        headers=auth_headers(doctor_token),
        json={"status": "reviewed"},
    )

    open_rows = await client.get(
        "/doctor/exceptions?status=open", headers=auth_headers(doctor_token)
    )
    reviewed_rows = await client.get(
        "/doctor/exceptions?status=reviewed", headers=auth_headers(doctor_token)
    )

    assert open_rows.json() == []
    assert [row["id"] for row in reviewed_rows.json()] == [exception_id]


async def test_the_queue_can_be_filtered_by_patient(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    doctor = await _sign_in_doctor(db)
    first, _token, _session = await _patient_with_a_change(client, db, email="one@example.com")
    second, _token2, _session2 = await _patient_with_a_change(client, db, email="two@example.com")
    await _link(db, doctor_id=doctor.id, patient_id=first)
    await _link(db, doctor_id=doctor.id, patient_id=second)
    doctor_token = await login_doctor(client)

    everyone = (await client.get("/doctor/exceptions", headers=auth_headers(doctor_token))).json()
    just_one = (
        await client.get(
            f"/doctor/exceptions?patient_id={second}", headers=auth_headers(doctor_token)
        )
    ).json()

    assert len(everyone) == 2
    assert {row["patient_id"] for row in just_one} == {second}


async def test_the_queue_is_newest_first(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """A queue a reviewer reads oldest-first is a queue they read wrong."""
    await _queued_patient(client, db, email="ordered@example.com", tail=[SLOW_TAPS] * 3)
    doctor_token = await login_doctor(client)

    rows = (await client.get("/doctor/exceptions", headers=auth_headers(doctor_token))).json()

    assert [row["created_at"] for row in rows] == sorted(
        (row["created_at"] for row in rows), reverse=True
    )


async def test_the_page_size_is_bounded(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    await _queued_patient(client, db)
    doctor_token = await login_doctor(client)

    response = await client.get("/doctor/exceptions?limit=1000", headers=auth_headers(doctor_token))

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


# --------------------------------------------------------------------- scale


async def _statements_for(client: AsyncClient, headers: dict[str, str], query: str) -> int:
    """Issue one queue request and report how many statements it cost."""
    seen: list[object] = []

    def _count(*_args: object) -> None:
        seen.append(None)

    event.listen(test_engine.sync_engine, "before_cursor_execute", _count)
    try:
        response = await client.get(f"/doctor/exceptions{query}", headers=headers)
        assert response.status_code == codes.OK, response.text
        return len(seen)
    finally:
        event.remove(test_engine.sync_engine, "before_cursor_execute", _count)


async def test_listing_the_queue_costs_the_same_however_long_it_is(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """A page of the queue is a fixed number of queries, so the portal cannot
    degrade row by row as the queue grows."""
    doctor = await _sign_in_doctor(db)
    patient_id, _token, _session = await _patient_with_a_change(
        client, db, email="long@example.com", tail=[SLOW_TAPS] * 4
    )
    await _link(db, doctor_id=doctor.id, patient_id=patient_id)
    doctor_token = await login_doctor(client)
    headers = auth_headers(doctor_token)

    one_row = await _statements_for(client, headers, "?limit=1")
    all_rows = await _statements_for(client, headers, "")
    rows = (await client.get("/doctor/exceptions", headers=auth_headers(doctor_token))).json()

    assert len(rows) == 4
    assert one_row == all_rows
