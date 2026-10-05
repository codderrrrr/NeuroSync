"""Hold back spiral drawing and handwriting

Revision ID: 0011
Revises: 0010
Create Date: 2026-10-05 18:00:00.000000

Finger tapping and line tracing are the two tests a doctor may hand out today.
Spiral drawing and handwriting have runners, but they are held back until their
guides and settings are good enough to ask a patient to use, so
``is_supported`` is cleared for both.

``assessment_definitions`` is re-synced from the code catalog, exactly as
migration 0010 did. It is NeuroSync-owned reference data rather than patient
data, so re-syncing it is not a data loss.

Clearing the flag is what takes the test off every patient's plan: the plan read
path only returns items whose assessment is supported, so an existing assignment
stops being shown without its row -- or anything recorded against it -- being
touched.
"""

import sqlalchemy as sa

from alembic import op
from neurosync.modules.monitoring.assessment_catalog import ASSESSMENT_CATALOG

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None

# The two tests this revision holds back, and the value they had before it. The
# downgrade cannot re-derive these from the code catalog, because the catalog
# keeps saying ``False`` once this ships: reversing the decision is a statement
# about history, not about the current code.
_HELD_BACK_SLUGS = ("spiral_drawing", "handwriting")

_SYNC_CATALOG = sa.text(
    """
    UPDATE assessment_definitions
    SET title = :title,
        description = :description,
        instructions = :instructions,
        execution_type = :execution_type,
        default_duration_seconds = :default_duration_seconds,
        is_supported = :is_supported,
        updated_at = now()
    WHERE slug = :slug
    """
)


def _sync_catalog() -> None:
    """Re-sync every definition from the code's single source of truth."""
    for spec in ASSESSMENT_CATALOG:
        op.execute(
            _SYNC_CATALOG.bindparams(
                slug=spec.slug,
                title=spec.title,
                description=spec.description,
                instructions=spec.instructions,
                execution_type=spec.execution_type.value,
                default_duration_seconds=spec.default_duration_seconds,
                is_supported=spec.is_supported,
            )
        )


def upgrade() -> None:
    _sync_catalog()


def downgrade() -> None:
    # Put the two held-back tests back in front of any patient who still has
    # them assigned. This is deliberately not ``_sync_catalog``: the code
    # catalog still says ``False`` for both, so syncing here would leave them
    # disabled and make the downgrade a no-op.
    for slug in _HELD_BACK_SLUGS:
        op.execute(
            sa.text(
                """
                UPDATE assessment_definitions
                SET is_supported = true,
                    updated_at = now()
                WHERE slug = :slug
                """
            ).bindparams(slug=slug)
        )
