"""API contracts for the monitoring module.

Responses deliberately describe assessments, plans, sessions and recordings;
nothing here is a clinical score and no endpoint interprets the patient.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from neurosync.modules.medication.models import (
    EvidenceStrength,
    MedicationContext,
)
from neurosync.modules.monitoring.assessment_catalog import (
    AssessmentSpec,
    ParameterKind,
    ParameterSpec,
)
from neurosync.modules.monitoring.canvas_features import CanvasPoint
from neurosync.modules.monitoring.models import LongitudinalState, RecordingQuality

# A 30-second task cannot plausibly produce ten thousand taps, and a 60 Hz
# canvas sample rate produces about 1,800 points in the same time; the cap
# keeps a broken client from flooding the events table while never rejecting
# honest recordings.
MAX_SESSION_EVENTS = 6_000
EVENT_TYPE_TAP = "tap"
EVENT_TYPE_STROKE_START = "stroke_start"
EVENT_TYPE_STROKE_POINT = "stroke_point"
EVENT_TYPE_STROKE_END = "stroke_end"

TAP_EVENT_TYPES: frozenset[str] = frozenset({EVENT_TYPE_TAP})
CANVAS_EVENT_TYPES: frozenset[str] = frozenset(
    {EVENT_TYPE_STROKE_START, EVENT_TYPE_STROKE_POINT, EVENT_TYPE_STROKE_END}
)

EVENT_TYPE_DESCRIPTION = (
    "Event type: 'tap' for finger tapping, or 'stroke_start', 'stroke_point' "
    "and 'stroke_end' for a canvas recording."
)


# Error message constants
ERR_UNSUPPORTED_EVENT_TYPE = "Unsupported event type: {type!r}"
ERR_MISSING_CANVAS_COORDS = "Canvas events must carry numeric 'x' and 'y' values."
ERR_STROKE_START_INSIDE = "A stroke started before the previous one ended."
ERR_STROKE_POINT_OUTSIDE = "A stroke point arrived outside a stroke."
ERR_STROKE_END_OUTSIDE = "A stroke ended without being started."
ERR_STROKE_UNCLOSED = "The recording ended while a stroke was still open."


class ParameterSpecResponse(BaseModel):
    """One doctor-settable value, described so a client can edit it."""

    key: str
    label: str
    kind: ParameterKind
    default: int | str
    minimum: int | None = None
    maximum: int | None = None
    choices: list[str] = Field(default_factory=list)
    max_length: int | None = None
    help_text: str = ""
    choice_labels: dict[str, str] = Field(default_factory=dict)
    value_format: str | None = None

    @classmethod
    def from_spec(cls, spec: ParameterSpec) -> "ParameterSpecResponse":
        return cls(
            key=spec.key,
            label=spec.label,
            kind=spec.kind,
            default=spec.default,
            minimum=spec.minimum,
            maximum=spec.maximum,
            choices=list(spec.choices),
            max_length=spec.max_length,
            help_text=spec.help_text,
            choice_labels=spec.choice_labels,
            value_format=spec.value_format,
        )


def parameter_responses(spec: AssessmentSpec) -> list[ParameterSpecResponse]:
    """Render every parameter an assessment lets a doctor set."""
    return [ParameterSpecResponse.from_spec(parameter) for parameter in spec.parameters]


class AssessmentResponse(BaseModel):
    """One catalog entry as the client sees it."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    slug: str
    title: str
    description: str
    instructions: str
    execution_type: str
    default_duration_seconds: int
    is_supported: bool
    # What a doctor may change about this test, and what it defaults to. The
    # patient app renders the values its plan item carries; the doctor app
    # renders an editor from these specs.
    parameters: list[ParameterSpecResponse] = Field(default_factory=list)


class PlanItemResponse(BaseModel):
    """One ordered assessment in the patient's plan."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    assessment: AssessmentResponse
    position: int

    # How many times this item has been completed today (UTC), used by the
    # client to show the next available assessment.
    completed_today: int

    # The recording target this item actually uses: a doctor-assigned override
    # when present, otherwise the assessment's catalog default.
    duration_seconds: int

    # Every parameter this item uses, resolved against the catalog so the
    # client never has to work out which ones the doctor left at their default.
    parameters: dict[str, int | str] = Field(default_factory=dict)


class MonitoringPlanResponse(BaseModel):
    """The patient's active monitoring plan with its ordered items."""

    id: int
    title: str
    status: str
    items: list[PlanItemResponse]


class StartSessionRequest(BaseModel):
    """Request to begin one execution of a plan item."""

    plan_item_id: int = Field(description="The plan item being performed")


class TapEventRequest(BaseModel):
    """One raw movement event as the client recorded it.

    One shape covers both runners. A tap carries no payload; a canvas point
    carries the ``x``/``y`` the client sampled, in whatever unit it renders.
    """

    event_type: str = Field(description=EVENT_TYPE_DESCRIPTION)
    offset_ms: int = Field(ge=0, description="Milliseconds into the session")
    payload: dict | None = Field(default=None, description="Optional raw client metadata")

    def point(self) -> CanvasPoint:
        """Return this event as a sampled canvas point.

        Raises ``ValueError`` when the payload is not a usable coordinate, so a
        client cannot smuggle a malformed point past the boundary.
        """
        payload = self.payload or {}
        try:
            x = float(payload["x"])  # type: ignore[arg-type]
            y = float(payload["y"])  # type: ignore[arg-type]
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(ERR_MISSING_CANVAS_COORDS) from exc
        return CanvasPoint(offset_ms=self.offset_ms, x=x, y=y)


class CompleteSessionRequest(BaseModel):
    """The raw event stream captured during one session."""

    events: list[TapEventRequest] = Field(
        max_length=MAX_SESSION_EVENTS,
        description="Raw events in the order the client captured them",
    )

    # Optional reported dose event to attach as context. Omitted means the
    # patient gave no medication information, and the resulting context stays
    # `unknown`; it is never inferred from their other records.
    medication_event_id: int | None = Field(
        default=None,
        description="A dose event this patient owns, to attach as context",
    )


class TapResultResponse(BaseModel):
    """Deterministic summary of one finger-tapping recording."""

    total_taps: int
    duration_ms: int
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int
    taps_per_second: float


class CanvasResultResponse(BaseModel):
    """Deterministic summary of one canvas (tracing) recording.

    Describes the recording only. Path length and speed are in the client's own
    coordinate unit, which is what makes a patient's sessions comparable with
    each other on their own device and with nothing else.
    """

    total_points: int
    stroke_count: int
    duration_ms: int
    longest_pause_ms: int
    path_length: float
    mean_speed_px_per_second: float
    peak_speed_px_per_second: float
    path_efficiency: float


class SessionResultResponse(BaseModel):
    """Deterministic summary of one recording, in the shape its runner needs.

    Exactly one block is present, so a client reads the one its assessment
    produces instead of guessing from which fields happen to be set.
    """

    quality: RecordingQuality
    taps: TapResultResponse | None = None
    canvas: CanvasResultResponse | None = None


class LongitudinalSummaryResponse(BaseModel):
    """How one session compared with the patient's own history.

    A monitoring state for a specialist to review. It carries no diagnosis,
    severity stage, or treatment meaning, and the supporting counts exist so a
    patient can see how much history the statement rests on.

    The medication fields are *supporting* context for that comparison, never a
    second baseline and never an explanation of why the state is what it is.
    """

    state: LongitudinalState
    # Usable previous sessions considered when this state was reached.
    usable_history_count: int
    # Present once a baseline exists; null while history is still building.
    baseline_observation_count: int | None
    baseline_confidence: str | None
    # Which tracked features were outside their tolerance, for traceability.
    changed_features: list[str]
    # Whether the state rests on a fully usable history.
    is_confident: bool

    # --- medication context -------------------------------------------------
    # `unknown` whenever timing could not be established, including when the
    # patient attached no dose event at all.
    medication_context: MedicationContext = MedicationContext.UNKNOWN
    medication_name: str | None = Field(
        default=None,
        description="The medication the patient attached, exactly as they recorded it",
    )
    # Absolute minutes between the reported dose and this assessment; null when
    # timing is unknown. Never negative: the direction is in the context.
    minutes_since_medication: int | None = None
    # How much supporting information stood behind this reading. A description
    # of how much was recorded, not a probability.
    evidence_strength: EvidenceStrength = EvidenceStrength.INSUFFICIENT
    # Earlier usable sessions recorded under this same medication context.
    comparable_observation_count: int = 0
    # A cautious, factual sentence describing the timing. Never a clinical
    # conclusion about the medication.
    medication_note: str = Field(
        default="Medication timing was not available for this assessment.",
    )


class PatientBaselineResponse(BaseModel):
    """The patient's own finger-tapping reference, as the client sees it."""

    assessment: AssessmentResponse
    observation_count: int
    valid_observation_count: int
    borderline_observation_count: int
    confidence: str
    taps_per_second: float
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int
    explanation: str


class MonitoringSessionResponse(BaseModel):
    """One execution of a plan item, with its result when completed."""

    id: int
    status: str
    assessment: AssessmentResponse
    started_at: datetime
    completed_at: datetime | None
    result: SessionResultResponse | None
    longitudinal: LongitudinalSummaryResponse | None = None


class UnsupportedEventTypeMessage:
    """Message for events whose type no runner can interpret."""

    @staticmethod
    def for_type(event_type: str) -> str:
        return f"Unsupported event type: {event_type!r}"


class MissingCanvasCoordinateMessage:
    """Message for a canvas event whose payload has no usable coordinate."""

    MESSAGE = "Canvas events must carry numeric 'x' and 'y' values."


class StrokeOrderMessage:
    """Messages for a canvas stream whose strokes do not nest correctly."""

    POINT_OUTSIDE_STROKE = "A stroke point arrived outside a stroke."
    START_INSIDE_STROKE = "A stroke started before the previous one ended."
    END_OUTSIDE_STROKE = "A stroke ended without being started."
    UNCLOSED_STROKE = "The recording ended while a stroke was still open."


def event_offsets_ms(events: list[TapEventRequest]) -> list[int]:
    """Return the offsets of tap events, validating the event type."""
    offsets: list[int] = []
    for event in events:
        if event.event_type not in TAP_EVENT_TYPES:
            raise ValueError(ERR_UNSUPPORTED_EVENT_TYPE.format(type=event.event_type))
        offsets.append(event.offset_ms)
    return offsets


def canvas_strokes(events: list[TapEventRequest]) -> list[list[CanvasPoint]]:
    """Return the strokes in a canvas recording, validating the stream shape.

    Strokes must nest: a start opens one, points extend it, and an end closes
    it. A stream that violates that is rejected rather than repaired, because
    guessing where one movement ended and the next began would change the
    stroke count that the recording's quality depends on.
    """
    strokes: list[list[CanvasPoint]] = []
    current: list[CanvasPoint] = []

    for event in events:
        if event.event_type not in CANVAS_EVENT_TYPES:
            raise ValueError(ERR_UNSUPPORTED_EVENT_TYPE.format(type=event.event_type))
        point = event.point()

        if event.event_type == EVENT_TYPE_STROKE_START:
            if current:
                raise ValueError(ERR_STROKE_START_INSIDE)
            current = [point]
        elif event.event_type == EVENT_TYPE_STROKE_POINT:
            if not current:
                raise ValueError(ERR_STROKE_POINT_OUTSIDE)
            current.append(point)
        else:
            if not current:
                raise ValueError(ERR_STROKE_END_OUTSIDE)
            current.append(point)
            strokes.append(current)
            current = []

    if current:
        raise ValueError(ERR_STROKE_UNCLOSED)
    return strokes
