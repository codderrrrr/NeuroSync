from datetime import UTC, datetime
from enum import StrEnum

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, String, text
from sqlalchemy.orm import Mapped, mapped_column

from neurosync.db.session import Base


class DoctorLinkStatus(StrEnum):
    """Lifecycle of a patient's link to a doctor."""

    PENDING = "pending"
    ACTIVE = "active"


_STATUS_SQL = ", ".join(f"'{status.value}'" for status in DoctorLinkStatus)
# Statuses that represent an existing relationship, used to block duplicates.
ACTIVE_LINK_STATUSES: tuple[str, ...] = tuple(status.value for status in DoctorLinkStatus)


class DoctorCode(Base):
    """A code a doctor shares with patients so they can request a link.

    Kept separate from the doctor record so codes can be rotated or deactivated
    without touching doctor identity.
    """

    __tablename__ = "doctor_codes"
    __table_args__ = (Index("ix_doctor_codes_doctor_id", "doctor_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    doctor_id: Mapped[int] = mapped_column(
        ForeignKey("doctors.id", ondelete="CASCADE"),
        nullable=False,
    )
    code: Mapped[str] = mapped_column(String(32), nullable=False, unique=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return f"<DoctorCode doctor_id={self.doctor_id} code={self.code}>"


class DoctorLink(Base):
    """A patient's request to be connected to a doctor.

    A link starts as ``pending`` and only the doctor it names can accept it, by
    posting to ``/doctor/patient-links/{link_id}/accept``. The partial unique
    index keeps the model open to many doctors per patient and many patients
    per doctor while preventing duplicate pending/active links for the same
    pair.
    """

    __tablename__ = "doctor_links"
    __table_args__ = (
        CheckConstraint(f"status IN ({_STATUS_SQL})", name="ck_doctor_links_status"),
        Index("ix_doctor_links_patient_id", "patient_id"),
        Index("ix_doctor_links_doctor_id", "doctor_id"),
        Index(
            "uq_doctor_links_active_pair",
            "patient_id",
            "doctor_id",
            unique=True,
            postgresql_where=text(f"status IN ({_STATUS_SQL})"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )
    doctor_id: Mapped[int] = mapped_column(
        ForeignKey("doctors.id", ondelete="CASCADE"),
        nullable=False,
    )
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=DoctorLinkStatus.PENDING.value,
    )
    # Derived information about acceptance, not a lifecycle authority: the
    # ``status`` column stays the single source of truth.
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return (
            f"<DoctorLink id={self.id} patient_id={self.patient_id} "
            f"doctor_id={self.doctor_id} status={self.status}>"
        )
