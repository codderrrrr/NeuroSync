"""Specialist review exceptions

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-05 00:00:00.000000

Adds the specialist review queue that the longitudinal layer routes into.

- ``review_exceptions`` records that one observation met a configured routing
  rule. It stores the decision - type, rule, rationale, and the count of
  observations that justified it - and points at the ``longitudinal_results``
  row it came from. No motor data is copied: state, evidence strength, changed
  features and medication context stay on the longitudinal result and are read
  at query time, so the queue cannot drift from the observation.

- ``longitudinal_result_id`` is UNIQUE. That is the duplicate-prevention
  guarantee, enforced by the database rather than by application logic: one
  longitudinal result can produce at most one exception, so reprocessing a
  session cannot enqueue copies of itself.

- Review state is three explicit statuses (``open``, ``reviewed``,
  ``dismissed``) with the reviewing doctor, the review time and the doctor's
  own note. A check constraint keeps an open exception from claiming it has a
  reviewer.

``review_exceptions`` is not surfaced to patients at all; exception-routing
terminology is internal, and the patient's monitoring result remains their
experience.
"""

import sqlalchemy as sa

from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None

_EXCEPTION_TYPES = "'persistent_change', 'contextual_change', 'review_requested'"
_ROUTING_RULES = "'repeated_change', 'context_corroborated_change', 'supported_single_change'"
_STATUSES = "'open', 'reviewed', 'dismissed'"


def upgrade() -> None:
    op.create_table(
        "review_exceptions",
        sa.Column("id", sa.Integer(), nullable=False),
        # UNIQUE: at most one originating exception per longitudinal result.
        sa.Column("longitudinal_result_id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("exception_type", sa.String(length=32), nullable=False),
        sa.Column("routing_rule", sa.String(length=40), nullable=False),
        sa.Column("rationale", sa.String(length=500), nullable=False),
        sa.Column("supporting_observations", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("reviewed_by_doctor_id", sa.Integer(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("review_note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            f"exception_type IN ({_EXCEPTION_TYPES})",
            name="ck_review_exceptions_type",
        ),
        sa.CheckConstraint(
            f"routing_rule IN ({_ROUTING_RULES})",
            name="ck_review_exceptions_routing_rule",
        ),
        sa.CheckConstraint(
            f"status IN ({_STATUSES})",
            name="ck_review_exceptions_status",
        ),
        sa.CheckConstraint(
            "supporting_observations >= 0",
            name="ck_review_exceptions_supporting_observations",
        ),
        sa.CheckConstraint(
            "(status = 'open') = (reviewed_by_doctor_id IS NULL)",
            name="ck_review_exceptions_review_state_consistent",
        ),
        sa.ForeignKeyConstraint(
            ["longitudinal_result_id"],
            ["longitudinal_results.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["reviewed_by_doctor_id"],
            ["doctors.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("longitudinal_result_id"),
    )
    op.create_index(
        "ix_review_exceptions_created_at",
        "review_exceptions",
        ["created_at"],
        unique=False,
    )
    op.create_index(
        "ix_review_exceptions_doctor_queue",
        "review_exceptions",
        ["patient_id", "status", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_review_exceptions_doctor_queue", table_name="review_exceptions")
    op.drop_index("ix_review_exceptions_created_at", table_name="review_exceptions")
    op.drop_table("review_exceptions")
