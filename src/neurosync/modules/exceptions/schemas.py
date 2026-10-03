"""Request and response contracts for the specialist review queue.

Two shapes on purpose. The **list** row carries only what a doctor needs to
triage - who, when, why, and how strong the evidence was. The **detail** adds
the recording and the patient's own reference, because that is the evidence a
review actually turns on and it is worth fetching only once a queue entry has
been chosen.
"""

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field

from neurosync.modules.exceptions.models import ExceptionStatus


class ReviewOutcome(StrEnum):
    """The two ways a doctor can close an exception.

    ``open`` is deliberately absent. It is the state an exception arrives in,
    not an outcome a reviewer chooses, so offering it would let a doctor
    silently undo their own review.
    """

    REVIEWED = ExceptionStatus.REVIEWED.value
    DISMISSED = ExceptionStatus.DISMISSED.value


class ExceptionSummaryResponse(BaseModel):
    """One row of the review queue."""

    id: int
    patient_id: int
    patient_name: str
    exception_type: str = Field(description="Why the observation was routed, not a diagnosis")
    status: str
    rationale: str = Field(description="The sentence the routing rule generated")
    created_at: datetime
    longitudinal_state: str
    evidence_strength: str
    assessment_title: str
    medication_context: str
    minutes_since_medication: int | None


class BaselineFactsResponse(BaseModel):
    """The patient's own reference the observation was compared against."""

    observation_count: int
    confidence: str
    taps_per_second: float
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int


class ExceptionDetailResponse(BaseModel):
    """One exception with the recording and reference behind it."""

    summary: ExceptionSummaryResponse
    routing_rule: str
    supporting_observations: int
    longitudinal_result_id: int
    monitoring_session_id: int
    usable_history_count: int
    baseline_confidence: str | None
    changed_features: tuple[str, ...]
    recording_quality: str
    total_taps: int
    duration_ms: int
    taps_per_second: float
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int
    baseline: BaselineFactsResponse | None
    reviewed_by_doctor_id: int | None
    reviewed_at: datetime | None
    review_note: str | None


class ReviewExceptionRequest(BaseModel):
    """A doctor's decision about one exception."""

    status: ReviewOutcome = Field(
        description="Whether the evidence was reviewed or dismissed as needing no action"
    )
    note: str | None = Field(
        default=None,
        max_length=2000,
        description="Optional free text recorded verbatim as the doctor's own words",
    )
