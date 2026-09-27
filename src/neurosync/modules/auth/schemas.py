from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BaseModel, EmailStr, Field

MIN_PASSWORD_LENGTH = 12
MAX_PASSWORD_LENGTH = 128
MAX_EMAIL_LENGTH = 320


BLANK_TEXT_MESSAGE = "must not be blank"
BLANK_PASSWORD_MESSAGE = "password must not be blank"


def _strip_required_text(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError(BLANK_TEXT_MESSAGE)
    return stripped


def _reject_blank_password(value: str) -> str:
    if not value.strip():
        raise ValueError(BLANK_PASSWORD_MESSAGE)
    return value


Name = Annotated[
    str,
    Field(min_length=1, max_length=200, description="Patient's full name"),
    AfterValidator(_strip_required_text),
]
Email = Annotated[
    EmailStr,
    Field(max_length=MAX_EMAIL_LENGTH, description="Email address used to sign in"),
]
SignupPassword = Annotated[
    str,
    Field(
        min_length=MIN_PASSWORD_LENGTH,
        max_length=MAX_PASSWORD_LENGTH,
        description=f"At least {MIN_PASSWORD_LENGTH} characters",
    ),
    AfterValidator(_reject_blank_password),
]
LoginPassword = Annotated[str, Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)]


class SignupRequest(BaseModel):
    """Fields a patient supplies to create an account."""

    name: Name
    email: Email
    password: SignupPassword


class LoginRequest(BaseModel):
    """Credentials a patient supplies to sign in."""

    email: Email
    password: LoginPassword


class PatientResponse(BaseModel):
    """Public view of the authenticated patient."""

    id: int
    email: str
    name: str
    created_at: datetime


class AuthResponse(BaseModel):
    """An authenticated session returned by signup and login."""

    patient: PatientResponse
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime
