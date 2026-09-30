"""Patient symptom check-ins

Revision ID: 0003
Revises: 0002
Create Date: 2026-06-19 00:00:00.000000

Adds ``check_ins``: patient-reported motor symptom severity (each 0-4) with an
optional note and a timezone-aware ``recorded_at``. Rows are raw observations
only; no scores or interpretations are stored.

The severity CHECK constraints mirror the Pydantic boundary validation so an
out-of-range rating cannot enter the database through any path.
"""

import sqlalchemy as sa

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "check_ins",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("tremor", sa.Integer(), nullable=False),
        sa.Column("stiffness", sa.Integer(), nullable=False),
        sa.Column("slowness", sa.Integer(), nullable=False),
        sa.Column("balance", sa.Integer(), nullable=False),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("tremor BETWEEN 0 AND 4", name="ck_check_ins_tremor"),
        sa.CheckConstraint("stiffness BETWEEN 0 AND 4", name="ck_check_ins_stiffness"),
        sa.CheckConstraint("slowness BETWEEN 0 AND 4", name="ck_check_ins_slowness"),
        sa.CheckConstraint("balance BETWEEN 0 AND 4", name="ck_check_ins_balance"),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_check_ins_patient_id_recorded_at",
        "check_ins",
        ["patient_id", "recorded_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_check_ins_patient_id_recorded_at", table_name="check_ins")
    op.drop_table("check_ins")
