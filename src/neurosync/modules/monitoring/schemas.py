"""API contracts for the monitoring module.

Responses deliberately describe assessments, plans, sessions and recordings;
nothing here is a clinical score and no endpoint interprets the patient.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from neurosync.modules.monitoring.models import RecordingQuality

# A 30-second task cannot plausibly produce ten thousand taps; the cap keeps a
# broken client from flooding the events table while never rejecting honest
# recordings.
MAX_TAP_EVENTS = 2_000
EVENT_TYPE_TAP = "tap"

EVENT_TYPE_DESCRIPTION = "Event type; only 'tap' events are accepted in this milestone."


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
    """One raw tap as the client recorded it."""

    event_type: str = Field(description=EVENT_TYPE_DESCRIPTION)
    offset_ms: int = Field(ge=0, description="Milliseconds into the session")
    payload: dict | None = Field(default=None, description="Optional raw client metadata")


class CompleteSessionRequest(BaseModel):
    """The raw event stream captured during one session."""

    events: list[TapEventRequest] = Field(
        max_length=MAX_TAP_EVENTS,
        description="Raw events in the order the client captured them",
    )


class SessionResultResponse(BaseModel):
    """Deterministic summary of one recording; describes the session only."""

    total_taps: int
    duration_ms: int
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int
    taps_per_second: float
    quality: RecordingQuality


class MonitoringSessionResponse(BaseModel):
    """One execution of a plan item, with its result when completed."""

    id: int
    status: str
    assessment: AssessmentResponse
    started_at: datetime
    completed_at: datetime | None
    result: SessionResultResponse | None


class UnsupportedEventTypeMessage:
    """Message for events whose type no runner can interpret."""

    @staticmethod
    def for_type(event_type: str) -> str:
        return f"Unsupported event type: {event_type!r}"


def event_offsets_ms(events: list[TapEventRequest]) -> list[int]:
    """Return the offsets of tap events, validating the event type."""
    offsets: list[int] = []
    for event in events:
        if event.event_type != EVENT_TYPE_TAP:
            raise ValueError(UnsupportedEventTypeMessage.for_type(event.event_type))
        offsets.append(event.offset_ms)
    return offsets
