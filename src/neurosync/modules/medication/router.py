"""Medication API endpoints.

Patient identity always comes from the authenticated session; no endpoint takes
a patient identifier from the request. These routes record what the patient
reports taking and whether a dose was taken. They never interpret it.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.db import get_session
from neurosync.modules.auth.dependencies import get_current_patient
from neurosync.modules.auth.models import Patient
from neurosync.modules.medication import service
from neurosync.modules.medication.schemas import (
    MedicationCreateRequest,
    MedicationEventCreateRequest,
    MedicationEventResponse,
    MedicationResponse,
)

router = APIRouter(prefix="/medications", tags=["medications"])

DbSession = Annotated[AsyncSession, Depends(get_session)]
CurrentPatient = Annotated[Patient, Depends(get_current_patient)]


@router.post(
    "",
    response_model=MedicationResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Record a medication the patient takes",
    description=(
        "Stores the medication exactly as reported. Dose and frequency are "
        "free text and are never parsed or interpreted."
    ),
)
async def create_medication(
    payload: MedicationCreateRequest,
    patient: CurrentPatient,
    session: DbSession,
) -> MedicationResponse:
    try:
        medication = await service.create_medication(
            session=session,
            patient_id=patient.id,
            payload=payload,
        )
    except service.MedicationNameRequiredError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A medication needs a name.",
        ) from exc
    return MedicationResponse.model_validate(medication)


@router.get(
    "",
    response_model=list[MedicationResponse],
    summary="List the patient's medications",
)
async def list_medications(
    patient: CurrentPatient,
    session: DbSession,
    include_inactive: Annotated[bool, Query()] = True,
) -> list[MedicationResponse]:
    medications = await service.list_medications(
        session=session,
        patient_id=patient.id,
        include_inactive=include_inactive,
    )
    return [MedicationResponse.model_validate(m) for m in medications]


@router.patch(
    "/{medication_id}",
    response_model=MedicationResponse,
    summary="Activate or deactivate one of the patient's medications",
    description=(
        "Deactivating never deletes the record or its history; it only stops "
        "the medication describing the patient's current regimen."
    ),
)
async def set_medication_active(
    medication_id: int,
    patient: CurrentPatient,
    session: DbSession,
    is_active: Annotated[bool, Query()] = True,
) -> MedicationResponse:
    try:
        medication = await service.set_medication_active(
            session=session,
            patient_id=patient.id,
            medication_id=medication_id,
            is_active=is_active,
        )
    except service.MedicationNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Medication not found.",
        ) from exc
    return MedicationResponse.model_validate(medication)


@router.post(
    "/events",
    response_model=MedicationEventResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Record a dose event",
    description=(
        "Records what the patient reports about a dose. `not_taken` and "
        "`not_sure` are complete answers that need no timestamp, and the "
        "resulting monitoring context stays `unknown`."
    ),
)
async def create_medication_event(
    payload: MedicationEventCreateRequest,
    patient: CurrentPatient,
    session: DbSession,
) -> MedicationEventResponse:
    try:
        event = await service.create_medication_event(
            session=session,
            patient_id=patient.id,
            payload=payload,
        )
    except service.MedicationNotFoundError as exc:
        # Another patient's medication is indistinguishable from a missing one.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Medication not found.",
        ) from exc

    return service.event_response(event)


@router.get(
    "/events",
    response_model=list[MedicationEventResponse],
    summary="List the patient's dose events",
)
async def list_medication_events(
    patient: CurrentPatient,
    session: DbSession,
    limit: Annotated[int, Query(ge=1, le=service.MAX_LIST_LIMIT)] = (service.DEFAULT_LIST_LIMIT),
) -> list[MedicationEventResponse]:
    events = await service.list_medication_events(
        session=session,
        patient_id=patient.id,
        limit=limit,
    )
    return [service.event_response(event) for event in events]
