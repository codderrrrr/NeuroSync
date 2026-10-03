"""API contracts for the medication module.

Dose and frequency travel as the free text the patient entered. No endpoint
parses them into numbers or proposes changes to them.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from neurosync.modules.medication.models import MedicationAdherence


class MedicationCreateRequest(BaseModel):
    """A medication the patient reports taking."""

    name: str = Field(min_length=1, max_length=200, description="As reported")
    dose_label: str | None = Field(
        default=None,
        max_length=100,
        description="Free text exactly as reported; never parsed",
    )
    frequency_label: str | None = Field(
        default=None,
        max_length=100,
        description="Free text exactly as reported; never parsed",
    )
    is_active: bool = True


class MedicationResponse(BaseModel):
    """One medication record."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    dose_label: str | None
    frequency_label: str | None
    is_active: bool
    created_at: datetime
    updated_at: datetime


class MedicationEventCreateRequest(BaseModel):
    """One report about a dose.

    ``taken_at`` is what the patient says they actually took it, which may be
    unknown. A ``not_taken`` or ``not_sure`` report is a complete answer on its
    own and needs no timestamp.
    """

    medication_id: int = Field(description="The medication this event concerns")
    adherence: MedicationAdherence
    scheduled_at: datetime | None = None
    taken_at: datetime | None = None
    recorded_at: datetime | None = Field(
        default=None,
        description="Defaults to now; set explicitly when back-filling a report",
    )


class MedicationEventResponse(BaseModel):
    """One reported dose event."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    medication_id: int
    medication_name: str | None = None
    adherence: MedicationAdherence
    scheduled_at: datetime | None
    taken_at: datetime | None
    recorded_at: datetime
