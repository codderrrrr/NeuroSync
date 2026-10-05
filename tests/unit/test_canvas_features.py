"""Unit tests for canvas (tracing) feature extraction."""

from neurosync.modules.monitoring.canvas_features import (
    CanvasPoint,
    extract_canvas_features,
)


def _stroke(points: list[tuple[int, float, float]]) -> list[CanvasPoint]:
    return [CanvasPoint(offset_ms=offset, x=x, y=y) for offset, x, y in points]


def _straight_line(offset_ms: int = 0, points: int = 11, step_ms: int = 100) -> list[CanvasPoint]:
    """``points`` samples walking 10 px right every ``step_ms``."""
    return _stroke([(offset_ms + i * step_ms, i * 10.0, 0.0) for i in range(points)])


def test_an_empty_recording_reports_nothing() -> None:
    features = extract_canvas_features([])

    assert features.total_points == 0
    assert features.stroke_count == 0
    assert features.duration_ms == 0
    assert features.mean_speed_px_per_second == 0.0
    # Nothing was drawn, so nothing is inefficient either.
    assert features.path_efficiency == 1.0


def test_a_straight_line_is_fully_efficient() -> None:
    features = extract_canvas_features([_straight_line()])

    assert features.stroke_count == 1
    assert features.total_points == 11
    assert features.path_length == 100.0
    assert features.duration_ms == 1000
    assert features.path_efficiency == 1.0


def test_path_efficiency_grows_as_a_trace_wanders() -> None:
    straight = extract_canvas_features([_straight_line(points=3)])
    # Same endpoints, same duration, but a detour out and back.
    wandering = extract_canvas_features(
        [_stroke([(0, 0.0, 0.0), (100, 100.0, 100.0), (200, 200.0, 0.0)])]
    )

    assert wandering.path_length > straight.path_length
    assert wandering.path_efficiency > straight.path_efficiency


def test_a_closed_shape_that_returns_to_its_start_is_not_a_division_by_zero() -> None:
    features = extract_canvas_features(
        [_stroke([(0, 0.0, 0.0), (100, 50.0, 0.0), (200, 0.0, 0.0)])]
    )

    assert features.path_length == 100.0
    assert features.path_efficiency == 1.0


def test_every_completed_stroke_counts() -> None:
    features = extract_canvas_features([_straight_line(), _straight_line(offset_ms=5_000)])

    assert features.stroke_count == 2
    assert features.total_points == 22
    # Duration spans the whole recording, from the first sample of the first
    # pass to the last sample of the last one.
    assert features.duration_ms == 6_000
    assert features.path_length == 200.0


def test_a_stroke_where_the_finger_never_moved_is_not_a_completed_pass() -> None:
    # "Draw the line three times" is not satisfied by pressing the screen three
    # times in one place.
    features = extract_canvas_features([_stroke([(0, 5.0, 5.0), (50, 5.0, 5.0), (100, 5.0, 5.0)])])

    assert features.total_points == 3
    assert features.stroke_count == 0
    assert features.path_length == 0.0


def test_a_single_sampled_point_cannot_be_a_stroke() -> None:
    features = extract_canvas_features([_stroke([(0, 5.0, 5.0)])])

    assert features.stroke_count == 0


def test_speeds_are_derived_from_distance_over_time() -> None:
    # 10 px every 100 ms is 100 px/second.
    features = extract_canvas_features([_straight_line()])

    assert features.mean_speed_px_per_second == 100.0
    assert features.peak_speed_px_per_second == 100.0


def test_a_stationary_tail_does_not_drag_the_mean_speed_down() -> None:
    moving_then_still = extract_canvas_features(
        [_stroke([(0, 0.0, 0.0), (100, 50.0, 0.0), (200, 50.0, 0.0)])]
    )

    # The second segment has no distance, so it carries no speed; averaging it
    # in as zero would report a patient who drew well as barely moving.
    assert moving_then_still.mean_speed_px_per_second == 500.0
    assert moving_then_still.peak_speed_px_per_second == 500.0


def test_the_longest_pause_is_measured_with_the_finger_down() -> None:
    features = extract_canvas_features(
        [_stroke([(0, 0.0, 0.0), (100, 10.0, 0.0), (9_000, 20.0, 0.0)])]
    )

    assert features.longest_pause_ms == 8_900


def test_offsets_out_of_order_are_sorted_defensively() -> None:
    features = extract_canvas_features(
        [_stroke([(200, 20.0, 0.0), (0, 0.0, 0.0), (100, 10.0, 0.0)])]
    )

    assert features.duration_ms == 200
    assert features.path_length == 20.0


def test_extraction_is_deterministic() -> None:
    strokes = [_straight_line(), _straight_line(offset_ms=6_000)]

    assert extract_canvas_features(strokes) == extract_canvas_features(strokes)
