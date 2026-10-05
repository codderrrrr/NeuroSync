"""Deterministic feature extraction from raw canvas (tracing) events.

A canvas recording is a sequence of strokes, each a run of sampled points with
a millisecond offset. The extractor is a pure function over those points: no
randomness, no clock, no database. Every statistic describes the recording,
never the patient.

Coordinates are whatever the client reported, in a single consistent unit for
one recording (the patient app reports logical pixels). Path length and speed
are therefore expressed in that same unit, which is what makes them comparable
across a patient's own sessions on their own device.
"""

import math
import statistics
from collections.abc import Sequence
from dataclasses import dataclass

# A stroke the patient started and immediately lifted is a dot, not a
# completed shape, so it does not count towards the movements a task asked for.
POINTS_FOR_A_COMPLETED_STROKE = 2


@dataclass(frozen=True, slots=True)
class CanvasPoint:
    """One sampled point of a stroke."""

    offset_ms: int
    x: float
    y: float


@dataclass(frozen=True, slots=True)
class CanvasFeatures:
    """Descriptive statistics of one canvas recording."""

    total_points: int
    # Strokes with at least two points. A stroke the patient started and
    # immediately lifted is a dot, not a completed shape, so it is not
    # counted: this is what "did they do all the repetitions?" is judged on.
    stroke_count: int
    duration_ms: int
    longest_pause_ms: int
    path_length: float
    mean_speed_px_per_second: float
    peak_speed_px_per_second: float
    # Total distance travelled divided by the total distance the strokes
    # actually got the finger across the canvas. 1.0 is a straight, direct
    # path; larger means the finger travelled further to get there.
    path_efficiency: float


def _empty_features() -> CanvasFeatures:
    return CanvasFeatures(
        total_points=0,
        stroke_count=0,
        duration_ms=0,
        longest_pause_ms=0,
        path_length=0.0,
        mean_speed_px_per_second=0.0,
        peak_speed_px_per_second=0.0,
        path_efficiency=1.0,
    )


def _distance(a: CanvasPoint, b: CanvasPoint) -> float:
    return math.hypot(b.x - a.x, b.y - a.y)


def _stroke_length(stroke: Sequence[CanvasPoint]) -> float:
    """How far the finger actually travelled along one stroke."""
    return sum(
        _distance(previous, current) for previous, current in zip(stroke, stroke[1:], strict=False)
    )


def extract_canvas_features(
    strokes: Sequence[Sequence[CanvasPoint]],
) -> CanvasFeatures:
    """Summarise a canvas recording from its strokes, in capture order.

    Unsorted input is treated as the client reported it and sorted by offset
    defensively before any interval is computed, so an out-of-order sample
    cannot produce a negative duration or speed.
    """
    points = [
        point
        for stroke in strokes
        for point in sorted(stroke, key=lambda recorded: recorded.offset_ms)
    ]
    if not points:
        return _empty_features()

    completed_strokes = [
        sorted(stroke, key=lambda recorded: recorded.offset_ms)
        for stroke in strokes
        if len(stroke) >= POINTS_FOR_A_COMPLETED_STROKE and _stroke_length(stroke) > 0
    ]

    path_length = 0.0
    travelled = 0.0
    longest_pause_ms = 0
    speeds: list[float] = []

    for stroke in completed_strokes:
        for previous, current in zip(stroke, stroke[1:], strict=False):
            distance = _distance(previous, current)
            path_length += distance
            elapsed_ms = current.offset_ms - previous.offset_ms
            longest_pause_ms = max(longest_pause_ms, elapsed_ms)
            # A zero-length step carries no timing information, and a step
            # with no elapsed time has no meaningful speed.
            if elapsed_ms > 0 and distance > 0:
                speeds.append(distance / elapsed_ms * 1000)
        travelled += _distance(stroke[0], stroke[-1])

    # A stroke that returns to where it started (a closed spiral) covers
    # real distance but no net displacement; without this the ratio would be
    # a division by zero rather than an honest "no direct path".
    path_efficiency = 1.0 if travelled <= 0 else round(path_length / travelled, 3)

    return CanvasFeatures(
        total_points=len(points),
        stroke_count=len(completed_strokes),
        duration_ms=points[-1].offset_ms,
        longest_pause_ms=longest_pause_ms,
        path_length=round(path_length, 1),
        mean_speed_px_per_second=(round(statistics.fmean(speeds), 1) if speeds else 0.0),
        peak_speed_px_per_second=round(max(speeds), 1) if speeds else 0.0,
        path_efficiency=path_efficiency,
    )
