"""Doctor authentication and roster use cases.

Doctor identity always comes from the session, never from the request, so the
portal cannot act on behalf of another doctor. Link queries are filtered by the
authenticated doctor's id, so a link that exists but belongs to someone else is
indistinguishable from one that does not exist. Each use case that writes owns
its transaction, matching the other modules.
"""

import asyncio
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db.models import Doctor
from neurosync.modules.auth.models import Patient
from neurosync.modules.auth.security import (
    generate_session_token,
    hash_password,
    hash_session_token,
    verify_password,
)
from neurosync.modules.auth.session_support import (
    issue_session_token,
    resolve_owner_for_session,
    revoke_session_token,
)
from neurosync.modules.doctor.models import DoctorSession
from neurosync.modules.doctor.schemas import validated_assignment_parameters
from neurosync.modules.doctor_linking.models import DoctorCode, DoctorLink, DoctorLinkStatus
from neurosync.modules.monitoring import service as monitoring_service
from neurosync.modules.monitoring.models import (
    AssessmentDefinition,
    MonitoringPlan,
    MonitoringPlanItem,
    PlanStatus,
)

# Verifying against this hash when no account exists keeps response time
# similar for known and unknown emails, which resists account enumeration.
_DUMMY_PASSWORD_HASH = hash_password("neurosync-doctor-timing-equalisation")

# A desktop workspace re-authenticates more often than a phone app.
DOCTOR_SESSION_TTL = timedelta(days=7)


class DoctorAuthError(Exception):
    """Base class for doctor authentication errors."""


class InvalidDoctorCredentialsError(DoctorAuthError):
    """Raised when the email/password pair is not valid."""


class DoctorEmailAlreadyRegisteredError(DoctorAuthError):
    """Raised when a signup email already belongs to a doctor."""


class DoctorNameAlreadyRegisteredError(DoctorAuthError):
    """Raised when a signup name already belongs to a doctor."""


class InactiveDoctorError(DoctorAuthError):
    """Raised when the doctor account exists but is not active."""


class InvalidDoctorSessionError(DoctorAuthError):
    """Raised when a session token is absent, revoked, expired or not owned."""


class DoctorCodeGenerationError(DoctorAuthError):
    """Raised when a unique link code could not be generated after retries."""


class DoctorLinkError(Exception):
    """Base class for doctor roster errors."""


class PatientLinkNotFoundError(DoctorLinkError):
    """Raised when a link does not exist for this doctor."""


ERR_MISSING_LINKED_PATIENT = "Linked patient {patient_id} is missing."


def _now() -> datetime:
    return datetime.now(UTC)


def normalize_doctor_email(email: str) -> str:
    """Normalise an email address for storage and lookup."""
    return email.strip().lower()


# Link codes are shown to patients and typed by hand, so ambiguous characters
# (I/L/O and 0/1) are excluded, like a classroom join code.
DOCTOR_CODE_LENGTH = 7
_DOCTOR_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
_MAX_CODE_ATTEMPTS = 5


def generate_doctor_code() -> str:
    """Return a new shareable doctor link code."""
    return "".join(secrets.choice(_DOCTOR_CODE_ALPHABET) for _ in range(DOCTOR_CODE_LENGTH))


async def _issue_session(session: AsyncSession, doctor_id: int) -> tuple[str, datetime]:
    """Persist a new doctor session, returning its raw token and expiry."""
    token = generate_session_token()
    return await issue_session_token(
        session,
        session_model=DoctorSession,
        owner_id_column="doctor_id",
        owner_id=doctor_id,
        token=token,
        ttl=DOCTOR_SESSION_TTL,
    )


async def _issue_doctor_code(session: AsyncSession, doctor_id: int) -> str:
    """Create the doctor's personal link code, retrying on rare collisions."""
    for _ in range(_MAX_CODE_ATTEMPTS):
        code = generate_doctor_code()
        clash = await session.scalar(select(DoctorCode.id).where(DoctorCode.code == code))
        if clash is not None:
            continue
        session.add(DoctorCode(doctor_id=doctor_id, code=code, is_active=True))
        await session.flush()
        return code
    raise DoctorCodeGenerationError


async def signup_doctor(
    *,
    session: AsyncSession,
    name: str,
    email: str,
    password: str,
) -> tuple[Doctor, str, str, datetime]:
    """Create a doctor account with a personal link code and start a session.

    The code is what patients type to request a link, like a classroom join
    code: it is generated here, unique across all doctors, and shown in the
    doctor's profile.
    """
    normalized_email = normalize_doctor_email(email)
    existing_doctor_id = await session.scalar(
        select(Doctor.id).where(Doctor.email == normalized_email)
    )
    if existing_doctor_id is not None:
        raise DoctorEmailAlreadyRegisteredError

    existing_name_id = await session.scalar(select(Doctor.id).where(Doctor.name == name))
    if existing_name_id is not None:
        raise DoctorNameAlreadyRegisteredError

    password_hash = await asyncio.to_thread(hash_password, password)
    doctor = Doctor(
        name=name,
        email=normalized_email,
        password_hash=password_hash,
        is_active=True,
    )
    session.add(doctor)
    await session.flush()

    code = await _issue_doctor_code(session, doctor.id)

    token, expires_at = await _issue_session(session, doctor.id)
    await session.commit()
    return doctor, code, token, expires_at


async def get_doctor_code(session: AsyncSession, doctor_id: int) -> str | None:
    """Return the doctor's active link code, if one exists."""
    return await session.scalar(
        select(DoctorCode.code)
        .where(DoctorCode.doctor_id == doctor_id, DoctorCode.is_active.is_(True))
        .order_by(DoctorCode.created_at.asc(), DoctorCode.id.asc())
        .limit(1)
    )


async def login_doctor(
    *,
    session: AsyncSession,
    email: str,
    password: str,
) -> tuple[Doctor, str, datetime]:
    """Verify doctor credentials and start a portal session.

    Doctors provisioned before the portal (development seeds) have no
    credentials; their records are matched by email but always fail login.
    """
    doctor = await session.scalar(
        select(Doctor).where(Doctor.email == normalize_doctor_email(email))
    )
    if doctor is None or doctor.password_hash is None:
        await asyncio.to_thread(verify_password, password, _DUMMY_PASSWORD_HASH)
        raise InvalidDoctorCredentialsError

    if not await asyncio.to_thread(verify_password, password, doctor.password_hash):
        raise InvalidDoctorCredentialsError

    if not doctor.is_active:
        raise InactiveDoctorError

    token, expires_at = await _issue_session(session, doctor.id)
    await session.commit()
    return doctor, token, expires_at


async def resolve_doctor_for_session(session: AsyncSession, *, token: str) -> Doctor:
    """Return the active doctor that owns a usable portal session token.

    A single indexed lookup resolves the session and its doctor, and the query
    only succeeds while the session is unrevoked, unexpired and the account is
    active.
    """
    try:
        return await resolve_owner_for_session(
            session,
            token_hash=hash_session_token(token),
            owner_model=Doctor,
            session_model=DoctorSession,
            owner_id_column=DoctorSession.doctor_id,
        )
    except LookupError as exc:
        raise InvalidDoctorSessionError from exc


async def revoke_doctor_session(session: AsyncSession, *, token: str) -> None:
    """Revoke a doctor session. Unknown or already-revoked tokens are ignored."""
    await revoke_session_token(
        session,
        token_hash=hash_session_token(token),
        session_model=DoctorSession,
    )


@dataclass(frozen=True, slots=True)
class RosterPatient:
    """Projection of an accepted link for the doctor's roster."""

    link_id: int
    patient_id: int
    patient_name: str
    status: DoctorLinkStatus
    linked_at: datetime


@dataclass(frozen=True, slots=True)
class PendingRequest:
    """Projection of a pending link awaiting the doctor's decision."""

    link_id: int
    patient_id: int
    patient_name: str
    created_at: datetime


async def list_pending_requests(
    *,
    session: AsyncSession,
    doctor_id: int,
) -> list[PendingRequest]:
    """Return the doctor's pending patient requests, oldest first.

    Oldest first because acceptance is a queue: the longest-waiting patient is
    the one a doctor should see at the top.
    """
    statement = (
        select(
            DoctorLink.id,
            DoctorLink.patient_id,
            Patient.name,
            DoctorLink.created_at,
        )
        .join(Patient, Patient.id == DoctorLink.patient_id)
        .where(
            DoctorLink.doctor_id == doctor_id,
            DoctorLink.status == DoctorLinkStatus.PENDING.value,
        )
        .order_by(DoctorLink.created_at.asc(), DoctorLink.id.asc())
    )
    rows = (await session.execute(statement)).all()
    return [
        PendingRequest(
            link_id=row[0],
            patient_id=row[1],
            patient_name=row[2],
            created_at=row[3],
        )
        for row in rows
    ]


async def list_active_patients(
    *,
    session: AsyncSession,
    doctor_id: int,
) -> list[RosterPatient]:
    """Return the doctor's accepted patients, newest acceptance first."""
    statement = (
        select(
            DoctorLink.id,
            DoctorLink.patient_id,
            Patient.name,
            DoctorLink.status,
            DoctorLink.accepted_at,
            DoctorLink.created_at,
        )
        .join(Patient, Patient.id == DoctorLink.patient_id)
        .where(
            DoctorLink.doctor_id == doctor_id,
            DoctorLink.status == DoctorLinkStatus.ACTIVE.value,
        )
        .order_by(DoctorLink.accepted_at.desc().nulls_last(), DoctorLink.id.desc())
    )
    rows = (await session.execute(statement)).all()
    return [
        RosterPatient(
            link_id=row[0],
            patient_id=row[1],
            patient_name=row[2],
            status=DoctorLinkStatus(row[3]),
            linked_at=row[4] if row[4] is not None else row[5],
        )
        for row in rows
    ]


async def get_link_for_doctor(
    *,
    session: AsyncSession,
    doctor_id: int,
    link_id: int,
) -> DoctorLink:
    """Return the link when (and only when) the doctor owns it."""
    link = await session.scalar(
        select(DoctorLink).where(
            DoctorLink.id == link_id,
            DoctorLink.doctor_id == doctor_id,
        )
    )
    if link is None:
        raise PatientLinkNotFoundError
    return link


async def accept_patient_link(
    *,
    session: AsyncSession,
    doctor_id: int,
    link_id: int,
) -> tuple[DoctorLink, str, bool]:
    """Accept a pending patient request on the doctor's roster.

    Accepting an already-accepted link succeeds without changing it, so a
    retried request or a double click cannot fail or duplicate work. A link
    that does not exist for this doctor raises ``PatientLinkNotFoundError``;
    the caller maps that to 404 so another doctor's request is
    indistinguishable from a missing one.

    Returns the link, the patient's name, and whether this call changed it.
    """
    link = await get_link_for_doctor(
        session=session,
        doctor_id=doctor_id,
        link_id=link_id,
    )
    if link.status == DoctorLinkStatus.ACTIVE.value:
        patient_name = await _patient_name(session, link.patient_id)
        return link, patient_name, False

    link.status = DoctorLinkStatus.ACTIVE.value
    link.accepted_at = _now()
    await session.commit()

    # Re-read so the caller sees the persisted state, not the identity map.
    persisted = await get_link_for_doctor(
        session=session,
        doctor_id=doctor_id,
        link_id=link_id,
    )
    patient_name = await _patient_name(session, persisted.patient_id)
    return persisted, patient_name, True


async def _patient_name(session: AsyncSession, patient_id: int) -> str:
    """Return a patient's name, failing loudly if the account vanished."""
    name = await session.scalar(select(Patient.name).where(Patient.id == patient_id))
    if name is None:
        raise DoctorLinkError(ERR_MISSING_LINKED_PATIENT.format(patient_id=patient_id))
    return name


@dataclass(frozen=True, slots=True)
class AssignmentSummary:
    """Projection of one exercise a doctor assigned to a patient."""

    plan_id: int
    title: str
    status: str
    created_at: datetime
    updated_at: datetime
    assessment_slug: str
    assessment_title: str
    duration_seconds: int
    parameters: dict[str, int | str]


class PatientNotLinkedError(DoctorLinkError):
    """Raised when a patient is not on the doctor's active roster."""


class AssignmentNotFoundError(DoctorLinkError):
    """Raised when an exercise does not exist for this doctor and patient."""


async def _active_link_id(
    session: AsyncSession,
    *,
    doctor_id: int,
    patient_id: int,
) -> int | None:
    return await session.scalar(
        select(DoctorLink.id).where(
            DoctorLink.doctor_id == doctor_id,
            DoctorLink.patient_id == patient_id,
            DoctorLink.status == DoctorLinkStatus.ACTIVE.value,
        )
    )


def _summary(
    plan: MonitoringPlan,
    item: MonitoringPlanItem,
    definition: AssessmentDefinition,
) -> AssignmentSummary:
    return AssignmentSummary(
        plan_id=plan.id,
        title=plan.title,
        status=plan.status,
        created_at=plan.created_at,
        updated_at=plan.updated_at,
        assessment_slug=definition.slug,
        assessment_title=definition.title,
        duration_seconds=monitoring_service.resolve_item_duration_seconds(item, definition),
        parameters=monitoring_service.resolve_item_parameters(item, definition),
    )


async def create_assignment(  # noqa: PLR0913 - explicit arguments beat a config object
    *,
    session: AsyncSession,
    doctor_id: int,
    patient_id: int,
    title: str | None,
    assessment_slug: str,
    duration_seconds: int,
    parameters: dict[str, int | str] | None = None,
) -> AssignmentSummary:
    """Assign one supported assessment to a linked patient.

    The assignment is an active monitoring plan owned by this doctor; the
    patient app always shows the newest active plan, so the latest assignment
    is the one the patient sees. Only assessments that are being handed out
    can be assigned, and the patient must be on the doctor's active roster.
    ``parameters`` is the rest of what the patient is asked to do, already
    validated against the assessment's catalog specs at the API boundary.
    """
    if await _active_link_id(session, doctor_id=doctor_id, patient_id=patient_id) is None:
        raise PatientNotLinkedError

    definition = await monitoring_service.get_assessment_definition(
        session,
        slug=assessment_slug,
    )
    if definition is None or not definition.is_supported:
        raise monitoring_service.UnsupportedAssessmentError(
            monitoring_service.ERR_UNASSIGNABLE_ASSESSMENTS.format(slugs=[assessment_slug])
        )

    plan = await monitoring_service.create_plan(
        session=session,
        patient_id=patient_id,
        title=title if title is not None else definition.title,
        assessment_definition_ids=[definition.id],
        doctor_id=doctor_id,
        status=PlanStatus.ACTIVE,
        duration_seconds=duration_seconds,
        # An empty set means "the doctor changed nothing", which is stored as
        # no parameters at all rather than as a row of nothing.
        parameters=parameters or None,
    )
    item = await _first_item(session, plan.id)
    return _summary(plan, item, definition)


async def _first_item(session: AsyncSession, plan_id: int) -> MonitoringPlanItem:
    """Return a plan's first item.

    An assignment is always a single-assessment plan; this is the one place
    that assumption is expressed, so a plan that somehow has no item fails
    loudly here instead of producing a summary with nothing in it.
    """
    item = await session.scalar(
        select(MonitoringPlanItem)
        .where(MonitoringPlanItem.plan_id == plan_id)
        .order_by(MonitoringPlanItem.position)
        .limit(1)
    )
    if item is None:
        raise monitoring_service.MonitoringError(monitoring_service.ERR_MISSING_PLAN_ITEM)
    return item


async def _assignment_for_doctor(
    *,
    session: AsyncSession,
    doctor_id: int,
    patient_id: int,
    plan_id: int,
) -> tuple[MonitoringPlan, MonitoringPlanItem, AssessmentDefinition]:
    """Return one exercise when (and only when) this doctor assigned it.

    Filtered by doctor and patient together, so an exercise that exists but
    belongs to someone else is indistinguishable from one that never existed.
    """
    row = (
        await session.execute(
            select(MonitoringPlan, MonitoringPlanItem, AssessmentDefinition)
            .join(MonitoringPlanItem, MonitoringPlanItem.plan_id == MonitoringPlan.id)
            .join(
                AssessmentDefinition,
                AssessmentDefinition.id == MonitoringPlanItem.assessment_definition_id,
            )
            .where(
                MonitoringPlan.id == plan_id,
                MonitoringPlan.doctor_id == doctor_id,
                MonitoringPlan.patient_id == patient_id,
            )
            .order_by(MonitoringPlanItem.position)
            .limit(1)
        )
    ).first()
    if row is None:
        raise AssignmentNotFoundError
    return row[0], row[1], row[2]


async def update_assignment(  # noqa: PLR0913 - explicit arguments beat a config object
    *,
    session: AsyncSession,
    doctor_id: int,
    patient_id: int,
    plan_id: int,
    title: str | None = None,
    duration_seconds: int | None = None,
    parameters: dict[str, int | str] | None = None,
) -> AssignmentSummary:
    """Change what an already-assigned exercise asks the patient to do.

    Only the fields the caller supplies are applied, so changing the recording
    length cannot silently reset the settings and renaming cannot reset the
    length. The assessment is fixed: a plan item's recorded history belongs to
    the test it named, so switching tests means removing this exercise and
    assigning the new one.

    ``parameters`` replaces the stored set rather than merging into it, because
    the catalog always describes a complete set and a half-updated one would
    leave the patient doing half of what the doctor last chose.

    An exercise the doctor has already removed is reported as missing rather
    than edited. The patient is never going to be asked to do it again, so an
    edit would succeed, return the new settings, and quietly change nothing
    the patient will ever see.

    An exercise built on a test that has since been held back is refused for
    the same reason, and this one is reachable in practice: a plan created
    while the test was live is still in the database. The doctor still sees it
    in their list, but the patient's plan no longer contains it, so an edit
    would change nothing anyone sees. Removing it still works.
    """
    if await _active_link_id(session, doctor_id=doctor_id, patient_id=patient_id) is None:
        raise PatientNotLinkedError

    plan, item, definition = await _assignment_for_doctor(
        session=session,
        doctor_id=doctor_id,
        patient_id=patient_id,
        plan_id=plan_id,
    )
    if plan.status == PlanStatus.ARCHIVED.value:
        raise AssignmentNotFoundError

    if not definition.is_supported:
        # Checked after the archived test above: an exercise the doctor removed
        # reads as missing whatever test it was built on.
        raise monitoring_service.UnsupportedAssessmentError(
            monitoring_service.ERR_UNASSIGNABLE_ASSESSMENTS.format(slugs=[definition.slug])
        )

    if title is not None:
        plan.title = title
    if duration_seconds is not None:
        item.duration_seconds = duration_seconds
    if parameters is not None:
        item.parameters = validated_assignment_parameters(definition.slug, parameters)
    plan.updated_at = _now()

    await session.commit()
    return _summary(plan, item, definition)


async def remove_assignment(
    *,
    session: AsyncSession,
    doctor_id: int,
    patient_id: int,
    plan_id: int,
) -> None:
    """Remove an exercise from a patient.

    The plan is archived rather than deleted. A recording is a clinical record
    the patient performed and the longitudinal layer already read, and the
    cascade from a deleted plan would take the sessions, their raw events and
    their results with it. Archiving takes the exercise off the patient's next
    check-in and leaves everything that was recorded against it intact and
    attributable. Removing an exercise twice is not an error.
    """
    if await _active_link_id(session, doctor_id=doctor_id, patient_id=patient_id) is None:
        raise PatientNotLinkedError

    plan, _item, _definition = await _assignment_for_doctor(
        session=session,
        doctor_id=doctor_id,
        patient_id=patient_id,
        plan_id=plan_id,
    )
    if plan.status == PlanStatus.ARCHIVED.value:
        return

    plan.status = PlanStatus.ARCHIVED.value
    plan.updated_at = _now()
    await session.commit()


async def list_assignments(
    *,
    session: AsyncSession,
    doctor_id: int,
    patient_id: int,
) -> list[AssignmentSummary]:
    """Return the doctor's assignments for one patient, newest first.

    Archived exercises are included with their status, so a doctor can still
    see what they removed and when.
    """
    if await _active_link_id(session, doctor_id=doctor_id, patient_id=patient_id) is None:
        raise PatientNotLinkedError

    statement = (
        select(MonitoringPlan, MonitoringPlanItem, AssessmentDefinition)
        .join(MonitoringPlanItem, MonitoringPlanItem.plan_id == MonitoringPlan.id)
        .join(
            AssessmentDefinition,
            AssessmentDefinition.id == MonitoringPlanItem.assessment_definition_id,
        )
        .where(
            MonitoringPlan.doctor_id == doctor_id,
            MonitoringPlan.patient_id == patient_id,
        )
        .order_by(
            MonitoringPlan.created_at.desc(),
            MonitoringPlan.id.desc(),
            MonitoringPlanItem.position.asc(),
        )
    )
    rows = (await session.execute(statement)).all()
    return [_summary(plan, item, definition) for plan, item, definition in rows]
