"""Unit tests for deterministic tap feature extraction."""

import pytest

from neurosync.modules.monitoring.features import extract_tap_features


def test_empty_recording_yields_zeroes() -> None:
    features = extract_tap_features([])

    assert features.total_taps == 0
    assert features.duration_ms == 0
    assert features.mean_inter_tap_interval_ms == 0
    assert features.inter_tap_variability_ms == 0
    assert features.longest_pause_ms == 0
    assert features.taps_per_second == 0.0


def test_single_tap_has_no_intervals() -> None:
    features = extract_tap_features([1500])

    assert features.total_taps == 1
    assert features.duration_ms == 1500
    assert features.mean_inter_tap_interval_ms == 0
    assert features.longest_pause_ms == 0


def test_known_series_produce_exact_statistics() -> None:
    # Intervals: 100, 200, 300 -> mean 200, pstdev sqrt(6666.66) ~ 81.65 -> 82.
    features = extract_tap_features([0, 100, 300, 600])

    assert features.total_taps == 4
    assert features.duration_ms == 600
    assert features.mean_inter_tap_interval_ms == 200
    assert features.inter_tap_variability_ms == 82
    assert features.longest_pause_ms == 300
    assert features.taps_per_second == pytest.approx(6.667, abs=0.001)


def test_offsets_are_sorted_defensively() -> None:
    features = extract_tap_features([600, 0, 300, 100])

    assert features.total_taps == 4
    assert features.duration_ms == 600
    assert features.longest_pause_ms == 300


def test_identical_intervals_have_zero_variability() -> None:
    features = extract_tap_features([0, 250, 500, 750, 1000])

    assert features.total_taps == 5
    assert features.mean_inter_tap_interval_ms == 250
    assert features.inter_tap_variability_ms == 0
    assert features.longest_pause_ms == 250
    # 5 taps over the 1-second span between the first and last tap.
    assert features.taps_per_second == pytest.approx(5.0)
