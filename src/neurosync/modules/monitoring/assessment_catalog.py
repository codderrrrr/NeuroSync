"""The NeuroSync assessment catalog: what tests exist, how they run, and what
a doctor may change about them.

The catalog is the single source of truth for the assessments NeuroSync owns.
A definition describes a test and its ``execution_type``; ``is_supported``
records whether a doctor may hand it to a patient today. It is ``False`` for two
different reasons: NeuroSync has no runner for the test yet, or the test is
being held back deliberately. Either way the entry stays visible but must never
be assigned or published as a patient task ("Coming soon").

Each definition also declares ``parameters``: the values a doctor sets when
they hand a test to a patient, such as how long the recording runs and how fast
the patient should move. The specs here are the only place those keys, bounds,
and defaults exist. The API validates a doctor's values against them, the
doctor app renders an editor from them, and the patient app renders the
resulting test settings - so the three can never disagree about what a
parameter means.

Assessment content here is NeuroSync-owned and written for this application.
Established Parkinson's motor-assessment literature informed only the choice of
tasks, never any wording, scoring, or copyrighted content.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum


class ExecutionType(StrEnum):
    """How an assessment is executed by a client runner."""

    TAP_TASK = "tap_task"
    CANVAS_TASK = "canvas_task"
    QUESTIONNAIRE = "questionnaire"


class ParameterKind(StrEnum):
    """How one doctor-settable value is entered and validated."""

    INTEGER = "integer"
    CHOICE = "choice"
    TEXT = "text"


@dataclass(frozen=True, slots=True)
class ParameterSpec:
    """One value a doctor can set when assigning a test to a patient.

    ``minimum``/``maximum`` bound an integer parameter; ``choices`` enumerates
    the values of a choice parameter; ``max_length`` bounds a text parameter.
    Exactly the fields the matching ``kind`` needs are set, and validation
    below rejects anything that does not fit.
    """

    key: str
    label: str
    kind: ParameterKind
    default: int | str
    minimum: int | None = None
    maximum: int | None = None
    choices: tuple[str, ...] = ()
    max_length: int | None = None
    help_text: str = ""


class ParameterValidationError(ValueError):
    """Raised when a doctor's parameter value does not match its spec."""


class UnknownParameterMessage:
    """Message for a parameter the assessment does not declare."""

    @staticmethod
    def for_keys(slug: str, keys: list[str]) -> str:
        return f"{slug} has no setting(s): {', '.join(sorted(keys))}"


class ParameterOutOfRangeMessage:
    """Message for a value outside the bounds its spec declares."""

    @staticmethod
    def for_key(key: str, minimum: int, maximum: int) -> str:
        return f"'{key}' must be between {minimum} and {maximum}."


class ParameterNotAChoiceMessage:
    """Message for a value outside a choice parameter's options."""

    @staticmethod
    def for_key(key: str, choices: tuple[str, ...]) -> str:
        return f"'{key}' must be one of: {', '.join(choices)}."


class ParameterTextTooLongMessage:
    """Message for text longer than its spec allows."""

    @staticmethod
    def for_key(key: str, max_length: int) -> str:
        return f"'{key}' must be at most {max_length} characters."


class ParameterTextBlankMessage:
    """Message for text a doctor submitted with no content."""

    @staticmethod
    def for_key(key: str) -> str:
        return f"'{key}' cannot be blank."


class ParameterWrongTypeMessage:
    """Message for a value of the wrong kind for its parameter."""

    @staticmethod
    def for_key(key: str, expected: str) -> str:
        return f"'{key}' must be {expected}."


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
    # What a doctor may change about this test. Empty means the recording
    # length is the only thing to configure.
    parameters: tuple[ParameterSpec, ...] = ()
    # The parameter whose integer value is how many separate strokes the task
    # asks for, for assessments drawn as discrete strokes. ``None`` means the
    # task is one continuous stroke, which is how a spiral is drawn.
    strokes_parameter: str | None = None


def _pacing() -> ParameterSpec:
    """How fast the patient should move. Shared by every assessment."""
    return ParameterSpec(
        key="pacing",
        label="Speed",
        kind=ParameterKind.CHOICE,
        default="comfortable",
        choices=("slow", "comfortable", "fast"),
        help_text="How quickly the patient should move during the test.",
    )


def _repetitions(label: str, *, default: int, minimum: int, maximum: int) -> ParameterSpec:
    """How many separate passes of the task the patient should perform."""
    return ParameterSpec(
        key="repetitions",
        label=label,
        kind=ParameterKind.INTEGER,
        default=default,
        minimum=minimum,
        maximum=maximum,
        help_text="How many separate times the patient completes the shape.",
    )


# Finger tapping and line tracing are the two tests a doctor can hand out today.
# Spiral drawing and handwriting have runners but are held back: their guides and
# settings are not yet good enough to ask a patient to use, so ``is_supported``
# keeps them out of every plan rather than shipping a poor test. Adding a catalog
# entry without a runner must likewise keep ``is_supported`` ``False``.
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
        parameters=(
            ParameterSpec(
                key="hand",
                label="Hand",
                kind=ParameterKind.CHOICE,
                default="right",
                choices=("left", "right"),
                help_text="Which hand the patient taps with.",
            ),
            ParameterSpec(
                key="finger",
                label="Finger",
                kind=ParameterKind.CHOICE,
                default="index",
                choices=("thumb", "index", "middle", "ring", "little"),
                help_text="Which finger the patient taps with.",
            ),
            _pacing(),
        ),
    ),
    AssessmentSpec(
        slug="spiral_drawing",
        title="Spiral Drawing",
        description=(
            "Trace a spiral shape on the screen so the app can record your drawing movement."
        ),
        instructions=(
            "Use your fingertip to trace the spiral shown on screen, from the "
            "centre outwards, without lifting your finger. Draw it in one "
            "continuous movement at the pace shown before the test starts."
        ),
        execution_type=ExecutionType.CANVAS_TASK,
        default_duration_seconds=30,
        is_supported=False,
        parameters=(
            _pacing(),
            ParameterSpec(
                key="turns",
                label="Turns",
                kind=ParameterKind.INTEGER,
                default=2,
                minimum=1,
                maximum=6,
                help_text="How many full turns of the spiral to trace.",
            ),
            ParameterSpec(
                key="size_percent",
                label="Spiral size",
                kind=ParameterKind.INTEGER,
                default=70,
                minimum=40,
                maximum=100,
                help_text="How large the spiral is on screen, as a percentage.",
            ),
        ),
    ),
    AssessmentSpec(
        slug="line_tracing",
        title="Line Tracing",
        description=(
            "Follow a line between two points so the app can record your tracing movement."
        ),
        instructions=(
            "Use your fingertip to trace the path between the two markers, "
            "staying on the line. Lift your finger at the end of the line and "
            "start again from the same marker."
        ),
        execution_type=ExecutionType.CANVAS_TASK,
        default_duration_seconds=30,
        is_supported=True,
        parameters=(
            _pacing(),
            _repetitions("Repetitions", default=3, minimum=1, maximum=10),
            ParameterSpec(
                key="line_length_percent",
                label="Line length",
                kind=ParameterKind.INTEGER,
                default=70,
                minimum=30,
                maximum=100,
                help_text="How long the line is on screen, as a percentage.",
            ),
        ),
        strokes_parameter="repetitions",
    ),
    AssessmentSpec(
        slug="handwriting",
        title="Handwriting",
        description=(
            "Write a short phrase on the screen so the app can record your writing movement."
        ),
        instructions=(
            "Write the phrase shown on screen with your fingertip, at your "
            "normal writing speed and in your usual handwriting. Lift your "
            "finger between words and between repetitions."
        ),
        execution_type=ExecutionType.CANVAS_TASK,
        default_duration_seconds=30,
        is_supported=False,
        parameters=(
            _pacing(),
            ParameterSpec(
                key="phrase",
                label="Phrase",
                kind=ParameterKind.TEXT,
                default="NeuroSync",
                max_length=60,
                help_text="The words the patient writes on screen.",
            ),
            _repetitions("Repetitions", default=1, minimum=1, maximum=5),
        ),
        strokes_parameter="repetitions",
    ),
)

SUPPORTED_ASSESSMENT_SLUGS: frozenset[str] = frozenset(
    spec.slug for spec in ASSESSMENT_CATALOG if spec.is_supported
)


def get_spec(slug: str) -> AssessmentSpec | None:
    """Return the code catalog entry for ``slug``, or ``None``."""
    for spec in ASSESSMENT_CATALOG:
        if spec.slug == slug:
            return spec
    return None


def default_parameters(spec: AssessmentSpec) -> dict[str, int | str]:
    """Return every parameter of ``spec`` at its catalog default."""
    return {parameter.key: parameter.default for parameter in spec.parameters}


def _coerce(parameter: ParameterSpec, value: object) -> int | str:
    """Validate one value against its spec and return it normalised."""
    if parameter.kind is ParameterKind.INTEGER:
        # ``bool`` is an ``int`` subclass, and ``True`` is not a tap count.
        if not isinstance(value, int) or isinstance(value, bool):
            raise ParameterValidationError(
                ParameterWrongTypeMessage.for_key(parameter.key, "a whole number")
            )
        minimum = parameter.minimum
        maximum = parameter.maximum
        if minimum is None or maximum is None or not minimum <= value <= maximum:
            raise ParameterValidationError(
                ParameterOutOfRangeMessage.for_key(parameter.key, minimum or 0, maximum or 0)
            )
        return value

    if parameter.kind is ParameterKind.CHOICE:
        if not isinstance(value, str) or value not in parameter.choices:
            raise ParameterValidationError(
                ParameterNotAChoiceMessage.for_key(parameter.key, parameter.choices)
            )
        return value

    if not isinstance(value, str):
        raise ParameterValidationError(ParameterWrongTypeMessage.for_key(parameter.key, "text"))
    trimmed = value.strip()
    if not trimmed:
        raise ParameterValidationError(ParameterTextBlankMessage.for_key(parameter.key))
    max_length = parameter.max_length
    if max_length is not None and len(trimmed) > max_length:
        raise ParameterValidationError(
            ParameterTextTooLongMessage.for_key(parameter.key, max_length)
        )
    return trimmed


def validate_parameters(
    spec: AssessmentSpec,
    values: Mapping[str, object] | None,
) -> dict[str, int | str]:
    """Return a complete, validated parameter set for ``spec``.

    Unspecified parameters fall back to their catalog default, so the stored
    value is always a complete set and a client never has to reason about
    which keys happen to be present. Unknown keys are rejected rather than
    dropped: silently discarding a setting the doctor chose would make the
    test they assigned differ from the one they believe they assigned.
    """
    supplied = dict(values or {})
    known = {parameter.key for parameter in spec.parameters}
    unknown = [key for key in supplied if key not in known]
    if unknown:
        raise ParameterValidationError(UnknownParameterMessage.for_keys(spec.slug, unknown))

    return {
        parameter.key: (
            _coerce(parameter, supplied[parameter.key])
            if parameter.key in supplied
            else parameter.default
        )
        for parameter in spec.parameters
    }


def resolve_parameters(
    stored: Mapping[str, object] | None,
    spec: AssessmentSpec,
) -> dict[str, int | str]:
    """Return the parameters a stored plan item actually uses.

    Parameters were validated against ``spec`` when they were written, so a
    stored value is trusted here; anything missing, or of a shape the spec could
    never have accepted, falls back to the catalog default so a row written
    before a parameter existed still yields a complete, usable set.
    """
    values = stored or {}
    resolved: dict[str, int | str] = {}
    for parameter in spec.parameters:
        value = values.get(parameter.key)
        resolved[parameter.key] = (
            value
            if isinstance(value, int | str) and not isinstance(value, bool)
            else parameter.default
        )
    return resolved


def required_strokes(
    spec: AssessmentSpec,
    parameters: Mapping[str, int | str],
) -> int:
    """How many separate strokes ``spec`` asks the patient to draw.

    A single continuous stroke is the floor for every canvas assessment; the
    assessments drawn as discrete strokes multiply it by how many repetitions
    the doctor asked for.
    """
    if spec.strokes_parameter is None:
        return 1
    value = parameters.get(spec.strokes_parameter, 1)
    return value if isinstance(value, int) and value > 0 else 1
