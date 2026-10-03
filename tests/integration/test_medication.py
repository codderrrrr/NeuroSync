"""API integration tests for medication-aware longitudinal monitoring.

These drive the whole chain through the API a patient actually uses:

    medication → dose event → monitoring session → longitudinal result
    → medication context → evidence strength

and assert the boundary rules that matter most: unknown stays unknown, one
patient can never touch another's medication data, and historical observations
are never retrofitted with a context they never had.
"""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.medication.models import MedicationEvent
from neurosync.modules.monitoring import service as monitoring_service
from neurosync.modules.monitoring.models import LongitudinalResult, PatientBaseline
from tests.factories import (
    ReportedDose,
    auth_headers,
    complete_a_session,
    create_default_plan,
    create_medication_event,
    create_medication_record,
    signup_patient,
    steady_taps,
)

USUAL_TAPS = steady_taps(count=30, interval_ms=1000)
# Clearly slower than the usual recording: a tap roughly every 3 seconds.
SLOW_TAPS = steady_taps(count=10, interval_ms=3000)
# Under half the 30-second target, so quality rejects it.
TOO_SHORT_TAPS = steady_taps(count=4, interval_ms=1000)


def _ago(**kwargs: float) -> datetime:
    """A timestamp relative to now, in UTC."""
    return datetime.now(UTC) - timedelta(**kwargs)


async def _record_for(db: AsyncSession, session_id: int) -> LongitudinalResult | None:
    return await db.scalar(
        select(LongitudinalResult).where(LongitudinalResult.session_id == session_id)
    )


# --------------------------------------------------------------- medication records


async def test_a_patient_records_a_medication_verbatim(
    client: AsyncClient,
) -> None:
    _, token = await signup_patient(client)

    response = await client.post(
        "/medications",
        headers=auth_headers(token),
        json={"name": "Levodopa", "dose_label": "100mg", "frequency_label": "4 times daily"},
    )

    assert response.status_code == codes.CREATED, response.text
    body = response.json()
    # Dose and frequency travel as the words entered; nothing parses them.
    assert body["name"] == "Levodopa"
    assert body["dose_label"] == "100mg"
    assert body["frequency_label"] == "4 times daily"
    assert body["is_active"] is True


async def test_a_medication_needs_a_name(client: AsyncClient) -> None:
    _, token = await signup_patient(client)

    response = await client.post(
        "/medications",
        headers=auth_headers(token),
        json={"name": "   "},
    )

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


async def test_deactivating_a_medication_keeps_its_history(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    created = await create_medication_record(client, token=token)

    response = await client.patch(
        f"/medications/{created['id']}",
        headers=auth_headers(token),
        params={"is_active": False},
    )

    assert response.status_code == codes.OK, response.text
    assert response.json()["is_active"] is False
    listed = await client.get("/medications", headers=auth_headers(token))
    assert [m["id"] for m in listed.json()] == [created["id"]]


async def test_medication_routes_require_authentication(client: AsyncClient) -> None:
    assert (await client.get("/medications")).status_code in (
        codes.UNAUTHORIZED,
        codes.FORBIDDEN,
    )
    assert (await client.get("/medications/events")).status_code in (
        codes.UNAUTHORIZED,
        codes.FORBIDDEN,
    )


# ------------------------------------------------------------------ ownership


async def test_one_patient_cannot_list_another_patients_medications(
    client: AsyncClient,
) -> None:
    _, first_token = await signup_patient(client, email="first@example.com")
    await create_medication_record(client, token=first_token, name="First Patient's Drug")
    _, second_token = await signup_patient(client, email="second@example.com")

    response = await client.get("/medications", headers=auth_headers(second_token))

    assert response.status_code == codes.OK, response.text
    assert response.json() == []


async def test_one_patient_cannot_list_another_patients_dose_events(
    client: AsyncClient,
) -> None:
    _, first_token = await signup_patient(client, email="first@example.com")
    medication = await create_medication_record(client, token=first_token)
    await create_medication_event(
        client,
        token=first_token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=20)),
    )
    _, second_token = await signup_patient(client, email="second@example.com")

    response = await client.get("/medications/events", headers=auth_headers(second_token))

    assert response.status_code == codes.OK, response.text
    assert response.json() == []


async def test_a_dose_event_cannot_be_recorded_against_another_patients_medication(
    client: AsyncClient,
) -> None:
    _, first_token = await signup_patient(client, email="first@example.com")
    medication = await create_medication_record(client, token=first_token)
    _, second_token = await signup_patient(client, email="second@example.com")

    response = await client.post(
        "/medications/events",
        headers=auth_headers(second_token),
        json={
            "medication_id": medication["id"],
            "adherence": "taken",
            "taken_at": _ago(minutes=20).isoformat(),
        },
    )

    # Reported as missing, not forbidden: another patient's record must be
    # indistinguishable from one that does not exist.
    assert response.status_code == codes.NOT_FOUND


async def test_a_patient_cannot_attach_another_patients_dose_event_to_a_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    first_id, first_token = await signup_patient(client, email="first@example.com")
    medication = await create_medication_record(client, token=first_token)
    event = await create_medication_event(
        client,
        token=first_token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=20)),
    )
    second_id, second_token = await signup_patient(client, email="second@example.com")
    second_plan_item = await create_default_plan(db, second_id)

    started = await client.post(
        "/monitoring/sessions",
        headers=auth_headers(second_token),
        json={"plan_item_id": second_plan_item},
    )
    assert started.status_code == codes.CREATED, started.text

    response = await client.post(
        f"/monitoring/sessions/{started.json()['id']}/complete",
        headers=auth_headers(second_token),
        json={"events": USUAL_TAPS, "medication_event_id": event["id"]},
    )

    assert response.status_code == codes.NOT_FOUND

    # The rejected session was not silently completed with no context either:
    # the whole request is refused, so nothing is recorded about the other
    # patient's dose.
    still_open = await client.get(
        f"/monitoring/sessions/{started.json()['id']}",
        headers=auth_headers(second_token),
    )
    assert still_open.status_code == codes.OK
    assert still_open.json()["status"] == "in_progress"
    assert await _record_for(db, int(started.json()["id"])) is None


# ------------------------------------------------------- the complete chain


async def test_a_reported_dose_reaches_the_persisted_longitudinal_result(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """medication → dose event → session → longitudinal result → context."""
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token, name="Levodopa")
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=105)),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    summary = body["longitudinal"]
    assert summary["medication_context"] == "later_after_medication"
    assert summary["minutes_since_medication"] == 105
    assert summary["medication_name"] == "Levodopa"
    assert "1h 45m after" in summary["medication_note"]

    # The same facts are in the database, not just the response.
    stored = await _record_for(db, int(body["id"]))
    assert stored is not None
    assert stored.medication_event_id == event["id"]
    assert stored.medication_context == "later_after_medication"
    assert stored.minutes_since_medication == 105
    assert stored.evidence_strength == "insufficient"


async def test_a_recent_dose_is_labelled_recently_after(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=25)),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    assert body["longitudinal"]["medication_context"] == "recently_after_medication"
    assert body["longitudinal"]["minutes_since_medication"] == 25


async def test_a_dose_the_patient_scheduled_for_later_is_before_medication(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=datetime.now(UTC) + timedelta(minutes=40)),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    summary = body["longitudinal"]
    assert summary["medication_context"] == "before_medication"
    assert summary["minutes_since_medication"] == 40
    assert "before the reported medication" in summary["medication_note"]


# ------------------------------------------------------------ unknown timing


async def test_no_attached_event_leaves_the_context_unknown(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    await create_medication_record(client, token=token)

    body = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
    )

    summary = body["longitudinal"]
    assert summary["medication_context"] == "unknown"
    assert summary["minutes_since_medication"] is None
    assert summary["medication_name"] is None
    assert summary["medication_note"] == (
        "Medication timing was not available for this assessment."
    )
    stored = await _record_for(db, int(body["id"]))
    assert stored is not None
    assert stored.medication_event_id is None


async def test_a_dose_with_no_recorded_time_stays_unknown(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=None),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    summary = body["longitudinal"]
    assert summary["medication_context"] == "unknown"
    assert summary["minutes_since_medication"] is None
    # The event is still associated, so the record of "the patient said they
    # took it but could not say when" is not lost.
    stored = await _record_for(db, int(body["id"]))
    assert stored is not None and stored.medication_event_id == event["id"]


async def test_a_not_taken_dose_stays_unknown(client: AsyncClient, db: AsyncSession) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(adherence="not_taken"),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    assert body["longitudinal"]["medication_context"] == "unknown"
    assert body["longitudinal"]["minutes_since_medication"] is None


async def test_a_not_sure_dose_stays_unknown_even_with_a_time(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(adherence="not_sure", taken_at=_ago(minutes=15)),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    assert body["longitudinal"]["medication_context"] == "unknown"


async def test_an_inactive_medication_cannot_supply_a_context(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=15)),
    )
    await client.patch(
        f"/medications/{medication['id']}",
        headers=auth_headers(token),
        params={"is_active": False},
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    assert body["longitudinal"]["medication_context"] == "unknown"


async def test_each_session_keeps_the_event_it_was_given(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Two doses, two sessions: the association is per assessment, not global."""
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    recent = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=10)),
    )
    later = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(hours=4)),
    )

    first = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(recent["id"]),
    )
    second = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(later["id"]),
    )

    assert first["longitudinal"]["medication_context"] == "recently_after_medication"
    assert second["longitudinal"]["medication_context"] == "later_after_medication"
    assert first["longitudinal"]["minutes_since_medication"] == 10
    assert second["longitudinal"]["minutes_since_medication"] == 240


# --------------------------------------------- longitudinal integration


async def test_a_healthy_session_with_known_context_reaches_stronger_evidence(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)

    summaries = []
    for _ in range(5):
        event = await create_medication_event(
            client,
            token=token,
            medication_id=int(medication["id"]),
            dose=ReportedDose(taken_at=_ago(minutes=30)),
        )
        body = await complete_a_session(
            client,
            token=token,
            plan_item_id=plan_item_id,
            events=USUAL_TAPS,
            medication_event_id=int(event["id"]),
        )
        summaries.append(body["longitudinal"])

    # The baseline is established by the third session; the fifth is the first
    # with enough corroborated history behind it.
    assert [s["state"] for s in summaries] == [
        "insufficient_data",
        "insufficient_data",
        "insufficient_data",
        "within_baseline",
        "within_baseline",
    ]
    assert [s["medication_context"] for s in summaries] == ["recently_after_medication"] * 5
    assert [s["evidence_strength"] for s in summaries] == [
        "insufficient",
        "insufficient",
        "insufficient",
        "limited",
        "stronger",
    ]
    assert summaries[-1]["comparable_observation_count"] == 4


async def test_a_changed_session_with_known_context_keeps_its_context(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)

    for _ in range(4):
        event = await create_medication_event(
            client,
            token=token,
            medication_id=int(medication["id"]),
            dose=ReportedDose(taken_at=_ago(minutes=30)),
        )
        await complete_a_session(
            client,
            token=token,
            plan_item_id=plan_item_id,
            events=USUAL_TAPS,
            medication_event_id=int(event["id"]),
        )

    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=30)),
    )
    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=SLOW_TAPS,
        medication_event_id=int(event["id"]),
    )

    summary = body["longitudinal"]
    assert summary["state"] == "changed"
    assert summary["changed_features"]
    # A difference is described, never explained: the medication context
    # travels beside it without altering the state.
    assert summary["medication_context"] == "recently_after_medication"
    assert summary["minutes_since_medication"] == 30
    assert summary["evidence_strength"] == "stronger"


async def test_insufficient_history_with_a_known_context_still_preserves_it(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=30)),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    summary = body["longitudinal"]
    assert summary["state"] == "insufficient_data"
    # The context is still true and still recorded; there was simply nothing
    # to compare it against.
    assert summary["medication_context"] == "recently_after_medication"
    assert summary["medication_note"].endswith("after the reported medication.")
    # No comparison was made, so the evidence cannot claim more than that.
    assert summary["evidence_strength"] == "insufficient"


async def test_an_unusable_recording_with_a_known_context_supports_nothing(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=30)),
    )

    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=TOO_SHORT_TAPS,
        medication_event_id=int(event["id"]),
    )

    summary = body["longitudinal"]
    assert summary["state"] == "unreliable"
    assert summary["medication_context"] == "recently_after_medication"
    assert summary["evidence_strength"] == "insufficient"


async def test_unknown_timing_never_produces_medication_aware_evidence(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    bodies = [
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)
        for _ in range(6)
    ]

    summary = bodies[-1]["longitudinal"]
    assert summary["state"] == "within_baseline"
    assert summary["usable_history_count"] >= 4
    assert summary["medication_context"] == "unknown"
    # Plenty of history, but the reading must not be presented as
    # medication-aware evidence when no timing was ever reported.
    assert summary["evidence_strength"] == "moderate"
    assert summary["evidence_strength"] != "stronger"
    assert summary["comparable_observation_count"] == 0


# ------------------------------------------------------- comparability


async def test_history_without_context_is_not_counted_as_comparable(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Contexts are not mixed: unknown history cannot corroborate known timing."""
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)

    # Three sessions with no medication information at all.
    for _ in range(3):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=30)),
    )
    first_known = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    # The three unknown-context sessions are still history — they still build
    # the baseline — but they are not treated as evidence about this context.
    assert first_known["longitudinal"]["usable_history_count"] == 3
    assert first_known["longitudinal"]["comparable_observation_count"] == 0
    assert first_known["longitudinal"]["evidence_strength"] == "limited"


async def test_sessions_are_never_retrofitted_with_an_invented_context(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """A later session's event cannot be pushed back onto an earlier one."""
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)

    earlier = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
    )
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=30)),
    )
    await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    stored = await _record_for(db, int(earlier["id"]))
    assert stored is not None
    assert stored.medication_context == "unknown"
    assert stored.medication_event_id is None
    assert stored.minutes_since_medication is None


# ------------------------------------------------------------- persistence


async def test_deleting_a_medication_event_keeps_the_session_readable(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """The comparison must not vanish because a context reference went away."""
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=30)),
    )
    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    stored_event = await db.get(MedicationEvent, int(event["id"]))
    assert stored_event is not None
    await db.delete(stored_event)
    await db.commit()

    reread = await client.get(
        f"/monitoring/sessions/{body['id']}",
        headers=auth_headers(token),
    )
    assert reread.status_code == codes.OK, reread.text
    summary = reread.json()["longitudinal"]
    # The context recorded at the time survives; only the link is gone.
    assert summary["medication_context"] == "recently_after_medication"
    assert summary["minutes_since_medication"] == 30
    assert summary["medication_name"] is None


async def test_the_stored_result_carries_every_documented_field(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token)
    event = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=30)),
    )
    body = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(event["id"]),
    )

    stored = await _record_for(db, int(body["id"]))
    assert stored is not None
    # Longitudinal state, baseline reference, medication association and
    # evidence all answered from one row, as the schema promises.
    assert stored.state == "insufficient_data"
    assert stored.usable_history_count == 0
    assert stored.baseline_id is None
    assert stored.medication_event_id == event["id"]
    assert stored.medication_context == "recently_after_medication"
    assert stored.minutes_since_medication == 30
    assert stored.evidence_strength == "insufficient"
    assert stored.comparable_observation_count == 0


async def test_dose_events_are_listed_newest_first(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    medication = await create_medication_record(client, token=token)
    first = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(hours=5), scheduled_at=_ago(hours=6)),
    )
    second = await create_medication_event(
        client,
        token=token,
        medication_id=int(medication["id"]),
        dose=ReportedDose(taken_at=_ago(minutes=5)),
    )

    response = await client.get("/medications/events", headers=auth_headers(token))

    assert response.status_code == codes.OK, response.text
    body = response.json()
    assert [e["id"] for e in body] == [second["id"], first["id"]]
    # Each event names its medication, so a history page needs no extra calls.
    assert {e["medication_name"] for e in body} == {"Levodopa"}


async def test_the_history_page_keeps_medication_context_per_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """The list endpoint must carry the same context the detail endpoint does.

    A history page that silently dropped medication context would let a patient
    read two assessments as if they had been recorded the same way.
    """
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    medication = await create_medication_record(client, token=token, name="Levodopa")

    first = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
    )
    second = await complete_a_session(
        client,
        token=token,
        plan_item_id=plan_item_id,
        events=USUAL_TAPS,
        medication_event_id=int(
            (
                await create_medication_event(
                    client,
                    token=token,
                    medication_id=int(medication["id"]),
                    dose=ReportedDose(taken_at=_ago(minutes=45)),
                )
            )["id"]
        ),
    )

    response = await client.get("/monitoring/sessions?limit=30", headers=auth_headers(token))

    assert response.status_code == codes.OK, response.text
    # Newest first.
    by_id = {entry["id"]: entry["longitudinal"] for entry in response.json()}
    assert set(by_id) == {first["id"], second["id"]}

    assert by_id[second["id"]]["medication_context"] == "recently_after_medication"
    assert by_id[second["id"]]["medication_name"] == "Levodopa"
    assert by_id[second["id"]]["minutes_since_medication"] == 45

    # The session with no dose keeps saying so, on the list as on the detail.
    assert by_id[first["id"]]["medication_context"] == "unknown"
    assert by_id[first["id"]]["medication_name"] is None
    assert by_id[first["id"]]["minutes_since_medication"] is None


async def test_the_stored_baseline_is_identical_however_it_is_rebuilt(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    """Reusing the loaded history must not change the stored baseline.

    The longitudinal step now hands its already-loaded observations to the
    baseline rebuild instead of re-querying them. This pins that the shortcut
    produces the same numbers as rebuilding from a fresh read.
    """
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    for _ in range(4):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    stored = await db.scalar(
        select(PatientBaseline).where(PatientBaseline.patient_id == patient_id)
    )
    assert stored is not None
    # Read everything up front: the rollback below expires the instance, and an
    # expired attribute would try to re-fetch itself outside the event loop.
    definition_id = stored.assessment_definition_id
    from_shortcut = _baseline_values(stored)

    await db.rollback()
    db.expunge_all()

    # Rebuild from a fresh read, exactly as the function did before the change.
    rebuilt = await monitoring_service.rebuild_baseline(
        session=db,
        patient_id=patient_id,
        assessment_definition_id=definition_id,
    )

    assert rebuilt is not None
    assert _baseline_values(rebuilt) == from_shortcut


def _baseline_values(baseline: PatientBaseline) -> tuple[object, ...]:
    """The stored baseline's derived values, for comparing two rebuilds."""
    return (
        baseline.taps_per_second,
        baseline.mean_inter_tap_interval_ms,
        baseline.inter_tap_variability_ms,
        baseline.longest_pause_ms,
        baseline.observation_count,
        baseline.valid_observation_count,
        baseline.borderline_observation_count,
        baseline.confidence,
    )
