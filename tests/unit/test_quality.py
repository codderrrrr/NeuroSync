"""Unit tests for deterministic recording-quality evaluation."""

from neurosync.modules.monitoring.features import TapFeatures, extract_tap_features
from neurosync.modules.monitoring.models import RecordingQuality
from neurosync.modules.monitoring.quality import (
    LONG_PAUSE_MS,
    MIN_DURATION_FRACTION,
    MIN_TAPS_FOR_RHYTHM,
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
