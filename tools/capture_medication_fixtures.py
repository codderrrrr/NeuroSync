"""Capture real backend payloads as patient-app contract fixtures.

Boots the application against the test database and records the exact JSON the
API returns for the medication-aware flow, so the Flutter parsers are checked
against the server rather than against a hand-written guess.

Run from the repository root:

    ENVIRONMENT=test uv run python tools/capture_medication_fixtures.py
"""

import asyncio
import json
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from neurosync.db import get_session
from neurosync.main import app
from tests.conftest import _test_get_session, test_session_factory
from tests.factories import auth_headers, create_default_plan, steady_taps

REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = REPO_ROOT / "apps/patient_app/test/features/monitoring/fixtures"

PATIENT_EMAIL = "fixture-capture@patient.example.com"
PASSWORD = "correct-horse-battery"

USUAL_TAPS = steady_taps(count=30, interval_ms=1000)
SLOW_TAPS = steady_taps(count=10, interval_ms=3000)

# Everything this run creates, patient-owned, oldest dependency last.
_DOMAIN_TABLES = (
    "medication_events, medications, monitoring_results, "
    "monitoring_session_events, monitoring_sessions, monitoring_plan_items, "
    "monitoring_plans, patient_sessions, patients"
)

# Only the fixtures this slice introduces. Earlier ones stay untouched so their
# own contract checks keep testing exactly what they did.
_NEW_FIXTURES = (
    "medication_list",
    "session_recently_after_medication",
    "session_later_after_medication",
    "session_unknown_context",
    "session_changed_with_context",
    "session_undated_dose",
    "medication_events",
)


def _ago(minutes: float) -> datetime:
    return datetime.now(UTC) - timedelta(minutes=minutes)


async def _reset() -> None:
    """Leave the database as it was found, before and after the run."""
    async with test_session_factory() as session:
        await session.execute(text(f"TRUNCATE {_DOMAIN_TABLES} RESTART IDENTITY CASCADE"))
        await session.commit()


async def main() -> None:
    await _reset()
    app.dependency_overrides[get_session] = _test_get_session
    captured: dict[str, Any] = {}

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://fixture"
        ) as client:
            signup = await client.post(
                "/auth/signup",
                json={
                    "name": "Fixture Capture",
                    "email": PATIENT_EMAIL,
                    "password": PASSWORD,
                },
            )
            signup.raise_for_status()
            token = str(signup.json()["access_token"])
            patient_id = int(signup.json()["patient"]["id"])
            headers = auth_headers(token)

            async with test_session_factory() as session:
                plan_item_id = await create_default_plan(session, patient_id)

            medication = await client.post(
                "/medications",
                headers=headers,
                json={
                    "name": "Levodopa",
                    "dose_label": "100mg",
                    "frequency_label": "4 times daily",
                },
            )
            medication.raise_for_status()
            medication_id = int(medication.json()["id"])
            # The list endpoint, not the create response: the app parses this
            # shape on the home screen and the medication list.
            captured["medication_list"] = (await client.get("/medications", headers=headers)).json()

            async def record_dose(minutes_ago: float | None) -> int:
                """Record one reported dose; None means the patient could not say."""
                payload: dict[str, Any] = {
                    "medication_id": medication_id,
                    "adherence": "taken",
                }
                if minutes_ago is not None:
                    payload["taken_at"] = _ago(minutes_ago).isoformat()
                response = await client.post("/medications/events", headers=headers, json=payload)
                response.raise_for_status()
                return int(response.json()["id"])

            async def complete(events: list[dict[str, object]], event_id: int | None) -> Any:
                started = await client.post(
                    "/monitoring/sessions",
                    headers=headers,
                    json={"plan_item_id": plan_item_id},
                )
                started.raise_for_status()
                response = await client.post(
                    f"/monitoring/sessions/{started.json()['id']}/complete",
                    headers=headers,
                    json={"events": events, "medication_event_id": event_id},
                )
                response.raise_for_status()
                return response.json()

            # A dose the patient could date, and one they could not.
            undated_event_id = await record_dose(None)

            # Three sessions with no medication information: the baseline has to
            # build from them, which proves context is not required for history.
            for _ in range(3):
                await complete(USUAL_TAPS, None)

            # First session with a known context: the baseline is established,
            # but nothing yet corroborates this particular context.
            captured["session_recently_after_medication"] = await complete(
                USUAL_TAPS, await record_dose(30)
            )
            # Then three more under the same context.
            for _ in range(3):
                await complete(USUAL_TAPS, await record_dose(30))

            # Switch to a different window, and rebuild its history from scratch:
            # comparability is per context, not a running total.
            for _ in range(4):
                await complete(USUAL_TAPS, await record_dose(90))

            # Enough matching history this time for the strongest reading.
            captured["session_later_after_medication"] = await complete(
                USUAL_TAPS, await record_dose(150)
            )

            # The patient attached no dose at all.
            captured["session_unknown_context"] = await complete(USUAL_TAPS, None)

            # A session that departed from the patient's usual range, and the
            # dose event recorded but never dated.
            captured["session_changed_with_context"] = await complete(
                SLOW_TAPS, await record_dose(75)
            )
            await complete(USUAL_TAPS, undated_event_id)
            captured["session_undated_dose"] = (
                await client.get("/monitoring/sessions?limit=1", headers=headers)
            ).json()[0]

            captured["medication_events"] = (
                await client.get("/medications/events?limit=20", headers=headers)
            ).json()
    finally:
        app.dependency_overrides.pop(get_session, None)

    for name in _NEW_FIXTURES:
        path = FIXTURE_DIR / f"{name}.json"
        path.write_text(json.dumps(captured[name], indent=2) + "\n")
        print(f"wrote {path.relative_to(REPO_ROOT)}")

    await _reset()


if __name__ == "__main__":
    asyncio.run(main())
