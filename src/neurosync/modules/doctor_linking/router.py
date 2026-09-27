from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import get_session
from neurosync.modules.auth.dependencies import get_current_patient
from neurosync.modules.auth.models import Patient
from neurosync.modules.doctor_linking.schemas import (
    DoctorLinkCreateRequest,
    DoctorLinkResponse,
)
from neurosync.modules.doctor_linking.service import (
    DoctorCodeInactiveError,
    DoctorCodeNotFoundError,
    DuplicateDoctorLinkError,
    list_doctor_links,
    request_doctor_link,
)

router = APIRouter(prefix="/doctor-links", tags=["doctor-links"])

DbSession = Annotated[AsyncSession, Depends(get_session)]
CurrentPatient = Annotated[Patient, Depends(get_current_patient)]


@router.post(
    "",
    response_model=DoctorLinkResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Request a link to a doctor",
    description=(
        "Creates a pending link between the authenticated patient and the doctor "
        "owning the supplied code. Only a doctor can accept it."
    ),
)
async def create_doctor_link(
    payload: DoctorLinkCreateRequest,
    patient: CurrentPatient,
    session: DbSession,
) -> DoctorLinkResponse:
    try:
        summary = await request_doctor_link(
            session=session,
            patient_id=patient.id,
            doctor_code=payload.doctor_code,
        )
    except DoctorCodeNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="That doctor code was not recognised.",
        ) from exc
    except DoctorCodeInactiveError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="That doctor code is no longer active.",
        ) from exc
    except DuplicateDoctorLinkError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A pending or active link to this doctor already exists.",
        ) from exc

    return DoctorLinkResponse(
        doctor_id=summary.doctor_id,
        status=summary.status,
        created_at=summary.created_at,
    )


@router.get(
    "",
    response_model=list[DoctorLinkResponse],
    summary="List the authenticated patient's doctor links",
)
async def list_links(patient: CurrentPatient, session: DbSession) -> list[DoctorLinkResponse]:
    summaries = await list_doctor_links(session=session, patient_id=patient.id)
    return [
        DoctorLinkResponse(
            doctor_id=summary.doctor_id,
            status=summary.status,
            created_at=summary.created_at,
        )
        for summary in summaries
    ]
