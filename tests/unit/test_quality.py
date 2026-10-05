"""Unit tests for deterministic recording-quality evaluation."""

from neurosync.modules.monitoring.canvas_features import CanvasFeatures
from neurosync.modules.monitoring.features import TapFeatures, extract_tap_features
from neurosync.modules.monitoring.models import RecordingQuality
from neurosync.modules.monitoring.quality import (
    LONG_PAUSE_MS,
    MIN_CANVAS_POINTS,
    MIN_DURATION_FRACTION,
    MIN_TAPS_FOR_RHYTHM,
    evaluate_canvas_quality,
    evaluate_quality,
)

TARGET_MS = 30_000


def _features(
    total_taps: int = 60,
    duration_ms: int = TARGET_MS,
    longest_pause_ms: int = 400,
) -> TapFeatures:
    return TapFeatures(
        total_taps=total_taps,
        duration_ms=duration_ms,
        mean_inter_tap_interval_ms=300,
        inter_tap_variability_ms=60,
        longest_pause_ms=longest_pause_ms,
        taps_per_second=2.0,
    )


def test_a_steady_full_recording_is_valid() -> None:
    assert evaluate_quality(features=_features(), target_duration_ms=TARGET_MS) is (
        RecordingQuality.VALID
    )


def test_fewer_than_two_taps_is_incomplete() -> None:
    for taps in (0, 1):
        features = _features(total_taps=taps, duration_ms=TARGET_MS)
        assert evaluate_quality(features=features, target_duration_ms=TARGET_MS) is (
            RecordingQuality.INCOMPLETE
        )


def test_recording_under_half_the_target_is_incomplete() -> None:
    features = _features(
        duration_ms=int(TARGET_MS * MIN_DURATION_FRACTION) - 1,
        longest_pause_ms=200,
    )
    assert evaluate_quality(features=features, target_duration_ms=TARGET_MS) is (
        RecordingQuality.INCOMPLETE
    )


def test_recording_past_twice_the_target_is_invalid() -> None:
    features = _features(duration_ms=TARGET_MS * 2 + 1)
    assert evaluate_quality(features=features, target_duration_ms=TARGET_MS) is (
        RecordingQuality.INVALID
    )


def test_few_taps_but_long_enough_is_borderline() -> None:
    features = _features(total_taps=MIN_TAPS_FOR_RHYTHM - 1)
    assert evaluate_quality(features=features, target_duration_ms=TARGET_MS) is (
        RecordingQuality.BORDERLINE
    )


def test_a_very_long_pause_is_borderline() -> None:
    features = _features(longest_pause_ms=LONG_PAUSE_MS + 1)
    assert evaluate_quality(features=features, target_duration_ms=TARGET_MS) is (
        RecordingQuality.BORDERLINE
    )


def test_completeness_is_valued_over_rhythm_rules() -> None:
    # One tap in a short recording is incomplete even though it also breaks the
    # rhythm rules; completeness is decided first.
    features = _features(total_taps=1, duration_ms=1_000)
    assert evaluate_quality(features=features, target_duration_ms=TARGET_MS) is (
        RecordingQuality.INCOMPLETE
    )


def test_evaluation_is_deterministic() -> None:
    offsets = [i * 300 for i in range(100)]
    first = evaluate_quality(features=extract_tap_features(offsets), target_duration_ms=TARGET_MS)
    second = evaluate_quality(features=extract_tap_features(offsets), target_duration_ms=TARGET_MS)
    assert first is second


# -------------------------------------------------------- canvas recordings


def _canvas_features(
    total_points: int = 60,
    stroke_count: int = 1,
    duration_ms: int = TARGET_MS,
    longest_pause_ms: int = 200,
) -> CanvasFeatures:
    return CanvasFeatures(
        total_points=total_points,
        stroke_count=stroke_count,
        duration_ms=duration_ms,
        longest_pause_ms=longest_pause_ms,
        path_length=400.0,
        mean_speed_px_per_second=120.0,
        peak_speed_px_per_second=200.0,
        path_efficiency=1.4,
    )


def test_a_complete_canvas_recording_is_valid() -> None:
    assert (
        evaluate_canvas_quality(
            features=_canvas_features(),
            target_duration_ms=TARGET_MS,
            required_strokes=1,
        )
        is RecordingQuality.VALID
    )


def test_too_few_canvas_points_is_incomplete() -> None:
    features = _canvas_features(total_points=MIN_CANVAS_POINTS - 1)

    assert (
        evaluate_canvas_quality(
            features=features,
            target_duration_ms=TARGET_MS,
            required_strokes=1,
        )
        is RecordingQuality.INCOMPLETE
    )


def test_canvas_duration_bounds_match_the_tap_ones() -> None:
    # A patient is held to the same length rule whichever runner they used.
    short = _canvas_features(duration_ms=int(TARGET_MS * MIN_DURATION_FRACTION) - 1)
    long = _canvas_features(duration_ms=TARGET_MS * 2 + 1)

    assert (
        evaluate_canvas_quality(
            features=short,
            target_duration_ms=TARGET_MS,
            required_strokes=1,
        )
        is RecordingQuality.INCOMPLETE
    )
    assert (
        evaluate_canvas_quality(
            features=long,
            target_duration_ms=TARGET_MS,
            required_strokes=1,
        )
        is RecordingQuality.INVALID
    )


def test_missing_repetitions_is_incomplete() -> None:
    # "Draw the line three times" is only satisfied by three strokes, however
    # long the recording ran.
    features = _canvas_features(stroke_count=2, duration_ms=TARGET_MS * 2 - 1)

    assert (
        evaluate_canvas_quality(
            features=features,
            target_duration_ms=TARGET_MS,
            required_strokes=3,
        )
        is RecordingQuality.INCOMPLETE
    )


def test_a_canvas_recording_that_overran_its_target_is_invalid_even_when_complete() -> None:
    features = _canvas_features(stroke_count=5, duration_ms=TARGET_MS * 2 + 1)

    assert (
        evaluate_canvas_quality(
            features=features,
            target_duration_ms=TARGET_MS,
            required_strokes=3,
        )
        is RecordingQuality.INVALID
    )


def test_a_long_canvas_pause_is_borderline() -> None:
    features = _canvas_features(longest_pause_ms=LONG_PAUSE_MS + 1)

    assert (
        evaluate_canvas_quality(
            features=features,
            target_duration_ms=TARGET_MS,
            required_strokes=1,
        )
        is RecordingQuality.BORDERLINE
    )
