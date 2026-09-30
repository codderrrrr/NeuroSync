"""Symptom check-in use cases.

Check-ins are raw patient-reported observations. This module stores and
retrieves them; it never scores, compares, or interprets the data.
"""

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.check_ins.models import CheckIn
from neurosync.modules.check_ins.schemas import CheckInCreateRequest

DEFAULT_LIST_LIMIT = 30
MAX_LIST_LIMIT = 100


async def create_check_in(
    *,
    session: AsyncSession,
    patient_id: int,
    payload: CheckInCreateRequest,
) -> CheckIn:
    """Store a new check-in reported by the patient."""
    now = datetime.now(UTC)
    check_in = CheckIn(
        patient_id=patient_id,
        recorded_at=payload.recorded_at or now,
        tremor=payload.tremor,
        stiffness=payload.stiffness,
        slowness=payload.slowness,
        balance=payload.balance,
        note=payload.note,
        created_at=now,
    )
    session.add(check_in)
    await session.commit()
    await session.refresh(check_in)
    return check_in


async def list_check_ins(
    *,
    session: AsyncSession,
    patient_id: int,
    limit: int,
) -> list[CheckIn]:
    """Return the patient's check-ins, newest first."""
    statement = (
        select(CheckIn)
        .where(CheckIn.patient_id == patient_id)
        .order_by(CheckIn.recorded_at.desc(), CheckIn.id.desc())
        .limit(limit)
    )
    return list(await session.scalars(statement))


async def get_check_in(
    *,
    session: AsyncSession,
    patient_id: int,
    check_in_id: int,
) -> CheckIn | None:
    """Return the check-in when (and only when) it belongs to the patient."""
    return await session.scalar(
        select(CheckIn).where(
            CheckIn.id == check_in_id,
            CheckIn.patient_id == patient_id,
        )
    )
