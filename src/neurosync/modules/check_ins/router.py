from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import get_session
from neurosync.modules.auth.dependencies import get_current_patient
from neurosync.modules.auth.models import Patient
from neurosync.modules.check_ins.models import CheckIn
from neurosync.modules.check_ins.schemas import CheckInCreateRequest, CheckInResponse
from neurosync.modules.check_ins.service import (
    DEFAULT_LIST_LIMIT,
    MAX_LIST_LIMIT,
    create_check_in,
    get_check_in,
    list_check_ins,
)

router = APIRouter(prefix="/check-ins", tags=["check-ins"])

DbSession = Annotated[AsyncSession, Depends(get_session)]
CurrentPatient = Annotated[Patient, Depends(get_current_patient)]


def _to_response(check_in: CheckIn) -> CheckInResponse:
    return CheckInResponse(
        id=check_in.id,
        recorded_at=check_in.recorded_at,
        tremor=check_in.tremor,
        stiffness=check_in.stiffness,
        slowness=check_in.slowness,
        balance=check_in.balance,
        note=check_in.note,
        created_at=check_in.created_at,
    )


@router.post(
    "",
    response_model=CheckInResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Record a symptom check-in",
    description=(
        "Stores the authenticated patient's own severity ratings (0-4) for "
        "tremor, stiffness, slowness, and balance, with an optional note. "
        "Ratings are stored exactly as reported and are not interpreted."
    ),
)
async def submit_check_in(
    payload: CheckInCreateRequest,
    patient: CurrentPatient,
    session: DbSession,
) -> CheckInResponse:
    check_in = await create_check_in(
        session=session,
        patient_id=patient.id,
        payload=payload,
    )
    return _to_response(check_in)


@router.get(
    "",
    response_model=list[CheckInResponse],
    summary="List the authenticated patient's check-ins",
    description="Returns the patient's own check-ins, newest first.",
)
async def list_patient_check_ins(
    patient: CurrentPatient,
    session: DbSession,
    limit: Annotated[int, Query(ge=1, le=MAX_LIST_LIMIT)] = DEFAULT_LIST_LIMIT,
) -> list[CheckInResponse]:
    check_ins = await list_check_ins(
        session=session,
        patient_id=patient.id,
        limit=limit,
    )
    return [_to_response(check_in) for check_in in check_ins]


@router.get(
    "/{check_in_id}",
    response_model=CheckInResponse,
    summary="Return one of the patient's check-ins",
    description=(
        "Returns a single check-in. A check-in that does not exist or does not "
        "belong to the authenticated patient both return 404."
    ),
)
async def get_check_in_detail(
    check_in_id: int,
    patient: CurrentPatient,
    session: DbSession,
) -> CheckInResponse:
    check_in = await get_check_in(
        session=session,
        patient_id=patient.id,
        check_in_id=check_in_id,
    )
    if check_in is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Check-in not found.",
        )
    return _to_response(check_in)
