"""Request and response contracts for the doctor web portal API."""

from collections.abc import Mapping
from datetime import datetime

from pydantic import BaseModel, Field, model_validator

from neurosync.modules.auth.schemas import Email, LoginPassword, Name, SignupPassword
from neurosync.modules.doctor_linking.models import DoctorLinkStatus
from neurosync.modules.monitoring.assessment_catalog import (
    get_spec,
    validate_parameters,
)


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
DEFAULT_ASSIGNMENT_SLUG = "finger_tapping"


def validated_assignment_parameters(
    slug: str,
    parameters: Mapping[str, object],
) -> dict[str, int | str]:
    """Validate a doctor's settings against the assessment's catalog spec.

    Every setting a doctor can change about a test - which hand, how fast, how
    many turns, the phrase to write - is declared once in the catalog, and this
    is the only place a submitted value meets those bounds. An assessment the
    catalog does not describe has nothing to validate against; the service is
    what reports that it cannot be assigned.
    """
    spec = get_spec(slug)
    if spec is None:
        return {}
    return validate_parameters(spec, parameters)


class CreateAssignmentRequest(BaseModel):
    """One exercise a doctor assigns to a linked patient."""

    title: str | None = Field(
        default=None,
        max_length=200,
        description="Optional display title; defaults to the assessment's title",
    )
    assessment_slug: str = Field(
        default=DEFAULT_ASSIGNMENT_SLUG,
        max_length=64,
        description="Which catalog assessment to assign",
    )
    duration_seconds: int = Field(
        default=DEFAULT_ASSIGNMENT_DURATION_SECONDS,
        ge=MIN_ASSIGNMENT_DURATION_SECONDS,
        le=MAX_ASSIGNMENT_DURATION_SECONDS,
        description="How long the recording should run",
    )
    parameters: dict[str, int | str] = Field(
        default_factory=dict,
        description="The rest of what the patient is asked to do; validated "
        "against the assessment's declared settings",
    )

    @model_validator(mode="after")
    def _check_parameters(self) -> "CreateAssignmentRequest":
        validated_assignment_parameters(self.assessment_slug, self.parameters)
        return self


class UpdateAssignmentRequest(BaseModel):
    """Changes a doctor makes to an exercise they already assigned.

    Every field is optional and only the ones actually sent are applied, so a
    doctor can change the recording length without restating the settings, and
    rename an exercise without touching either. The assessment itself is not
    editable here: changing which test a patient performs is a different
    instruction, and a plan item's recorded history belongs to the test it
    named. Removing the exercise and assigning the new one keeps that history
    unambiguous.
    """

    title: str | None = Field(
        default=None,
        max_length=200,
        description="A new display title",
    )
    duration_seconds: int | None = Field(
        default=None,
        ge=MIN_ASSIGNMENT_DURATION_SECONDS,
        le=MAX_ASSIGNMENT_DURATION_SECONDS,
        description="A new recording length",
    )
    parameters: dict[str, int | str] | None = Field(
        default=None,
        description="A new, complete set of settings; replaces what was stored",
    )

    @model_validator(mode="after")
    def _check_parameters(self) -> "UpdateAssignmentRequest":
        # The slug is not known here, so bounds are checked in the service
        # against the assessment the stored plan item actually points at.
        # Pydantic has already rejected anything that is not a number or text.
        return self

    def changed(self, field: str) -> bool:
        """Whether ``field`` was actually sent, as opposed to left out."""
        return field in self.model_fields_set


class DoctorAssignmentResponse(BaseModel):
    """An exercise the doctor assigned to one patient."""

    id: int
    title: str
    status: str
    created_at: datetime
    updated_at: datetime
    assessment_slug: str
    assessment_title: str
    duration_seconds: int
    # Every setting this exercise uses, resolved against the catalog so the
    # editor shows the values the patient will actually be given.
    parameters: dict[str, int | str]
