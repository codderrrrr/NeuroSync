"""Seed a complete doctor-portal development scenario.

Creates (idempotently) everything the portal needs to demonstrate the first
vertical slice:

- a doctor with portal credentials
- a doctor code the patient can use
- a patient with patient-app credentials
- a ``pending`` link request from the patient to the doctor

Re-running never duplicates rows: existing doctors, patients, codes and links
are reused. No clinical or monitoring data is created. The script refuses to
run when ``ENVIRONMENT=production``, like the other development seeds.

Usage:
    uv run python -m neurosync.scripts.seed_doctor_portal [options]
"""

import argparse
import asyncio
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.config.settings import settings
from neurosync.db import Doctor, async_session_factory
from neurosync.modules.auth.models import Patient
from neurosync.modules.auth.security import hash_password
from neurosync.modules.doctor_linking.models import DoctorCode, DoctorLink, DoctorLinkStatus

# Note: emails must pass the API's EmailStr validation, which rejects
# reserved names such as ``.local``; ``example.com`` is accepted.
DEFAULT_DOCTOR_NAME = "Dr. Development"
DEFAULT_DOCTOR_EMAIL = "doctor@example.com"
DEFAULT_DOCTOR_PASSWORD = "portal-dev-password"
DEFAULT_DOCTOR_CODE = "ABC123"
DEFAULT_PATIENT_NAME = "Demo Patient"
DEFAULT_PATIENT_EMAIL = "patient@example.com"
DEFAULT_PATIENT_PASSWORD = "patient-dev-password"
PRODUCTION_GUARD_MESSAGE = "Refusing to seed development data in a production environment."


async def _get_or_create_doctor(
    session: AsyncSession,
    name: str,
    email: str,
    password: str,
) -> Doctor:
    doctor = await session.scalar(select(Doctor).where(Doctor.name == name))
    if doctor is None:
        doctor = Doctor(
            name=name,
            email=email,
            password_hash=hash_password(password),
            is_active=True,
        )
        session.add(doctor)
        await session.flush()
    elif doctor.password_hash is None:
        # Backfill credentials for a doctor provisioned before the portal.
        doctor.email = doctor.email or email
        doctor.password_hash = hash_password(password)
    return doctor


async def _get_or_create_code(
    session: AsyncSession,
    doctor_id: int,
    code: str,
) -> DoctorCode:
    doctor_code = await session.scalar(select(DoctorCode).where(DoctorCode.code == code))
    if doctor_code is None:
        doctor_code = DoctorCode(doctor_id=doctor_id, code=code, is_active=True)
        session.add(doctor_code)
        await session.flush()
    return doctor_code


async def _get_or_create_patient(
    session: AsyncSession,
    name: str,
    email: str,
    password: str,
) -> Patient:
    patient = await session.scalar(select(Patient).where(Patient.email == email))
    if patient is None:
        patient = Patient(
            name=name,
            email=email,
            password_hash=hash_password(password),
            is_active=True,
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
        )
        session.add(patient)
        await session.flush()
    return patient


async def _get_or_create_pending_link(
    session: AsyncSession,
    doctor_id: int,
    patient_id: int,
) -> DoctorLink:
    link = await session.scalar(
        select(DoctorLink).where(
            DoctorLink.doctor_id == doctor_id,
            DoctorLink.patient_id == patient_id,
        )
    )
    if link is None:
        link = DoctorLink(
            doctor_id=doctor_id,
            patient_id=patient_id,
            status=DoctorLinkStatus.PENDING.value,
        )
        session.add(link)
        await session.flush()
    return link


class PortalSeedSpec:
    """Everything the seed creates, kept together for readability."""

    def __init__(self, arguments: argparse.Namespace) -> None:
        self.doctor_name = arguments.doctor_name.strip()
        self.doctor_email = arguments.doctor_email.strip().lower()
        self.doctor_password = arguments.doctor_password
        self.doctor_code = arguments.doctor_code.strip().upper()
        self.patient_name = arguments.patient_name.strip()
        self.patient_email = arguments.patient_email.strip().lower()
        self.patient_password = arguments.patient_password


async def seed_doctor_portal(spec: PortalSeedSpec) -> dict[str, str]:
    """Create the scenario if missing and return the credentials involved."""
    async with async_session_factory() as session:
        doctor = await _get_or_create_doctor(
            session, spec.doctor_name, spec.doctor_email, spec.doctor_password
        )
        await _get_or_create_code(session, doctor.id, spec.doctor_code)
        patient = await _get_or_create_patient(
            session, spec.patient_name, spec.patient_email, spec.patient_password
        )
        link = await _get_or_create_pending_link(session, doctor.id, patient.id)
        await session.commit()

        return {
            "doctor_id": str(doctor.id),
            "doctor_email": doctor.email or spec.doctor_email,
            "doctor_code": spec.doctor_code,
            "patient_id": str(patient.id),
            "patient_email": patient.email,
            "link_status": link.status,
        }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--doctor-name", default=DEFAULT_DOCTOR_NAME)
    parser.add_argument("--doctor-email", default=DEFAULT_DOCTOR_EMAIL)
    parser.add_argument("--doctor-password", default=DEFAULT_DOCTOR_PASSWORD)
    parser.add_argument("--doctor-code", default=DEFAULT_DOCTOR_CODE)
    parser.add_argument("--patient-name", default=DEFAULT_PATIENT_NAME)
    parser.add_argument("--patient-email", default=DEFAULT_PATIENT_EMAIL)
    parser.add_argument("--patient-password", default=DEFAULT_PATIENT_PASSWORD)
    arguments = parser.parse_args()

    if settings.is_production:
        raise SystemExit(PRODUCTION_GUARD_MESSAGE)

    summary = asyncio.run(seed_doctor_portal(PortalSeedSpec(arguments)))
    for key, value in summary.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
