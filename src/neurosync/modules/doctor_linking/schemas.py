from datetime import datetime

from pydantic import BaseModel, Field

from neurosync.modules.doctor_linking.models import DoctorLinkStatus


class DoctorLinkCreateRequest(BaseModel):
    """A doctor code supplied by the patient."""

    doctor_code: str = Field(
        min_length=1,
        max_length=32,
        description="Code provided by the doctor",
    )


class DoctorLinkResponse(BaseModel):
    """A patient's link to a doctor.

    Only the doctor identifier and the link state are exposed; no further
    doctor detail is returned to the patient application.
    """

    doctor_id: int
    status: DoctorLinkStatus
    created_at: datetime
