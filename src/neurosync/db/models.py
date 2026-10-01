from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from neurosync.db.session import Base


class Doctor(Base):
    """A clinician who patients can request a link to.

    Identity and credentials support signing in to the doctor web portal.
    ``email`` and ``password_hash`` are nullable because doctors provisioned
    before the portal existed (development seeds) remain valid records; they
    simply cannot sign in until a password is set for them.
    """

    __tablename__ = "doctors"
    __table_args__ = (Index("ix_doctors_email", "email"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, unique=True)
    email: Mapped[str | None] = mapped_column(String(320), nullable=True, unique=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return f"<Doctor id={self.id} name={self.name}>"
