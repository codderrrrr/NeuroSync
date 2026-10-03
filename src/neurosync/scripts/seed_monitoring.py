"""Seed the deterministic development monitoring data.

A doctor assigns plans through the portal at
``/doctor/patients/{patient_id}/assignments``. This script provisions the same
default plan ("Daily motor check-in") for development patients directly, so a
local patient has a plan without a doctor account.

Seeding is idempotent and additive:
- the assessment catalog is topped up from the code catalog;
- every named patient without an active plan receives the default plan.

The script refuses to run in production, like ``seed_doctor``.

Usage:
    uv run python -m neurosync.scripts.seed_monitoring [EMAIL ...]

With no arguments it seeds the default plan for every patient that has none.
"""

import argparse
import asyncio

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.config.settings import settings
from neurosync.db import async_session_factory
from neurosync.modules.auth.models import Patient
from neurosync.modules.monitoring import service
from neurosync.modules.monitoring.assessment_catalog import SUPPORTED_ASSESSMENT_SLUGS
from neurosync.modules.monitoring.models import MonitoringPlan, PlanStatus

DEFAULT_PLAN_TITLE = "Daily motor check-in"

PRODUCTION_GUARD_MESSAGE = "Refusing to seed development data in a production environment."


class UnknownPatientsError(SystemExit):
    """Raised when a named patient account does not exist."""

    def __init__(self, emails: list[str]) -> None:
        super().__init__(f"No patient account(s) for: {', '.join(emails)}")


async def seed_monitoring(
    session: AsyncSession,
    emails: list[str] | None = None,
) -> list[int]:
    """Seed the catalog and default plans; return the affected patient ids."""
    await service.seed_assessment_catalog(session)

    patients: list[Patient]
    if emails:
        patients = list(
            await session.scalars(
                select(Patient).where(Patient.email.in_(email.strip().lower() for email in emails))
            )
        )
        found_emails = {patient.email for patient in patients}
        requested = {email.strip().lower() for email in emails}
        missing = sorted(requested - found_emails)
        if missing:
            raise UnknownPatientsError(missing)
    else:
        patients = list(await session.scalars(select(Patient)))

    definition_ids = []
    for slug in SUPPORTED_ASSESSMENT_SLUGS:
        definition = await service.get_assessment_definition(session, slug=slug)
        if definition is not None:
            definition_ids.append(definition.id)

    seeded: list[int] = []
    for patient in patients:
        has_active_plan = await session.scalar(
            select(MonitoringPlan.id).where(
                MonitoringPlan.patient_id == patient.id,
                MonitoringPlan.status == PlanStatus.ACTIVE.value,
            )
        )
        if has_active_plan is not None:
            continue
        await service.create_plan(
            session=session,
            patient_id=patient.id,
            title=DEFAULT_PLAN_TITLE,
            assessment_definition_ids=definition_ids,
            status=PlanStatus.ACTIVE,
        )
        seeded.append(patient.id)

    return seeded


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "emails",
        nargs="*",
        help="Patient emails to seed; omit to seed every patient without a plan",
    )
    arguments = parser.parse_args()

    if settings.is_production:
        raise SystemExit(PRODUCTION_GUARD_MESSAGE)

    async def run() -> list[int]:
        async with async_session_factory() as session:
            return await seed_monitoring(session, arguments.emails or None)

    seeded = asyncio.run(run())
    for patient_id in seeded:
        print(f"seeded default plan for patient_id={patient_id}")
    if not seeded:
        print("nothing to seed; every patient already has an active plan")


if __name__ == "__main__":
    main()
