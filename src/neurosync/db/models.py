from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from neurosync.db.session import Base


class Doctor(Base):
    __tablename__ = "doctors"

    id = Column(Integer, primary_key=True)
    name = Column(String(200), nullable=False, unique=True)
    created_at = Column(DateTime, nullable=False, default=lambda: datetime.now(UTC))

    patients = relationship("Patient", back_populates="primary_care_physician")

    def __repr__(self) -> str:
        return f"<Doctor id={self.id} name={self.name}>"


class Patient(Base):
    __tablename__ = "patients"

    id = Column(Integer, primary_key=True)
    mrn = Column(String(50), nullable=False, unique=True, comment="Medical Record Number")
    name = Column(String(200), nullable=False)
    created_at = Column(
        DateTime,
        nullable=False,
        default=lambda: datetime.now(UTC),
    )
    primary_care_physician_id = Column(Integer, ForeignKey("doctors.id"), nullable=False)

    primary_care_physician = relationship("Doctor", back_populates="patients")

    def __repr__(self) -> str:
        return f"<Patient id={self.id} mrn={self.mrn} name={self.name}>"
