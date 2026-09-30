"""Unit tests for symptom check-in request validation."""

from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError

from neurosync.modules.check_ins.models import SEVERITY_MAX, SEVERITY_MIN
from neurosync.modules.check_ins.schemas import MAX_NOTE_LENGTH, CheckInCreateRequest


def _payload(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "tremor": 1,
        "stiffness": 2,
        "slowness": 3,
        "balance": 0,
    }
    payload.update(overrides)
    return payload


def test_defaults_note_and_recorded_at_to_none() -> None:
    request = CheckInCreateRequest(**_payload())
    assert request.note is None
    assert request.recorded_at is None


def test_accepts_severity_scale_boundaries() -> None:
    request = CheckInCreateRequest(**_payload(tremor=SEVERITY_MIN, balance=SEVERITY_MAX))
    assert request.tremor == SEVERITY_MIN
    assert request.balance == SEVERITY_MAX


@pytest.mark.parametrize("field", ["tremor", "stiffness", "slowness", "balance"])
@pytest.mark.parametrize("value", [-1, 5])
def test_rejects_severity_outside_allowed_range(field: str, value: int) -> None:
    with pytest.raises(ValidationError):
        CheckInCreateRequest(**_payload(**{field: value}))


def test_blank_note_is_stored_as_no_note() -> None:
    request = CheckInCreateRequest(**_payload(note="   "))
    assert request.note is None


def test_note_is_stripped() -> None:
    request = CheckInCreateRequest(**_payload(note="  tremor worse after lunch  "))
    assert request.note == "tremor worse after lunch"


def test_rejects_note_longer_than_limit() -> None:
    with pytest.raises(ValidationError):
        CheckInCreateRequest(**_payload(note="x" * (MAX_NOTE_LENGTH + 1)))


def test_accepts_recorded_at_with_timezone() -> None:
    recorded_at = datetime(2026, 6, 18, 8, 30, tzinfo=UTC)
    request = CheckInCreateRequest(**_payload(recorded_at=recorded_at))
    assert request.recorded_at == recorded_at


def test_accepts_recorded_at_slightly_ahead_of_server_clock() -> None:
    recorded_at = datetime.now(UTC) + timedelta(minutes=1)
    request = CheckInCreateRequest(**_payload(recorded_at=recorded_at))
    assert request.recorded_at == recorded_at


def test_rejects_naive_recorded_at() -> None:
    with pytest.raises(ValidationError):
        CheckInCreateRequest(**_payload(recorded_at=datetime(2026, 6, 18, 8, 30)))


def test_rejects_future_recorded_at() -> None:
    with pytest.raises(ValidationError):
        CheckInCreateRequest(**_payload(recorded_at=datetime.now(UTC) + timedelta(hours=1)))
