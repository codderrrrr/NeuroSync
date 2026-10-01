"""Persistence for doctor portal sessions.

Doctor sessions mirror ``patient_sessions`` (opaque token, only the hash
stored, revocation and expiry) but are a separate table on purpose: a patient
session token must never authenticate a doctor, and revoking one kind of
session must never affect the other.
"""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from neurosync.db.session import Base


class DoctorSession(Base):
    """An opaque session token issued to a signed-in doctor.

    Only the hash of the token is persisted, so a database leak does not
    expose usable session tokens.
    """

    __tablename__ = "doctor_sessions"
    __table_args__ = (Index("ix_doctor_sessions_doctor_id", "doctor_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    doctor_id: Mapped[int] = mapped_column(
        ForeignKey("doctors.id", ondelete="CASCADE"),
        nullable=False,
    )
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    def __repr__(self) -> str:
        return f"<DoctorSession id={self.id} doctor_id={self.doctor_id}>"
