"""Request and response contracts for the doctor web portal API."""

from datetime import datetime

from pydantic import BaseModel, Field

from neurosync.modules.auth.schemas import Email, LoginPassword, Name, SignupPassword
from neurosync.modules.doctor_linking.models import DoctorLinkStatus


class DoctorSignupRequest(BaseModel):
    """Fields a doctor supplies to create a portal account."""

    name: Name
    email: Email
    password: SignupPassword


class DoctorLoginRequest(BaseModel):
    """Credentials a doctor supplies to sign in to the portal."""

    email: Email
    password: LoginPassword


class DoctorResponse(BaseModel):
    """Public view of the authenticated doctor."""

    id: int
    name: str
    email: str
    created_at: datetime

    # The doctor's personal link code (like a classroom join code); patients
    # type it to request a link.
    code: str | None = None


class DoctorAuthResponse(BaseModel):
    """An authenticated doctor session returned by signup and login."""

    doctor: DoctorResponse
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime


class PendingLinkResponse(BaseModel):
    """A patient's pending request, awaiting the doctor's decision."""

    id: int
    patient_id: int
    patient_name: str
    created_at: datetime


class RosterPatientResponse(BaseModel):
    """A patient on the doctor's active roster."""

    patient_id: int
    patient_name: str
    status: DoctorLinkStatus
    linked_at: datetime


class AcceptLinkResponse(BaseModel):
    """The state of a link after an accept request."""

    id: int
    patient_id: int
    patient_name: str
    status: DoctorLinkStatus
    accepted_at: datetime | None


# Assignment bounds: long enough to be a usable recording, short enough that a
# patient completes it in one sitting.
MIN_ASSIGNMENT_DURATION_SECONDS = 10
MAX_ASSIGNMENT_DURATION_SECONDS = 600
DEFAULT_ASSIGNMENT_DURATION_SECONDS = 30


class CreateAssignmentRequest(BaseModel):
    """One exercise a doctor assigns to a linked patient."""

    title: str | None = Field(
        default=None,
        max_length=200,
        description="Optional display title; defaults to the assessment's title",
    )
    assessment_slug: str = Field(
        default="finger_tapping",
        max_length=64,
        description="Which catalog assessment to assign",
    )
    duration_seconds: int = Field(
        default=DEFAULT_ASSIGNMENT_DURATION_SECONDS,
        ge=MIN_ASSIGNMENT_DURATION_SECONDS,
        le=MAX_ASSIGNMENT_DURATION_SECONDS,
        description="How long the recording should run",
    )


class DoctorAssignmentResponse(BaseModel):
    """An exercise the doctor assigned to one patient."""

    id: int
    title: str
    status: str
    created_at: datetime
    assessment_title: str
    duration_seconds: int
