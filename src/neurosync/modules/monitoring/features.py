"""Deterministic feature extraction from raw tap events.

The extractor is a pure function over tap offsets: no randomness, no clock, no
database. Every statistic describes the recording, never the patient.
"""

import statistics
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class TapFeatures:
    """Descriptive statistics of one tap recording."""

    total_taps: int
    duration_ms: int
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int
    taps_per_second: float


def extract_tap_features(tap_offsets_ms: list[int]) -> TapFeatures:
    """Summarise a tap recording from tap offsets in milliseconds.

    Offsets must be non-negative; unsorted input is treated as the client
    reported it and sorted defensively before computing intervals.
    """
    offsets = sorted(tap_offsets_ms)
    if not offsets:
        return TapFeatures(
            total_taps=0,
            duration_ms=0,
            mean_inter_tap_interval_ms=0,
            inter_tap_variability_ms=0,
            longest_pause_ms=0,
            taps_per_second=0.0,
        )

    # strict=False is the point: the last offset has no successor, which is
    # exactly the interval list we want.
    intervals = [b - a for a, b in zip(offsets, offsets[1:], strict=False)]
    duration_ms = offsets[-1]
    # A recording with one tap has a duration but no interval to summarise.
    if not intervals:
        return TapFeatures(
            total_taps=1,
            duration_ms=duration_ms,
            mean_inter_tap_interval_ms=0,
            inter_tap_variability_ms=0,
            longest_pause_ms=0,
            taps_per_second=round(duration_ms / 1000, 3),
        )

    return TapFeatures(
        total_taps=len(offsets),
        duration_ms=duration_ms,
        mean_inter_tap_interval_ms=round(statistics.fmean(intervals)),
        inter_tap_variability_ms=round(statistics.pstdev(intervals)),
        longest_pause_ms=max(intervals),
        taps_per_second=round(len(offsets) / (duration_ms / 1000), 3),
    )
