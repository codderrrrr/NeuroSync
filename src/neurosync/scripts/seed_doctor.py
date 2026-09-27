"""Create a development doctor and doctor code.

Doctor authentication and doctor management are out of scope for the patient
phase, so doctors cannot be created through the API yet. This script is the
only supported way to provision them, and it refuses to run in production so it
can never stand in for real doctor onboarding.

Usage:
    uv run python -m neurosync.scripts.seed_doctor [NAME] [CODE]
"""

import argparse
import asyncio

from sqlalchemy import select

from neurosync.config.settings import settings
from neurosync.db import Doctor, async_session_factory
from neurosync.modules.doctor_linking.models import DoctorCode

DEFAULT_DOCTOR_NAME = "Dr. Development"
DEFAULT_DOCTOR_CODE = "ABC123"
PRODUCTION_GUARD_MESSAGE = "Refusing to seed development data in a production environment."


async def seed_doctor(name: str, code: str) -> tuple[int, str]:
    """Create the doctor and code if they do not exist, and return them."""
    async with async_session_factory() as session:
        doctor = await session.scalar(select(Doctor).where(Doctor.name == name))
        if doctor is None:
            doctor = Doctor(name=name)
            session.add(doctor)
            await session.flush()

        doctor_code = await session.scalar(select(DoctorCode).where(DoctorCode.code == code))
        if doctor_code is None:
            doctor_code = DoctorCode(doctor_id=doctor.id, code=code, is_active=True)
            session.add(doctor_code)

        await session.commit()
        return doctor.id, code


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", nargs="?", default=DEFAULT_DOCTOR_NAME)
    parser.add_argument("code", nargs="?", default=DEFAULT_DOCTOR_CODE)
    arguments = parser.parse_args()

    if settings.is_production:
        raise SystemExit(PRODUCTION_GUARD_MESSAGE)

    doctor_id, code = asyncio.run(seed_doctor(arguments.name, arguments.code.strip().upper()))
    print(f"doctor_id={doctor_id} doctor_code={code}")  # noqa: T201


if __name__ == "__main__":
    main()
