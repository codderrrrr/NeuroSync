"""Deterministic recording-quality evaluation.

Quality is a statement about the recording only: too few taps, too short, too
long, or irregular. It never carries clinical meaning and must never be shown
to patients or doctors as one.
"""

from dataclasses import dataclass

from neurosync.modules.monitoring.canvas_features import CanvasFeatures
from neurosync.modules.monitoring.features import TapFeatures
from neurosync.modules.monitoring.models import RecordingQuality


@dataclass(frozen=True, slots=True)
class QualityRule:
    """One human-readable quality threshold, kept next to its code."""

    code: str
    explanation: str


MIN_TAPS_FOR_RHYTHM = 10
MIN_TAPS_FOR_INTERVAL = 2
MIN_DURATION_FRACTION = 0.5
MAX_DURATION_FRACTION = 2.0
LONG_PAUSE_MS = 5_000

# Ordered rules; the first failing rule decides the quality state.
RULES: tuple[QualityRule, ...] = (
    QualityRule(
        code="too_few_taps",
        explanation=f"Fewer than {MIN_TAPS_FOR_RHYTHM} taps were recorded.",
    ),
    QualityRule(
        code="too_short",
        explanation=(
            f"The recording is shorter than {MIN_DURATION_FRACTION:.0%} of the "
            "expected task duration."
        ),
    ),
    QualityRule(
        code="too_long",
        explanation=(
            f"The recording runs past {MAX_DURATION_FRACTION:.0%} of the "
            "expected task duration, which suggests the task was left running."
        ),
    ),
    QualityRule(
        code="long_pause",
        explanation=(
            f"A pause longer than {LONG_PAUSE_MS / 1000:.0f} seconds interrupts the tapping rhythm."
        ),
    ),
)


def evaluate_quality(
    *,
    features: TapFeatures,
    target_duration_ms: int,
) -> RecordingQuality:
    """Return the deterministic quality state for one tap recording.

    The thresholds are deliberately simple and explainable for this milestone:
    an honest recording that ended early is ``incomplete``, one that kept
    running is ``invalid``, and an irregular or short-but-plausible one is
    ``borderline``. Everything else is ``valid``.
    """
    if features.total_taps < MIN_TAPS_FOR_INTERVAL:
        return RecordingQuality.INCOMPLETE
    if features.duration_ms < target_duration_ms * MIN_DURATION_FRACTION:
        return RecordingQuality.INCOMPLETE
    if features.duration_ms > target_duration_ms * MAX_DURATION_FRACTION:
        return RecordingQuality.INVALID
    if features.total_taps < MIN_TAPS_FOR_RHYTHM:
        return RecordingQuality.BORDERLINE
    if features.longest_pause_ms > LONG_PAUSE_MS:
        return RecordingQuality.BORDERLINE
    return RecordingQuality.VALID


# ------------------------------------------------------- canvas recordings
#
# A tracing recording has no taps to count, so it is judged on whether enough
# of the shape was captured and whether every repetition the doctor asked for
# was actually drawn.

# Below this a "recording" is a smudge rather than a trace, whatever the
# duration says.
MIN_CANVAS_POINTS = 12

CANVAS_RULES: tuple[QualityRule, ...] = (
    QualityRule(
        code="too_few_points",
        explanation=f"Fewer than {MIN_CANVAS_POINTS} points were recorded.",
    ),
    QualityRule(
        code="too_short",
        explanation=(
            f"The recording is shorter than {MIN_DURATION_FRACTION:.0%} of the "
            "expected task duration."
        ),
    ),
    QualityRule(
        code="too_long",
        explanation=(
            f"The recording runs past {MAX_DURATION_FRACTION:.0%} of the "
            "expected task duration, which suggests the task was left running."
        ),
    ),
    QualityRule(
        code="too_few_strokes",
        explanation="Fewer separate movements were recorded than the test asked for.",
    ),
    QualityRule(
        code="long_pause",
        explanation=(
            f"The finger stayed down for more than {LONG_PAUSE_MS / 1000:.0f} seconds at a stretch."
        ),
    ),
)


def evaluate_canvas_quality(
    *,
    features: CanvasFeatures,
    target_duration_ms: int,
    required_strokes: int,
) -> RecordingQuality:
    """Return the deterministic quality state for one canvas recording.

    The duration bounds and meanings are the same as for a tap recording, so a
    patient is held to the same rule either way; what differs is that a canvas
    recording is judged on the number of movements completed, because "draw the
    line three times" is only satisfied by three strokes.
    """
    if features.total_points < MIN_CANVAS_POINTS:
        return RecordingQuality.INCOMPLETE
    if features.duration_ms < target_duration_ms * MIN_DURATION_FRACTION:
        return RecordingQuality.INCOMPLETE
    if features.duration_ms > target_duration_ms * MAX_DURATION_FRACTION:
        return RecordingQuality.INVALID
    if features.stroke_count < required_strokes:
        return RecordingQuality.INCOMPLETE
    if features.longest_pause_ms > LONG_PAUSE_MS:
        return RecordingQuality.BORDERLINE
    return RecordingQuality.VALID
