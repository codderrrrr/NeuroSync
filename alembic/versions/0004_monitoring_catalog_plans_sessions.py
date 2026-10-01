"""Assessment catalog, monitoring plans, sessions, and results

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-30 00:00:00.000000

Creates the monitoring domain:

- ``assessment_definitions``: the NeuroSync-owned assessment catalog, seeded
  from ``assessment_catalog.ASSESSMENT_CATALOG`` so code and database agree.
  ``is_supported`` records whether a runner exists; unsupported assessments
  stay visible but can never be assigned as patient tasks.
- ``monitoring_plans`` / ``monitoring_plan_items``: ordered test plans. A plan
  may later be owned by a doctor (``doctor_id`` is nullable until the doctor
  phase exists).
- ``monitoring_sessions`` / ``monitoring_session_events`` /
  ``monitoring_results``: one execution of a plan item, its raw event stream
  stored exactly as captured, and one derived, deterministic result row.
"""

import sqlalchemy as sa

from alembic import op
from neurosync.modules.monitoring.assessment_catalog import ASSESSMENT_CATALOG

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "assessment_definitions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("slug", sa.String(length=64), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("instructions", sa.Text(), nullable=False),
        sa.Column("execution_type", sa.String(length=32), nullable=False),
        sa.Column("default_duration_seconds", sa.Integer(), nullable=False),
        sa.Column("is_supported", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("slug"),
    )

    op.create_table(
        "monitoring_plans",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("doctor_id", sa.Integer(), nullable=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="draft"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "status IN ('draft', 'active', 'archived')",
            name="ck_monitoring_plans_status",
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctors.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_monitoring_plans_patient_id_status",
        "monitoring_plans",
        ["patient_id", "status"],
    )

    op.create_table(
        "monitoring_plan_items",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("plan_id", sa.Integer(), nullable=False),
        sa.Column("assessment_definition_id", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("position >= 0", name="ck_monitoring_plan_items_position"),
        sa.ForeignKeyConstraint(["plan_id"], ["monitoring_plans.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["assessment_definition_id"],
            ["assessment_definitions.id"],
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_monitoring_plan_items_plan_id_position",
        "monitoring_plan_items",
        ["plan_id", "position"],
    )

    op.create_table(
        "monitoring_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("plan_id", sa.Integer(), nullable=False),
        sa.Column("plan_item_id", sa.Integer(), nullable=False),
        sa.Column("assessment_definition_id", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="in_progress"),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('in_progress', 'completed')",
            name="ck_monitoring_sessions_status",
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["plan_id"], ["monitoring_plans.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["plan_item_id"], ["monitoring_plan_items.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["assessment_definition_id"],
            ["assessment_definitions.id"],
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_monitoring_sessions_patient_id_started_at",
        "monitoring_sessions",
        ["patient_id", "started_at"],
    )

    op.create_table(
        "monitoring_session_events",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("session_id", sa.Integer(), nullable=False),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column("offset_ms", sa.Integer(), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.CheckConstraint("offset_ms >= 0", name="ck_monitoring_session_events_offset"),
        sa.ForeignKeyConstraint(["session_id"], ["monitoring_sessions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_monitoring_session_events_session_id_offset",
        "monitoring_session_events",
        ["session_id", "offset_ms"],
    )

    op.create_table(
        "monitoring_results",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("session_id", sa.Integer(), nullable=False),
        sa.Column("total_taps", sa.Integer(), nullable=False),
        sa.Column("duration_ms", sa.Integer(), nullable=False),
        sa.Column("mean_inter_tap_interval_ms", sa.Integer(), nullable=False),
        sa.Column("inter_tap_variability_ms", sa.Integer(), nullable=False),
        sa.Column("longest_pause_ms", sa.Integer(), nullable=False),
        sa.Column("taps_per_second", sa.Float(), nullable=False),
        sa.Column("quality", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "quality IN ('valid', 'borderline', 'invalid', 'incomplete')",
            name="ck_monitoring_results_quality",
        ),
        sa.CheckConstraint("total_taps >= 0", name="ck_monitoring_results_total_taps"),
        sa.CheckConstraint("duration_ms >= 0", name="ck_monitoring_results_duration_ms"),
        sa.ForeignKeyConstraint(["session_id"], ["monitoring_sessions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("session_id"),
    )

    # Seed the catalog from the code's single source of truth. Additive only:
    # re-running the migration (fresh database) or re-seeding later never
    # edits existing rows.
    for spec in ASSESSMENT_CATALOG:
        op.execute(
            sa.text(
                """
                INSERT INTO assessment_definitions
                    (slug, title, description, instructions, execution_type,
                     default_duration_seconds, is_supported, created_at, updated_at)
                VALUES (:slug, :title, :description, :instructions, :execution_type,
                        :default_duration_seconds, :is_supported, now(), now())
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
    op.drop_table("monitoring_results")
    op.drop_table("monitoring_session_events")
    op.drop_table("monitoring_sessions")
    op.drop_table("monitoring_plan_items")
    op.drop_table("monitoring_plans")
    op.drop_table("assessment_definitions")
