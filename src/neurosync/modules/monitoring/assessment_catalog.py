"""The NeuroSync assessment catalog: what tests exist and how they run.

The catalog is the single source of truth for the assessments NeuroSync owns.
A definition describes a test and its ``execution_type``; an assessment is only
executable when NeuroSync has a runner for it, which ``is_supported`` records.
Assessments that exist in the catalog without a runner are visible but must
never be assigned or published as patient tasks ("Not available yet").

Assessment content here is NeuroSync-owned and written for this application.
Established Parkinson's motor-assessment literature informed only the choice of
tasks, never any wording, scoring, or copyrighted content.
"""

from dataclasses import dataclass
from enum import StrEnum


class ExecutionType(StrEnum):
    """How an assessment is executed by a client runner."""

    TAP_TASK = "tap_task"
    CANVAS_TASK = "canvas_task"
    QUESTIONNAIRE = "questionnaire"


@dataclass(frozen=True, slots=True)
class AssessmentSpec:
    """A catalog entry describing one NeuroSync assessment."""

    slug: str
    title: str
    description: str
    instructions: str
    execution_type: ExecutionType
    default_duration_seconds: int
    is_supported: bool


# Only assessments with a matching client runner are ``is_supported``. Adding a
# catalog entry without a runner must keep that flag ``False`` so plans cannot
# publish it.
ASSESSMENT_CATALOG: tuple[AssessmentSpec, ...] = (
    AssessmentSpec(
        slug="finger_tapping",
        title="Finger Tapping",
        description=(
            "Tap as regularly as you can for a short period so the app can "
            "record your tapping rhythm."
        ),
        instructions=(
            "Sit comfortably and rest your hand on a table. When the test "
            "starts, tap the pad with the finger indicated on screen, at a "
            "steady pace that feels natural. Keep tapping until the test "
            "finishes on its own."
        ),
        execution_type=ExecutionType.TAP_TASK,
        default_duration_seconds=30,
        is_supported=True,
    ),
    AssessmentSpec(
        slug="spiral_drawing",
        title="Spiral Drawing",
        description=(
            "Trace a spiral shape on the screen so the app can record your drawing movement."
        ),
        instructions=(
            "Use your fingertip to trace the spiral shown on screen, from the "
            "centre outwards, without lifting your finger. This test is not "
            "available yet."
        ),
        execution_type=ExecutionType.CANVAS_TASK,
        default_duration_seconds=30,
        is_supported=False,
    ),
    AssessmentSpec(
        slug="line_tracing",
        title="Line Tracing",
        description=(
            "Follow a line between two points so the app can record your tracing movement."
        ),
        instructions=(
            "Use your fingertip to trace the path between the two markers, "
            "staying on the line. This test is not available yet."
        ),
        execution_type=ExecutionType.CANVAS_TASK,
        default_duration_seconds=30,
        is_supported=False,
    ),
    AssessmentSpec(
        slug="handwriting",
        title="Handwriting",
        description=(
            "Write a short phrase on the screen so the app can record your writing movement."
        ),
        instructions=(
            "Write the phrase shown on screen with your fingertip, at your "
            "normal writing speed. This test is not available yet."
        ),
        execution_type=ExecutionType.CANVAS_TASK,
        default_duration_seconds=30,
        is_supported=False,
    ),
)

SUPPORTED_ASSESSMENT_SLUGS: frozenset[str] = frozenset(
    spec.slug for spec in ASSESSMENT_CATALOG if spec.is_supported
)
