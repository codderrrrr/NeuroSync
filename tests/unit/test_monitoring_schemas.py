"""Unit tests for monitoring API schema validation."""

import pytest
from pydantic import ValidationError

from neurosync.modules.monitoring.schemas import (
    MAX_TAP_EVENTS,
    CompleteSessionRequest,
    TapEventRequest,
    event_offsets_ms,
)


def _event(offset_ms: int, event_type: str = "tap") -> TapEventRequest:
    return TapEventRequest(event_type=event_type, offset_ms=offset_ms)


def test_offsets_reduce_to_tap_offsets_in_order() -> None:
    events = [_event(0), _event(250), _event(500)]

    assert event_offsets_ms(events) == [0, 250, 500]


def test_non_tap_event_types_are_rejected() -> None:
    with pytest.raises(ValueError, match="Unsupported event type"):
        event_offsets_ms([_event(0, event_type="hold")])


def test_negative_offsets_are_rejected() -> None:
    with pytest.raises(ValidationError):
        TapEventRequest(event_type="tap", offset_ms=-1)


def test_empty_event_stream_is_accepted() -> None:
    request = CompleteSessionRequest(events=[])

    assert event_offsets_ms(request.events) == []


def test_event_stream_beyond_the_cap_is_rejected() -> None:
    with pytest.raises(ValidationError):
        CompleteSessionRequest(events=[_event(i) for i in range(MAX_TAP_EVENTS + 1)])


def test_unknown_fields_are_ignored_like_the_rest_of_the_api() -> None:
    event = TapEventRequest.model_validate(
        {"event_type": "tap", "offset_ms": 10, "extra": "ignored"}
    )

    assert event.offset_ms == 10
