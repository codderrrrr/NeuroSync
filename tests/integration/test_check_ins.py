"""API integration tests for patient symptom check-ins."""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient, codes
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.check_ins.models import CheckIn
from tests.factories import auth_headers, signup_patient

VALID_PAYLOAD = {
    "tremor": 2,
    "stiffness": 1,
    "slowness": 0,
    "balance": 3,
}


async def test_endpoints_require_authentication(client: AsyncClient) -> None:
    response = await client.post("/check-ins", json=VALID_PAYLOAD)
    assert response.status_code == codes.UNAUTHORIZED

    response = await client.get("/check-ins")
    assert response.status_code == codes.UNAUTHORIZED

    response = await client.get("/check-ins/1")
    assert response.status_code == codes.UNAUTHORIZED


async def test_create_persists_check_in_for_authenticated_patient(
    client: AsyncClient,
    db: AsyncSession,
) -> None:
    patient_id, token = await signup_patient(client)
    payload = {
        **VALID_PAYLOAD,
        "note": "  tremor worse after lunch  ",
        "recorded_at": "2026-06-18T10:30:00+00:00",
    }

    response = await client.post("/check-ins", headers=auth_headers(token), json=payload)

    assert response.status_code == codes.CREATED, response.text
    body = response.json()
    assert body["note"] == "tremor worse after lunch"
    assert datetime.fromisoformat(body["recorded_at"]) == datetime(2026, 6, 18, 10, 30, tzinfo=UTC)

    row = await db.scalar(select(CheckIn).where(CheckIn.id == body["id"]))
    assert row is not None
    assert row.patient_id == patient_id
    assert row.tremor == payload["tremor"]
    assert row.stiffness == payload["stiffness"]


async def test_create_defaults_recorded_at_to_now(client: AsyncClient) -> None:
    _, token = await signup_patient(client)

    response = await client.post("/check-ins", headers=auth_headers(token), json=VALID_PAYLOAD)

    assert response.status_code == codes.CREATED, response.text
    recorded_at = datetime.fromisoformat(response.json()["recorded_at"])
    assert abs(datetime.now(UTC) - recorded_at) < timedelta(minutes=1)


async def test_create_stores_blank_note_as_null(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    payload = {**VALID_PAYLOAD, "note": "   "}

    response = await client.post("/check-ins", headers=auth_headers(token), json=payload)

    assert response.status_code == codes.CREATED, response.text
    assert response.json()["note"] is None


async def test_create_rejects_severity_outside_allowed_range(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    payload = {**VALID_PAYLOAD, "tremor": 5}

    response = await client.post("/check-ins", headers=auth_headers(token), json=payload)

    assert response.status_code == codes.UNPROCESSABLE_ENTITY


async def test_list_returns_only_this_patients_check_ins_newest_first(
    client: AsyncClient,
) -> None:
    _, token_a = await signup_patient(client, email="patient-a@example.com")
    _, token_b = await signup_patient(client, email="patient-b@example.com")

    created_ids_a: list[int] = []
    for recorded_at in ("2026-06-01T08:00:00+00:00", "2026-06-02T08:00:00+00:00"):
        response = await client.post(
            "/check-ins",
            headers=auth_headers(token_a),
            json={**VALID_PAYLOAD, "recorded_at": recorded_at},
        )
        assert response.status_code == codes.CREATED, response.text
        created_ids_a.append(response.json()["id"])
    response = await client.post(
        "/check-ins",
        headers=auth_headers(token_b),
        json={**VALID_PAYLOAD, "recorded_at": "2026-06-03T08:00:00+00:00"},
    )
    assert response.status_code == codes.CREATED, response.text

    response = await client.get("/check-ins", headers=auth_headers(token_a))
    assert response.status_code == codes.OK
    items_a = response.json()
    assert len(items_a) == len(created_ids_a)
    # Newest first: the most recently recorded check-in is returned first.
    assert [item["id"] for item in items_a] == list(reversed(created_ids_a))
    first_recorded = datetime.fromisoformat(items_a[0]["recorded_at"])
    second_recorded = datetime.fromisoformat(items_a[1]["recorded_at"])
    assert first_recorded > second_recorded

    response = await client.get("/check-ins", headers=auth_headers(token_b))
    assert response.status_code == codes.OK
    items_b = response.json()
    assert len(items_b) == 1
    assert items_b[0]["id"] != items_a[0]["id"]


async def test_list_respects_limit(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    limit = 2
    for day in (1, 2, 3):
        response = await client.post(
            "/check-ins",
            headers=auth_headers(token),
            json={**VALID_PAYLOAD, "recorded_at": f"2026-06-0{day}T08:00:00+00:00"},
        )
        assert response.status_code == codes.CREATED, response.text

    response = await client.get(
        "/check-ins",
        headers=auth_headers(token),
        params={"limit": limit},
    )

    assert response.status_code == codes.OK
    items = response.json()
    assert len(items) == limit
    # The newest entries are kept.
    newest_recorded = datetime.fromisoformat(items[0]["recorded_at"])
    assert newest_recorded == datetime(2026, 6, 3, 8, 0, tzinfo=UTC)


async def test_detail_returns_own_check_in(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    created = await client.post(
        "/check-ins",
        headers=auth_headers(token),
        json=VALID_PAYLOAD,
    )
    assert created.status_code == codes.CREATED, created.text

    response = await client.get(
        f"/check-ins/{created.json()['id']}",
        headers=auth_headers(token),
    )

    assert response.status_code == codes.OK
    assert response.json()["id"] == created.json()["id"]


async def test_detail_hides_other_patients_check_in(client: AsyncClient) -> None:
    _, token_a = await signup_patient(client, email="patient-a@example.com")
    _, token_b = await signup_patient(client, email="patient-b@example.com")
    created = await client.post(
        "/check-ins",
        headers=auth_headers(token_b),
        json=VALID_PAYLOAD,
    )
    assert created.status_code == codes.CREATED, created.text

    response = await client.get(
        f"/check-ins/{created.json()['id']}",
        headers=auth_headers(token_a),
    )

    assert response.status_code == codes.NOT_FOUND


async def test_detail_returns_not_found_for_unknown_check_in(client: AsyncClient) -> None:
    _, token = await signup_patient(client)

    response = await client.get("/check-ins/999999", headers=auth_headers(token))

    assert response.status_code == codes.NOT_FOUND


async def test_create_rejects_future_recorded_at(client: AsyncClient) -> None:
    _, token = await signup_patient(client)
    future = (datetime.now(UTC) + timedelta(hours=1)).isoformat()
    payload = {**VALID_PAYLOAD, "recorded_at": future}

    response = await client.post("/check-ins", headers=auth_headers(token), json=payload)

    assert response.status_code == codes.UNPROCESSABLE_ENTITY
