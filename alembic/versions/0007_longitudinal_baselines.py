"""Patient-specific longitudinal finger-tapping monitoring

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-03 00:00:00.000000

Adds the first longitudinal layer: each completed finger-tapping session is
compared against the patient's own historical baseline rather than against any
population reference.

- ``patient_baselines`` holds one row per patient and assessment: the medians
  of that patient's usable observations, how many produced them, and how much
  of the contributing history was borderline. It is a cache of a deterministic
  computation, reproducible from the stored ``monitoring_results`` rows.
- ``longitudinal_results`` holds exactly one row per session, mirroring
  ``monitoring_results``: the monitoring state reached, the usable history
  considered, the baseline it was judged against, and which features fell
  outside their tolerance.

Nothing here stores a clinical score, a diagnosis, or a severity stage.
"""

import sqlalchemy as sa

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "patient_baselines",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("assessment_definition_id", sa.Integer(), nullable=False),
        sa.Column("observation_count", sa.Integer(), nullable=False),
        sa.Column("valid_observation_count", sa.Integer(), nullable=False),
        sa.Column("borderline_observation_count", sa.Integer(), nullable=False),
        sa.Column("taps_per_second", sa.Float(), nullable=False),
        sa.Column("mean_inter_tap_interval_ms", sa.Integer(), nullable=False),
        sa.Column("inter_tap_variability_ms", sa.Integer(), nullable=False),
        sa.Column("longest_pause_ms", sa.Integer(), nullable=False),
        sa.Column("confidence", sa.String(length=16), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "confidence IN ('full', 'reduced')",
            name="ck_patient_baselines_confidence",
        ),
        sa.CheckConstraint(
            "observation_count >= 0",
            name="ck_patient_baselines_observation_count",
        ),
        sa.ForeignKeyConstraint(
            ["assessment_definition_id"],
            ["assessment_definitions.id"],
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "patient_id",
            "assessment_definition_id",
            name="uq_patient_baselines_patient_assessment",
        ),
    )
    op.create_index(
        "ix_patient_baselines_patient_id",
        "patient_baselines",
        ["patient_id"],
    )

    op.create_table(
        "longitudinal_results",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("session_id", sa.Integer(), nullable=False),
        sa.Column("baseline_id", sa.Integer(), nullable=True),
        sa.Column("state", sa.String(length=24), nullable=False),
        sa.Column("usable_history_count", sa.Integer(), nullable=False),
        sa.Column("baseline_confidence", sa.String(length=16), nullable=True),
        sa.Column("changed_features", sa.JSON(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "state IN ('insufficient_data', 'within_baseline', 'changed', 'unreliable')",
            name="ck_longitudinal_results_state",
        ),
        sa.CheckConstraint(
            "usable_history_count >= 0",
            name="ck_longitudinal_results_usable_history_count",
        ),
        sa.ForeignKeyConstraint(
            ["baseline_id"],
            ["patient_baselines.id"],
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["monitoring_sessions.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("session_id"),
    )
    op.create_index(
        "ix_longitudinal_results_session_id",
        "longitudinal_results",
        ["session_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_longitudinal_results_session_id", table_name="longitudinal_results")
    op.drop_table("longitudinal_results")
    op.drop_index("ix_patient_baselines_patient_id", table_name="patient_baselines")
    op.drop_table("patient_baselines")
