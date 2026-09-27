from datetime import UTC, datetime

from sqlalchemy import DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from neurosync.db.session import Base


class Doctor(Base):
    """A clinician who patients can request a link to.

    Doctor authentication and management are not implemented yet. Doctors are
    provisioned through the development seed script until the doctor-facing
    phase is built.
    """

    __tablename__ = "doctors"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return f"<Doctor id={self.id} name={self.name}>"
