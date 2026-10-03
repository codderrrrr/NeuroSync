"""API integration tests for the longitudinal monitoring layer.

These drive the real pipeline end to end through the API, so the baseline,
the comparison and the persisted longitudinal result are all produced by the
code a patient actually runs.
"""

from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from neurosync.modules.monitoring.models import (
    LongitudinalResult,
    MonitoringSession,
    PatientBaseline,
)
from tests.factories import (
    auth_headers,
    complete_a_session,
    create_default_plan,
    signup_patient,
    steady_taps,
)

# A steady 30-second recording at one tap per second: 30 taps spread over 29s.
USUAL_TAPS = steady_taps(count=30, interval_ms=1000)
# Clearly slower: a tap roughly every 3 seconds.
SLOW_TAPS = steady_taps(count=10, interval_ms=3000)
# Too short to use: under half the 30-second target.
TOO_SHORT_TAPS = steady_taps(count=4, interval_ms=1000)


async def _baseline_for(db: AsyncSession, patient_id: int) -> PatientBaseline | None:
    return await db.scalar(select(PatientBaseline).where(PatientBaseline.patient_id == patient_id))


async def _record_for(db: AsyncSession, session_id: int) -> LongitudinalResult | None:
    return await db.scalar(
        select(LongitudinalResult).where(LongitudinalResult.session_id == session_id)
    )


# ------------------------------------------------------ insufficient history


async def test_first_session_reports_insufficient_data(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    body = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
    )

    assert body["result"]["quality"] == "valid"
    assert body["longitudinal"]["state"] == "insufficient_data"
    assert body["longitudinal"]["usable_history_count"] == 0
    assert body["longitudinal"]["baseline_confidence"] is None
    assert body["longitudinal"]["is_confident"] is False


async def test_second_session_is_still_insufficient(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    for _ in range(2):
        body = await complete_a_session(
            client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
        )
        assert body["longitudinal"]["state"] == "insufficient_data"

    assert body["longitudinal"]["usable_history_count"] == 1


async def test_baseline_endpoint_returns_404_until_history_exists(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    await create_default_plan(db, patient_id)

    response = await client.get("/monitoring/baseline", headers=auth_headers(token))

    assert response.status_code == codes.NOT_FOUND


# ----------------------------------------------------- baseline established


async def test_fourth_session_is_compared_against_an_established_baseline(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    states = []
    for _ in range(4):
        body = await complete_a_session(
            client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
        )
        states.append(body["longitudinal"]["state"])

    # The first two have no history; the third establishes the baseline from
    # its two predecessors plus itself being stored afterwards; the fourth is
    # the first session actually compared against a baseline.
    assert states[:3] == ["insufficient_data"] * 3
    assert states[3] == "within_baseline"
    assert body["longitudinal"]["usable_history_count"] == 3
    assert body["longitudinal"]["baseline_confidence"] == "full"
    assert body["longitudinal"]["is_confident"] is True


async def test_baseline_is_persisted_and_reproducible(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(3):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    stored = await _baseline_for(db, patient_id)

    assert stored is not None
    # Built from the three sessions stored so far.
    assert stored.observation_count == 3
    assert stored.valid_observation_count == 3
    assert stored.borderline_observation_count == 0
    assert stored.confidence == "full"

    # Reproducible: the stored medians match the observations that produced them.
    sessions = list(
        await db.scalars(
            select(MonitoringSession)
            .options(selectinload(MonitoringSession.result))
            .where(MonitoringSession.patient_id == patient_id)
        )
    )
    rates = sorted(s.result.taps_per_second for s in sessions if s.result is not None)
    assert stored.taps_per_second == rates[1]


async def test_baseline_endpoint_returns_the_patient_baseline(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(3):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    response = await client.get("/monitoring/baseline", headers=auth_headers(token))

    assert response.status_code == codes.OK
    body = response.json()
    assert body["observation_count"] == 3
    assert body["confidence"] == "full"
    assert body["assessment"]["slug"] == "finger_tapping"
    assert "3 comparable session" in body["explanation"]


async def test_baseline_endpoint_requires_authentication(client: AsyncClient) -> None:
    assert (await client.get("/monitoring/baseline")).status_code == codes.UNAUTHORIZED


# ---------------------------------------------------------------- changed


async def test_a_meaningful_slowdown_is_reported_as_changed(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(3):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    body = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=SLOW_TAPS
    )

    longitudinal = body["longitudinal"]
    assert body["result"]["quality"] == "valid"
    assert longitudinal["state"] == "changed"
    # The evidence behind the verdict is stored, not just the verdict.
    assert longitudinal["changed_features"]


async def test_changed_state_records_which_features_moved(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(3):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)
    body = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=SLOW_TAPS
    )

    stored = await _record_for(db, int(body["id"]))

    assert stored is not None
    assert stored.state == "changed"
    assert stored.changed_features
    assert "mean_inter_tap_interval_ms" in stored.changed_features
    assert stored.baseline_id is not None


# --------------------------------------------------------- quality handling


async def test_an_incomplete_session_is_unreliable_and_never_compared(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(3):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    body = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=TOO_SHORT_TAPS
    )

    assert body["result"]["quality"] == "incomplete"
    assert body["longitudinal"]["state"] == "unreliable"
    assert body["longitudinal"]["changed_features"] == []


async def test_incomplete_sessions_do_not_build_a_baseline(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    for _ in range(3):
        body = await complete_a_session(
            client, token=token, plan_item_id=plan_item_id, events=TOO_SHORT_TAPS
        )
        assert body["result"]["quality"] == "incomplete"

    # Three unusable recordings must not produce a baseline.
    assert await _baseline_for(db, patient_id) is None
    assert (await client.get("/monitoring/baseline", headers=auth_headers(token))).status_code == (
        codes.NOT_FOUND
    )


async def test_borderline_sessions_reduce_baseline_confidence(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # Fewer than ten taps is borderline under the quality rules.
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    borderline = steady_taps(count=8, interval_ms=4000)
    for _ in range(3):
        body = await complete_a_session(
            client, token=token, plan_item_id=plan_item_id, events=borderline
        )
        assert body["result"]["quality"] == "borderline", body["result"]

    stored = await _baseline_for(db, patient_id)

    assert stored is not None
    assert stored.observation_count == 3
    assert stored.borderline_observation_count == 3
    assert stored.confidence == "reduced"


async def test_a_reduced_confidence_baseline_is_not_presented_as_settled(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    borderline = steady_taps(count=8, interval_ms=4000)
    for _ in range(4):
        body = await complete_a_session(
            client, token=token, plan_item_id=plan_item_id, events=borderline
        )

    longitudinal = body["longitudinal"]

    assert longitudinal["baseline_confidence"] == "reduced"
    # The client needs this to soften its wording rather than presenting a
    # weakly-supported conclusion as settled.
    assert longitudinal["is_confident"] is False


# ------------------------------------------------------------- persistence


async def test_longitudinal_result_is_stored_for_each_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)

    for _ in range(3):
        body = await complete_a_session(
            client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
        )

    stored = await _record_for(db, int(body["id"]))

    assert stored is not None
    assert stored.state == "insufficient_data"
    assert stored.usable_history_count == 2
    assert stored.session_id == int(body["id"])


async def test_history_returns_the_longitudinal_state_per_session(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(4):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    response = await client.get("/monitoring/sessions", headers=auth_headers(token))

    assert response.status_code == codes.OK
    items = response.json()
    assert len(items) == 4
    # Newest first: the fourth session is the one compared to a baseline.
    assert [item["longitudinal"]["state"] for item in items] == [
        "within_baseline",
        "insufficient_data",
        "insufficient_data",
        "insufficient_data",
    ]


async def test_session_detail_includes_the_longitudinal_state(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    body = await complete_a_session(
        client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS
    )

    response = await client.get(f"/monitoring/sessions/{body['id']}", headers=auth_headers(token))

    assert response.status_code == codes.OK
    assert response.json()["longitudinal"]["state"] == "insufficient_data"


async def test_repeated_sessions_update_the_baseline_row(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    plan_item_id = await create_default_plan(db, patient_id)
    for _ in range(3):
        await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)
    first = await _baseline_for(db, patient_id)
    assert first is not None
    assert first.observation_count == 3

    await complete_a_session(client, token=token, plan_item_id=plan_item_id, events=USUAL_TAPS)

    # One row per patient, refreshed in place rather than duplicated.
    # populate_existing so the assertion reads the committed row rather than the
    # copy this session cached before the fourth session completed.
    rows = list(
        await db.scalars(
            select(PatientBaseline)
            .where(PatientBaseline.patient_id == patient_id)
            .execution_options(populate_existing=True)
        )
    )
    assert len(rows) == 1
    assert rows[0].observation_count == 4


# --------------------------------------------------------------- isolation


async def test_one_patients_baseline_never_affects_another(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    # Patient A builds a slow baseline; patient B must not inherit it.
    a_id, a_token = await signup_patient(client, email="a@example.com")
    a_item = await create_default_plan(db, a_id)
    for _ in range(3):
        await complete_a_session(client, token=a_token, plan_item_id=a_item, events=SLOW_TAPS)

    b_id, b_token = await signup_patient(client, email="b@example.com")
    b_item = await create_default_plan(db, b_id)

    body = await complete_a_session(client, token=b_token, plan_item_id=b_item, events=USUAL_TAPS)

    # B has one session of their own and no baseline at all.
    assert body["longitudinal"]["state"] == "insufficient_data"
    assert body["longitudinal"]["usable_history_count"] == 0
    assert await _baseline_for(db, b_id) is None
    assert await _baseline_for(db, a_id) is not None


async def test_another_patients_sessions_are_not_visible_in_history(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    a_id, a_token = await signup_patient(client, email="a@example.com")
    a_item = await create_default_plan(db, a_id)
    for _ in range(4):
        await complete_a_session(client, token=a_token, plan_item_id=a_item, events=USUAL_TAPS)

    b_id, b_token = await signup_patient(client, email="b@example.com")
    b_item = await create_default_plan(db, b_id)
    await complete_a_session(client, token=b_token, plan_item_id=b_item, events=USUAL_TAPS)

    response = await client.get("/monitoring/sessions", headers=auth_headers(b_token))

    assert response.status_code == codes.OK
    assert len(response.json()) == 1
