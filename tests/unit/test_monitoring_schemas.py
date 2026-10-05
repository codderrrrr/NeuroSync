"""Unit tests for monitoring API schema validation."""

import pytest
from pydantic import ValidationError

from neurosync.modules.monitoring.schemas import (
    MAX_SESSION_EVENTS,
    CompleteSessionRequest,
    StrokeOrderMessage,
    TapEventRequest,
    canvas_strokes,
    event_offsets_ms,
)


def _event(offset_ms: int, event_type: str = "tap") -> TapEventRequest:
    return TapEventRequest(event_type=event_type, offset_ms=offset_ms)


def _point(offset_ms: int, event_type: str, x: float = 10.0, y: float = 20.0) -> TapEventRequest:
    return TapEventRequest(
        event_type=event_type,
        offset_ms=offset_ms,
        payload={"x": x, "y": y},
    )


def test_offsets_reduce_to_tap_offsets_in_order() -> None:
    events = [_event(0), _event(250), _event(500)]

    assert event_offsets_ms(events) == [0, 250, 500]


def test_non_tap_event_types_are_rejected() -> None:
    with pytest.raises(ValueError, match="Unsupported event type"):
        event_offsets_ms([_event(0, event_type="hold")])


def test_canvas_events_are_not_taps() -> None:
    # The two runners own disjoint event types, so a canvas stream can never be
    # silently reduced to tap offsets.
    with pytest.raises(ValueError, match="Unsupported event type"):
        event_offsets_ms([_point(0, "stroke_start")])


def test_negative_offsets_are_rejected() -> None:
    with pytest.raises(ValidationError):
        TapEventRequest(event_type="tap", offset_ms=-1)


def test_empty_event_stream_is_accepted() -> None:
    request = CompleteSessionRequest(events=[])

    assert event_offsets_ms(request.events) == []


def test_event_stream_beyond_the_cap_is_rejected() -> None:
    with pytest.raises(ValidationError):
        CompleteSessionRequest(events=[_event(i) for i in range(MAX_SESSION_EVENTS + 1)])


def test_unknown_fields_are_ignored_like_the_rest_of_the_api() -> None:
    event = TapEventRequest.model_validate(
        {"event_type": "tap", "offset_ms": 10, "extra": "ignored"}
    )

    assert event.offset_ms == 10


# ------------------------------------------------------------ canvas events


def test_canvas_stream_groups_into_strokes() -> None:
    strokes = canvas_strokes(
        [
            _point(0, "stroke_start", x=0, y=0),
            _point(10, "stroke_point", x=5, y=0),
            _point(20, "stroke_end", x=10, y=0),
            _point(30, "stroke_start", x=0, y=0),
            _point(40, "stroke_end", x=10, y=0),
        ]
    )

    assert len(strokes) == 2
    assert [point.x for point in strokes[0]] == [0.0, 5.0, 10.0]
    assert [point.offset_ms for point in strokes[1]] == [30, 40]


def test_empty_canvas_stream_has_no_strokes() -> None:
    assert canvas_strokes([]) == []


@pytest.mark.parametrize(
    ("events", "message"),
    [
        (
            [_point(0, "stroke_point")],
            StrokeOrderMessage.POINT_OUTSIDE_STROKE,
        ),
        (
            [_point(0, "stroke_start"), _point(10, "stroke_start")],
            StrokeOrderMessage.START_INSIDE_STROKE,
        ),
        (
            [_point(0, "stroke_end")],
            StrokeOrderMessage.END_OUTSIDE_STROKE,
        ),
        (
            [_point(0, "stroke_start")],
            StrokeOrderMessage.UNCLOSED_STROKE,
        ),
    ],
)
def test_malformed_canvas_streams_are_rejected(
    events: list[TapEventRequest],
    message: str,
) -> None:
    # A stream that does not nest is rejected rather than repaired: guessing
    # where one movement ended would change the stroke count quality depends on.
    with pytest.raises(ValueError, match=message):
        canvas_strokes(events)


def test_canvas_event_without_coordinates_is_rejected() -> None:
    event = TapEventRequest(event_type="stroke_start", offset_ms=0, payload={"x": 1})

    with pytest.raises(ValueError, match="numeric 'x' and 'y'"):
        canvas_strokes([event])
