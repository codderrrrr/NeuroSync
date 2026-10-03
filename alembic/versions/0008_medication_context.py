"""Medication schedule, events, and medication-aware monitoring context

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-04 00:00:00.000000

Adds patient-reported medication context to the longitudinal monitoring layer.

- ``medications`` is what the patient reports taking. ``dose_label`` and
  ``frequency_label`` are stored verbatim as free text and are never parsed or
  interpreted.
- ``medication_events`` is one report about a dose: when it was expected, and
  when it was actually taken. Both timestamps are nullable, and a ``not_taken``
  or ``not_sure`` report normally leaves ``taken_at`` empty.
- ``longitudinal_results`` gains the medication context for the session, the
  associated event, the elapsed minutes, and how much supporting information
  stood behind the interpretation.

Every new column is nullable or defaulted, so sessions recorded before this
migration keep their existing meaning and no historical observation is
discarded for lacking medication context. ``medication_context`` defaults to
``unknown`` rather than to any window.
"""

import sqlalchemy as sa

from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "medications",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("dose_label", sa.String(length=100), nullable=True),
        sa.Column("frequency_label", sa.String(length=100), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
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
            "length(btrim(name)) > 0",
            name="ck_medications_name_present",
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_medications_patient_id", "medications", ["patient_id"])

    op.create_table(
        "medication_events",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("medication_id", sa.Integer(), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("taken_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("adherence", sa.String(length=16), nullable=False),
        sa.Column(
            "recorded_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "adherence IN ('taken', 'not_taken', 'not_sure')",
            name="ck_medication_events_adherence",
        ),
        sa.CheckConstraint(
            "taken_at IS NULL OR scheduled_at IS NULL "
            "OR taken_at >= scheduled_at - interval '1 day'",
            name="ck_medication_events_taken_not_before_scheduled",
        ),
        sa.ForeignKeyConstraint(["medication_id"], ["medications.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_medication_events_patient_id_recorded_at",
        "medication_events",
        ["patient_id", "recorded_at"],
    )
    op.create_index(
        "ix_medication_events_medication_id",
        "medication_events",
        ["medication_id"],
    )

    op.add_column(
        "longitudinal_results",
        sa.Column("medication_event_id", sa.Integer(), nullable=True),
    )
    op.add_column(
        "longitudinal_results",
        sa.Column(
            "medication_context",
            sa.String(length=32),
            nullable=False,
            server_default="unknown",
        ),
    )
    op.add_column(
        "longitudinal_results",
        sa.Column("minutes_since_medication", sa.Integer(), nullable=True),
    )
    op.add_column(
        "longitudinal_results",
        sa.Column(
            "evidence_strength",
            sa.String(length=16),
            nullable=False,
            server_default="insufficient",
        ),
    )
    op.add_column(
        "longitudinal_results",
        sa.Column(
            "comparable_observation_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.create_foreign_key(
        "fk_longitudinal_results_medication_event",
        "longitudinal_results",
        "medication_events",
        ["medication_event_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_check_constraint(
        "ck_longitudinal_results_medication_context",
        "longitudinal_results",
        "medication_context IN "
        "('before_medication', 'recently_after_medication', "
        "'later_after_medication', 'unknown')",
    )
    op.create_check_constraint(
        "ck_longitudinal_results_evidence_strength",
        "longitudinal_results",
        "evidence_strength IN ('insufficient', 'limited', 'moderate', 'stronger')",
    )
    op.create_check_constraint(
        "ck_longitudinal_results_minutes_since_medication",
        "longitudinal_results",
        "minutes_since_medication IS NULL OR minutes_since_medication >= 0",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_longitudinal_results_minutes_since_medication",
        "longitudinal_results",
        type_="check",
    )
    op.drop_constraint(
        "ck_longitudinal_results_evidence_strength",
        "longitudinal_results",
        type_="check",
    )
    op.drop_constraint(
        "ck_longitudinal_results_medication_context",
        "longitudinal_results",
        type_="check",
    )
    op.drop_constraint(
        "fk_longitudinal_results_medication_event",
        "longitudinal_results",
        type_="foreignkey",
    )
    op.drop_column("longitudinal_results", "comparable_observation_count")
    op.drop_column("longitudinal_results", "evidence_strength")
    op.drop_column("longitudinal_results", "minutes_since_medication")
    op.drop_column("longitudinal_results", "medication_context")
    op.drop_column("longitudinal_results", "medication_event_id")

    op.drop_index("ix_medication_events_medication_id", table_name="medication_events")
    op.drop_index(
        "ix_medication_events_patient_id_recorded_at",
        table_name="medication_events",
    )
    op.drop_table("medication_events")
    op.drop_index("ix_medications_patient_id", table_name="medications")
    op.drop_table("medications")
