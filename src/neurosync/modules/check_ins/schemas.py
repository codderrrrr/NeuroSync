from datetime import UTC, datetime, timedelta
from typing import Annotated, Self

from pydantic import BaseModel, Field, field_validator, model_validator

from neurosync.modules.check_ins.models import SEVERITY_MAX, SEVERITY_MIN

MAX_NOTE_LENGTH = 500
# Client clocks can run slightly ahead of server time; only clearly future
# timestamps are rejected.
RECORDED_AT_TOLERANCE = timedelta(minutes=5)

_TIMEZONE_REQUIRED_MESSAGE = (
    "recorded_at must include a timezone offset, e.g. 2026-06-20T10:00:00+00:00"
)
_FUTURE_MESSAGE = "recorded_at cannot be in the future."

Severity = Annotated[
    int,
    Field(
        ge=SEVERITY_MIN,
        le=SEVERITY_MAX,
        description="Patient-reported severity from 0 (not present) to 4 (severe)",
    ),
]


class CheckInCreateRequest(BaseModel):
    """A single patient-reported symptom check-in.

    Ratings are the patient's own observations and are stored as reported.
    Nothing in this request is scored or interpreted.
    """

    tremor: Severity
    stiffness: Severity
    slowness: Severity
    balance: Severity
    note: str | None = Field(
        default=None,
        max_length=MAX_NOTE_LENGTH,
        description="Optional free-text note, at most 500 characters",
    )
    recorded_at: datetime | None = Field(
        default=None,
        description="When the symptoms were felt; defaults to the current time (UTC)",
    )

    @field_validator("note")
    @classmethod
    def normalize_note(cls, value: str | None) -> str | None:
        """Store blank notes as no note."""
        if value is None:
            return None
        return value.strip() or None

    @model_validator(mode="after")
    def validate_recorded_at(self) -> Self:
        """Reject timestamps that are naive or clearly in the future."""
        if self.recorded_at is None:
            return self
        if self.recorded_at.tzinfo is None:
            raise ValueError(_TIMEZONE_REQUIRED_MESSAGE)
        if self.recorded_at > datetime.now(UTC) + RECORDED_AT_TOLERANCE:
            raise ValueError(_FUTURE_MESSAGE)
        return self


class CheckInResponse(BaseModel):
    """A stored check-in, returned exactly as the patient reported it."""

    id: int
    recorded_at: datetime
    tremor: int
    stiffness: int
    slowness: int
    balance: int
    note: str | None
    created_at: datetime
