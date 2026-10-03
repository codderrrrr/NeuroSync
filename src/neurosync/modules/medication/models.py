"""Persistence models for the medication domain.

Deliberately minimal. A ``Medication`` is what the patient or their care team
reported they take, recorded as free text exactly as entered. A
``MedicationEvent`` is one report about whether and when a dose was taken.

Nothing here is parsed, inferred, or interpreted. Dose and frequency are opaque
labels, not numbers the system reasons about, and the absence of a timestamp
stays an absence rather than becoming a guess.
"""

from datetime import UTC, datetime
from enum import StrEnum

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from neurosync.db.session import Base, sql_values


class MedicationAdherence(StrEnum):
    """What the patient reported about a dose.

    ``NOT_SURE`` is a first-class answer, not a missing value: it records that
    the patient could not tell, which is different from them reporting nothing.
    """

    TAKEN = "taken"
    NOT_TAKEN = "not_taken"
    NOT_SURE = "not_sure"


class MedicationContext(StrEnum):
    """Where an assessment fell relative to a reported dose.

    ``UNKNOWN`` is the honest default and is never widened into a window. A
    missing timestamp, a "not sure" report, an inactive medication, or no
    associated event at all all resolve to ``UNKNOWN`` rather than to a
    plausible-looking assumption.
    """

    BEFORE_MEDICATION = "before_medication"
    RECENTLY_AFTER_MEDICATION = "recently_after_medication"
    LATER_AFTER_MEDICATION = "later_after_medication"
    UNKNOWN = "unknown"


class EvidenceStrength(StrEnum):
    """How much supporting information stands behind an interpretation.

    This is a description of how much was recorded, not a probability. It never
    renders as a percentage and never claims to be medically validated.
    """

    INSUFFICIENT = "insufficient"
    LIMITED = "limited"
    MODERATE = "moderate"
    STRONGER = "stronger"


class Medication(Base):
    """A medication the patient reports taking.

    ``dose_label`` and ``frequency_label`` are free text exactly as entered by
    the patient or their care team. They are stored verbatim and never parsed
    into numbers, because interpreting a dose is a clinical task this system
    does not perform.
    """

    __tablename__ = "medications"
    __table_args__ = (
        CheckConstraint("length(btrim(name)) > 0", name="ck_medications_name_present"),
        Index("ix_medications_patient_id", "patient_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    # Verbatim as reported. Null when the patient did not state one.
    dose_label: Mapped[str | None] = mapped_column(String(100), nullable=True)
    frequency_label: Mapped[str | None] = mapped_column(String(100), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
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
        return f"<Medication id={self.id} patient_id={self.patient_id} name={self.name!r}>"


class MedicationEvent(Base):
    """One report about a dose: expected, and possibly taken.

    ``scheduled_at`` is when the dose was expected; ``taken_at`` is when the
    patient says they actually took it. Both are nullable and both are
    patient-reported. A ``not_taken`` or ``not_sure`` report normally leaves
    ``taken_at`` empty, and that absence is what keeps the derived medication
    context unknown rather than guessed.
    """

    __tablename__ = "medication_events"
    __table_args__ = (
        CheckConstraint(
            f"adherence IN ({sql_values(MedicationAdherence)})",
            name="ck_medication_events_adherence",
        ),
        # Taken at or after scheduled would be nonsense for a "taken" report.
        CheckConstraint(
            "taken_at IS NULL OR scheduled_at IS NULL "
            "OR taken_at >= scheduled_at - interval '1 day'",
            name="ck_medication_events_taken_not_before_scheduled",
        ),
        Index("ix_medication_events_patient_id_recorded_at", "patient_id", "recorded_at"),
        Index("ix_medication_events_medication_id", "medication_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    # Denormalised from the medication so ownership checks never need a join,
    # and so a medication can never be attached to another patient's session.
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )
    medication_id: Mapped[int] = mapped_column(
        ForeignKey("medications.id", ondelete="CASCADE"),
        nullable=False,
    )
    scheduled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    taken_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    adherence: Mapped[str] = mapped_column(String(16), nullable=False)
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    # Loaded eagerly wherever events are listed, so a history page resolves
    # medication names without a query per row.
    medication: Mapped["Medication"] = relationship(lazy="selectin")

    def __repr__(self) -> str:
        return (
            f"<MedicationEvent id={self.id} patient_id={self.patient_id} "
            f"medication_id={self.medication_id} adherence={self.adherence}>"
        )
