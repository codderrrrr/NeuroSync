"""Patient authentication and doctor linking

Revision ID: 0002
Revises: 0001
Create Date: 2024-01-02 00:00:00.000000

Reshapes ``patients`` into a patient-owned identity record, adds the session
table, and introduces doctor codes and doctor links.

The ``patients`` table is empty at this revision (no patient-creating endpoint
has ever existed), so the new identity columns are added as NOT NULL. If rows
do exist the migration fails loudly rather than inventing credentials.
"""

import sqlalchemy as sa

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

_ACTIVE_STATUSES = "'pending', 'active'"


def upgrade() -> None:
    # Timestamps become timezone-aware so expiry and ordering comparisons are
    # unambiguous. Existing rows are interpreted as UTC.
    op.alter_column(
        "doctors",
        "created_at",
        existing_type=sa.DateTime(),
        type_=sa.DateTime(timezone=True),
        existing_nullable=False,
        postgresql_using="created_at AT TIME ZONE 'UTC'",
    )
    op.alter_column(
        "patients",
        "created_at",
        existing_type=sa.DateTime(),
        type_=sa.DateTime(timezone=True),
        existing_nullable=False,
        postgresql_using="created_at AT TIME ZONE 'UTC'",
    )

    # A patient owns their identity record. Medical record numbers and the
    # single primary-care-physician assignment move out of the patient: doctor
    # relationships are modelled by doctor_links instead.
    op.drop_column("patients", "primary_care_physician_id")
    op.drop_column("patients", "mrn")

    op.add_column("patients", sa.Column("email", sa.String(length=320), nullable=False))
    op.add_column(
        "patients",
        sa.Column("password_hash", sa.String(length=255), nullable=False),
    )
    op.add_column(
        "patients",
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column(
        "patients",
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    # `is_active` and `updated_at` are supplied by the application; the server
    # defaults only exist so the columns can be added without losing rows.
    op.alter_column("patients", "is_active", server_default=None)
    op.alter_column("patients", "updated_at", server_default=None)
    op.create_unique_constraint(None, "patients", ["email"])

    op.create_table(
        "patient_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index("ix_patient_sessions_patient_id", "patient_sessions", ["patient_id"])

    op.create_table(
        "doctor_codes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("doctor_id", sa.Integer(), nullable=False),
        sa.Column("code", sa.String(length=32), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctors.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("code"),
    )
    op.create_index("ix_doctor_codes_doctor_id", "doctor_codes", ["doctor_id"])

    op.create_table(
        "doctor_links",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("patient_id", sa.Integer(), nullable=False),
        sa.Column("doctor_id", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(f"status IN ({_ACTIVE_STATUSES})", name="ck_doctor_links_status"),
        sa.ForeignKeyConstraint(["patient_id"], ["patients.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctors.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_doctor_links_patient_id", "doctor_links", ["patient_id"])
    op.create_index("ix_doctor_links_doctor_id", "doctor_links", ["doctor_id"])
    # A patient may link to many doctors, but only one pending/active link per
    # doctor. Postgres enforces this, so a race cannot create duplicates.
    op.create_index(
        "uq_doctor_links_active_pair",
        "doctor_links",
        ["patient_id", "doctor_id"],
        unique=True,
        postgresql_where=sa.text(f"status IN ({_ACTIVE_STATUSES})"),
    )


def downgrade() -> None:
    op.drop_index("uq_doctor_links_active_pair", table_name="doctor_links")
    op.drop_index("ix_doctor_links_doctor_id", table_name="doctor_links")
    op.drop_index("ix_doctor_links_patient_id", table_name="doctor_links")
    op.drop_table("doctor_links")

    op.drop_index("ix_doctor_codes_doctor_id", table_name="doctor_codes")
    op.drop_table("doctor_codes")

    op.drop_index("ix_patient_sessions_patient_id", table_name="patient_sessions")
    op.drop_table("patient_sessions")

    op.drop_constraint("patients_email_key", "patients", type_="unique")
    op.drop_column("patients", "updated_at")
    op.drop_column("patients", "is_active")
    op.drop_column("patients", "password_hash")
    op.drop_column("patients", "email")

    op.add_column("patients", sa.Column("mrn", sa.String(length=50), nullable=True))
    op.add_column(
        "patients",
        sa.Column("primary_care_physician_id", sa.Integer(), nullable=True),
    )
    op.create_unique_constraint(None, "patients", ["mrn"])
    op.create_foreign_key(
        "patients_primary_care_physician_id_fkey",
        "patients",
        "doctors",
        ["primary_care_physician_id"],
        ["id"],
    )

    op.alter_column(
        "patients",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        type_=sa.DateTime(),
        existing_nullable=False,
        postgresql_using="created_at AT TIME ZONE 'UTC'",
    )
    op.alter_column(
        "doctors",
        "created_at",
        existing_type=sa.DateTime(timezone=True),
        type_=sa.DateTime(),
        existing_nullable=False,
        postgresql_using="created_at AT TIME ZONE 'UTC'",
    )
