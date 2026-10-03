"""Medication use cases: what the patient takes, and reported dose events.

Every function is scoped to one authenticated patient. A record belonging to
anyone else is reported as missing rather than found, so one patient can never
observe or attach another patient's medication data.
"""

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.medication.context import (
    MedicationContextResult,
    MedicationTiming,
    classify_medication_context,
)
from neurosync.modules.medication.models import (
    Medication,
    MedicationAdherence,
    MedicationEvent,
)
from neurosync.modules.medication.schemas import (
    MedicationCreateRequest,
    MedicationEventCreateRequest,
    MedicationEventResponse,
)

DEFAULT_LIST_LIMIT = 50
MAX_LIST_LIMIT = 100


class MedicationNotFoundError(Exception):
    """Raised when a medication does not exist for this patient."""


class MedicationEventNotFoundError(Exception):
    """Raised when a dose event does not exist for this patient."""


class MedicationNameRequiredError(Exception):
    """Raised when a medication is submitted without a name."""


async def create_medication(
    *,
    session: AsyncSession,
    patient_id: int,
    payload: MedicationCreateRequest,
) -> Medication:
    """Record a medication the patient reports taking."""
    name = payload.name.strip()
    if not name:
        raise MedicationNameRequiredError
    now = datetime.now(UTC)
    medication = Medication(
        patient_id=patient_id,
        name=name,
        dose_label=_clean(payload.dose_label),
        frequency_label=_clean(payload.frequency_label),
        is_active=payload.is_active,
        created_at=now,
        updated_at=now,
    )
    session.add(medication)
    await session.commit()
    await session.refresh(medication)
    return medication


def _clean(value: str | None) -> str | None:
    """Trim an optional label, treating blank text as absent rather than ''."""
    if value is None:
        return None
    trimmed = value.strip()
    return trimmed or None


async def list_medications(
    *,
    session: AsyncSession,
    patient_id: int,
    include_inactive: bool = True,
) -> list[Medication]:
    """Return the patient's medications, newest first."""
    statement = select(Medication).where(Medication.patient_id == patient_id)
    if not include_inactive:
        statement = statement.where(Medication.is_active.is_(True))
    statement = statement.order_by(Medication.created_at.desc(), Medication.id.desc())
    return list(await session.scalars(statement))


async def set_medication_active(
    *,
    session: AsyncSession,
    patient_id: int,
    medication_id: int,
    is_active: bool,
) -> Medication:
    """Activate or deactivate one of the patient's medications.

    Deactivating never deletes the record or its history; it only stops the
    medication describing the patient's current regimen.
    """
    medication = await session.scalar(
        select(Medication).where(
            Medication.id == medication_id,
            Medication.patient_id == patient_id,
        )
    )
    if medication is None:
        raise MedicationNotFoundError
    medication.is_active = is_active
    medication.updated_at = datetime.now(UTC)
    await session.commit()
    await session.refresh(medication)
    return medication


async def create_medication_event(
    *,
    session: AsyncSession,
    patient_id: int,
    payload: MedicationEventCreateRequest,
) -> MedicationEvent:
    """Record one report about a dose."""
    medication = await session.scalar(
        select(Medication).where(
            Medication.id == payload.medication_id,
            Medication.patient_id == patient_id,
        )
    )
    if medication is None:
        # Another patient's medication is indistinguishable from a missing one.
        raise MedicationNotFoundError

    now = datetime.now(UTC)
    event = MedicationEvent(
        patient_id=patient_id,
        medication_id=medication.id,
        scheduled_at=payload.scheduled_at,
        taken_at=payload.taken_at,
        adherence=payload.adherence.value,
        recorded_at=payload.recorded_at or now,
        created_at=now,
    )
    session.add(event)
    await session.commit()
    await session.refresh(event)
    return event


async def list_medication_events(
    *,
    session: AsyncSession,
    patient_id: int,
    limit: int = DEFAULT_LIST_LIMIT,
) -> list[MedicationEvent]:
    """Return the patient's reported dose events, newest first."""
    statement = (
        select(MedicationEvent)
        .where(MedicationEvent.patient_id == patient_id)
        .order_by(MedicationEvent.recorded_at.desc(), MedicationEvent.id.desc())
        .limit(limit)
    )
    return list(await session.scalars(statement))


async def get_medication_event_for_patient(
    *,
    session: AsyncSession,
    patient_id: int,
    medication_event_id: int,
) -> MedicationEvent:
    """Return one dose event when (and only when) this patient owns it."""
    event = await session.scalar(
        select(MedicationEvent).where(
            MedicationEvent.id == medication_event_id,
            MedicationEvent.patient_id == patient_id,
        )
    )
    if event is None:
        raise MedicationEventNotFoundError
    return event


async def timing_for_event(
    *,
    session: AsyncSession,
    event: MedicationEvent,
) -> MedicationTiming:
    """Adapt a stored event into the pure timing facts used for classification."""
    medication = await session.get(Medication, event.medication_id)
    return MedicationTiming(
        adherence=MedicationAdherence(event.adherence),
        taken_at=event.taken_at,
        scheduled_at=event.scheduled_at,
        is_active=medication.is_active if medication is not None else False,
        medication_name=medication.name if medication is not None else None,
    )


async def resolve_context_for_session(
    *,
    session: AsyncSession,
    patient_id: int,
    assessment_at: datetime | None,
    medication_event_id: int | None,
) -> tuple[MedicationContextResult, MedicationEvent | None]:
    """Classify the medication context for one assessment.

    With no associated event the context is ``unknown``. The event is never
    chosen automatically: if the patient did not attach one, none is inferred.
    """
    if medication_event_id is None:
        return classify_medication_context(assessment_at=assessment_at, timing=None), None

    event = await get_medication_event_for_patient(
        session=session,
        patient_id=patient_id,
        medication_event_id=medication_event_id,
    )
    timing = await timing_for_event(session=session, event=event)
    return (
        classify_medication_context(assessment_at=assessment_at, timing=timing),
        event,
    )


def event_response(event: MedicationEvent) -> MedicationEventResponse:
    """Render one stored dose event as the API returns it."""
    return MedicationEventResponse(
        id=event.id,
        medication_id=event.medication_id,
        medication_name=event.medication.name if event.medication is not None else None,
        adherence=MedicationAdherence(event.adherence),
        scheduled_at=event.scheduled_at,
        taken_at=event.taken_at,
        recorded_at=event.recorded_at,
    )
