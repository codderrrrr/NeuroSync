"""Doctor authentication and link acceptance

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-01 00:00:00.000000

Introduces the doctor-facing phase:

- ``doctors`` gains identity and credential columns so a doctor can sign in to
  the web portal. Columns are nullable because the existing seeded doctors
  (provisioned before authentication existed) must keep working; they simply
  cannot sign in until a password is provisioned for them.
- ``doctor_links`` gains ``accepted_at`` so an accepted link records when the
  doctor accepted the patient. Backwards-compatible: ``accepted_at`` is
  derived information, not a status authority -- ``status`` remains the single
  source of truth for the link lifecycle.
- ``doctor_sessions`` stores portal sessions: an opaque token whose hash only
  is persisted, with expiry and revocation, mirroring ``patient_sessions``.
  Patient and doctor sessions are separate tables so neither kind of token can
  ever authenticate the other role.
"""

import sqlalchemy as sa

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("doctors", sa.Column("email", sa.String(length=320), nullable=True))
    op.add_column(
        "doctors",
        sa.Column("password_hash", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "doctors",
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    # `is_active` is supplied by the application; the server default only
    # exists so the column can be added to a populated table.
    op.alter_column("doctors", "is_active", server_default=None)
    op.create_unique_constraint("doctors_email_key", "doctors", ["email"])
    op.create_index("ix_doctors_email", "doctors", ["email"])

    op.add_column(
        "doctor_links",
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "doctor_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("doctor_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctors.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index("ix_doctor_sessions_doctor_id", "doctor_sessions", ["doctor_id"])


def downgrade() -> None:
    op.drop_index("ix_doctor_sessions_doctor_id", table_name="doctor_sessions")
    op.drop_table("doctor_sessions")

    op.drop_column("doctor_links", "accepted_at")

    op.drop_index("ix_doctors_email", table_name="doctors")
    op.drop_constraint("doctors_email_key", "doctors", type_="unique")
    op.drop_column("doctors", "is_active")
    op.drop_column("doctors", "password_hash")
    op.drop_column("doctors", "email")
