"""Canvas assessments, per-item parameters, and assignment editing

Revision ID: 0010
Revises: 0009
Create Date: 2026-10-05 12:00:00.000000

Makes the three canvas assessments executable and gives every assignment the
settings a doctor can change about it.

- ``assessment_definitions`` is re-synced from the code catalog, so
  ``spiral_drawing``, ``line_tracing`` and ``handwriting`` become supported and
  their instructions drop the "not available yet" wording. The catalog is
  NeuroSync-owned reference data, so re-syncing it is not a data loss.

- ``monitoring_plan_items.parameters`` stores what the doctor set besides the
  recording length: which hand and finger, how fast to move, how many turns or
  repetitions, the phrase to write. The keys, bounds and defaults live in
  ``assessment_catalog``; this column only holds a validated set of them.

- ``monitoring_results`` gains the canvas feature columns and its tap columns
  become nullable, because one row now holds either a tap recording or a canvas
  recording. ``duration_ms`` and ``longest_pause_ms`` mean the same thing for
  both and stay required. A check constraint keeps the two shapes exclusive, so
  a row can never claim to be both or neither.
"""

import sqlalchemy as sa

from alembic import op
from neurosync.modules.monitoring.assessment_catalog import ASSESSMENT_CATALOG

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "monitoring_plan_items",
        sa.Column("parameters", sa.JSON(), nullable=True),
    )

    for column in (
        "total_taps",
        "mean_inter_tap_interval_ms",
        "inter_tap_variability_ms",
        "taps_per_second",
    ):
        op.alter_column("monitoring_results", column, nullable=True)

    op.add_column(
        "monitoring_results",
        sa.Column("total_points", sa.Integer(), nullable=True),
    )
    op.add_column(
        "monitoring_results",
        sa.Column("stroke_count", sa.Integer(), nullable=True),
    )
    op.add_column(
        "monitoring_results",
        sa.Column("path_length", sa.Float(), nullable=True),
    )
    op.add_column(
        "monitoring_results",
        sa.Column("mean_speed_px_per_second", sa.Float(), nullable=True),
    )
    op.add_column(
        "monitoring_results",
        sa.Column("peak_speed_px_per_second", sa.Float(), nullable=True),
    )
    op.add_column(
        "monitoring_results",
        sa.Column("path_efficiency", sa.Float(), nullable=True),
    )
    op.create_check_constraint(
        "ck_monitoring_results_single_execution_type",
        "monitoring_results",
        "(total_taps IS NULL) <> (total_points IS NULL)",
    )

    # Re-sync the catalog from the code's single source of truth. The catalog
    # is reference data NeuroSync owns rather than patient data, so the same
    # UPDATE that migration 0004's INSERT performed is safe to repeat.
    for spec in ASSESSMENT_CATALOG:
        op.execute(
            sa.text(
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
            ).bindparams(
                slug=spec.slug,
                title=spec.title,
                description=spec.description,
                instructions=spec.instructions,
                execution_type=spec.execution_type.value,
                default_duration_seconds=spec.default_duration_seconds,
                is_supported=spec.is_supported,
            )
        )


def downgrade() -> None:
    # A canvas recording has no representation before 0010. Rather than
    # silently rewriting one into a tap recording it never was, the downgrade
    # refuses while any exist and the operator decides what to do with them.
    # This has to run first, before the ``total_points`` column below is
    # dropped, or the check cannot see it.
    op.execute(
        sa.text(
            """
            DO $$
            BEGIN
                IF EXISTS (SELECT 1 FROM monitoring_results WHERE total_points IS NOT NULL) THEN
                    RAISE EXCEPTION
                        'canvas recordings exist; export or delete them before '
                        'downgrading to 0009';
                END IF;
            END $$
            """
        )
    )

    op.drop_constraint(
        "ck_monitoring_results_single_execution_type",
        "monitoring_results",
        type_="check",
    )
    for column in (
        "path_efficiency",
        "peak_speed_px_per_second",
        "mean_speed_px_per_second",
        "path_length",
        "stroke_count",
        "total_points",
    ):
        op.drop_column("monitoring_results", column)

    op.alter_column("monitoring_results", "total_taps", nullable=False)
    op.alter_column("monitoring_results", "mean_inter_tap_interval_ms", nullable=False)
    op.alter_column("monitoring_results", "inter_tap_variability_ms", nullable=False)
    op.alter_column("monitoring_results", "taps_per_second", nullable=False)
    op.drop_column("monitoring_plan_items", "parameters")

    for spec in ASSESSMENT_CATALOG:
        op.execute(
            sa.text(
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
            ).bindparams(
                slug=spec.slug,
                title=spec.title,
                description=spec.description,
                instructions=spec.instructions,
                execution_type=spec.execution_type.value,
                default_duration_seconds=spec.default_duration_seconds,
                is_supported=spec.is_supported,
            )
        )
