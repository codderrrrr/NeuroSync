"""Doctor-assigned exercise durations

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-01 00:00:00.000000

Lets a doctor's assignment control how long a recording should run:

- ``monitoring_plan_items`` gains ``duration_seconds`` (nullable). When set it
  overrides the assessment's catalog default for that item only; when null the
  default applies, so pre-existing plans and the patient app keep behaving
  exactly as before.
"""

import sqlalchemy as sa

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "monitoring_plan_items",
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
    )
    op.create_check_constraint(
        "ck_monitoring_plan_items_duration",
        "monitoring_plan_items",
        "duration_seconds IS NULL OR duration_seconds > 0",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_monitoring_plan_items_duration",
        "monitoring_plan_items",
        type_="check",
    )
    op.drop_column("monitoring_plan_items", "duration_seconds")
