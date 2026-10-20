"""Catalog service: the assessment definitions and how they are rendered.

The catalog is NeuroSync-owned reference data. The code in
``assessment_catalog`` is its source of truth; the database holds a copy that
the migrations seed, and this service reads and renders it.
"""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from neurosync.modules.monitoring.assessment_catalog import ASSESSMENT_CATALOG, get_spec
from neurosync.modules.monitoring.models import AssessmentDefinition
from neurosync.modules.monitoring.schemas import AssessmentResponse, parameter_responses


async def get_assessment_catalog(session: AsyncSession) -> list[AssessmentDefinition]:
    """Return all catalog entries in a stable, seeded order."""
    statement = select(AssessmentDefinition).order_by(AssessmentDefinition.id)
    return list(await session.scalars(statement))


async def get_assessment_definition(
    session: AsyncSession,
    *,
    slug: str,
) -> AssessmentDefinition | None:
    """Return one catalog entry by slug, or ``None``."""
    return await session.scalar(
        select(AssessmentDefinition).where(AssessmentDefinition.slug == slug)
    )


async def seed_assessment_catalog(session: AsyncSession) -> None:
    """Insert any catalog entries missing from the database.

    The code catalog is authoritative; seeding is additive so re-running never
    edits or removes existing rows (patients may reference them).
    """
    existing_slugs = set(await session.scalars(select(AssessmentDefinition.slug)))
    for spec in ASSESSMENT_CATALOG:
        if spec.slug in existing_slugs:
            continue
        session.add(
            AssessmentDefinition(
                slug=spec.slug,
                title=spec.title,
                description=spec.description,
                instructions=spec.instructions,
                execution_type=spec.execution_type.value,
                default_duration_seconds=spec.default_duration_seconds,
                is_supported=spec.is_supported,
            )
        )
    await session.commit()


def assessment_response(definition: AssessmentDefinition) -> AssessmentResponse:
    """Render one catalog row, including what a doctor may change about it."""
    spec = get_spec(definition.slug)
    return AssessmentResponse(
        id=definition.id,
        slug=definition.slug,
        title=definition.title,
        description=definition.description,
        instructions=definition.instructions,
        execution_type=definition.execution_type,
        default_duration_seconds=definition.default_duration_seconds,
        is_supported=definition.is_supported,
        parameters=[] if spec is None else parameter_responses(spec),
    )
