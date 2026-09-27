"""Doctor-linking use cases.

This module only knows about the relationship between a patient and a doctor.
It deliberately knows nothing about monitoring data or clinical interpretation.
"""

from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.doctor_linking.models import (
    ACTIVE_LINK_STATUSES,
    DoctorCode,
    DoctorLink,
    DoctorLinkStatus,
)


class DoctorLinkingError(Exception):
    """Base class for doctor-linking errors."""


class DoctorCodeNotFoundError(DoctorLinkingError):
    """Raised when no doctor matches the supplied code."""


class DoctorCodeInactiveError(DoctorLinkingError):
    """Raised when the supplied code is no longer usable."""


class DuplicateDoctorLinkError(DoctorLinkingError):
    """Raised when a pending or active link to the doctor already exists."""


@dataclass(frozen=True, slots=True)
class DoctorLinkSummary:
    """Projection of a doctor link for read models."""

    doctor_id: int
    status: DoctorLinkStatus
    created_at: datetime


def normalize_doctor_code(doctor_code: str) -> str:
    """Normalise a doctor code for lookup."""
    return doctor_code.strip().upper()


async def request_doctor_link(
    *,
    session: AsyncSession,
    patient_id: int,
    doctor_code: str,
) -> DoctorLinkSummary:
    """Create a ``pending`` link between the patient and the code's doctor."""
    doctor_code_row = await session.scalar(
        select(DoctorCode).where(DoctorCode.code == normalize_doctor_code(doctor_code))
    )
    if doctor_code_row is None:
        raise DoctorCodeNotFoundError
    if not doctor_code_row.is_active:
        raise DoctorCodeInactiveError

    existing_link_id = await session.scalar(
        select(DoctorLink.id).where(
            DoctorLink.patient_id == patient_id,
            DoctorLink.doctor_id == doctor_code_row.doctor_id,
            DoctorLink.status.in_(ACTIVE_LINK_STATUSES),
        )
    )
    if existing_link_id is not None:
        raise DuplicateDoctorLinkError

    now = datetime.now(UTC)
    link = DoctorLink(
        patient_id=patient_id,
        doctor_id=doctor_code_row.doctor_id,
        status=DoctorLinkStatus.PENDING.value,
        created_at=now,
        updated_at=now,
    )
    session.add(link)
    try:
        await session.commit()
    except IntegrityError as exc:
        # The partial unique index is the authority; a concurrent request can
        # still get past the check above.
        raise DuplicateDoctorLinkError from exc

    return DoctorLinkSummary(
        doctor_id=link.doctor_id,
        status=DoctorLinkStatus(link.status),
        created_at=link.created_at,
    )


async def list_doctor_links(
    *,
    session: AsyncSession,
    patient_id: int,
) -> list[DoctorLinkSummary]:
    """Return the patient's links, newest first.

    Only the columns needed by the read model are selected, so no ORM objects
    are constructed for the list.
    """
    statement = (
        select(DoctorLink.doctor_id, DoctorLink.status, DoctorLink.created_at)
        .where(DoctorLink.patient_id == patient_id)
        .order_by(DoctorLink.created_at.desc(), DoctorLink.id.desc())
    )
    rows = (await session.execute(statement)).all()
    return [
        DoctorLinkSummary(
            doctor_id=row[0],
            status=DoctorLinkStatus(row[1]),
            created_at=row[2],
        )
        for row in rows
    ]
