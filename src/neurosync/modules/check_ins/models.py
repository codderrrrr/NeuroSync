from datetime import UTC, datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from neurosync.db.session import Base

# Patient-reported severity anchors: 0 = not present, 4 = severe.
SEVERITY_MIN = 0
SEVERITY_MAX = 4
_SEVERITY_RANGE_SQL = f"BETWEEN {SEVERITY_MIN} AND {SEVERITY_MAX}"


class CheckIn(Base):
    """A patient's self-reported symptom check-in.

    Each rating is the patient's own observation at ``recorded_at``. The rows
    are stored exactly as reported: no scores, trends, or interpretations are
    derived here, because drawing clinical conclusions is explicitly outside
    this module's scope.
    """

    __tablename__ = "check_ins"
    __table_args__ = (
        CheckConstraint(f"tremor {_SEVERITY_RANGE_SQL}", name="ck_check_ins_tremor"),
        CheckConstraint(f"stiffness {_SEVERITY_RANGE_SQL}", name="ck_check_ins_stiffness"),
        CheckConstraint(f"slowness {_SEVERITY_RANGE_SQL}", name="ck_check_ins_slowness"),
        CheckConstraint(f"balance {_SEVERITY_RANGE_SQL}", name="ck_check_ins_balance"),
        # Serves both "this patient's check-ins" filters and the
        # recorded_at ordering used by the history list.
        Index("ix_check_ins_patient_id_recorded_at", "patient_id", "recorded_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    tremor: Mapped[int] = mapped_column(Integer, nullable=False)
    stiffness: Mapped[int] = mapped_column(Integer, nullable=False)
    slowness: Mapped[int] = mapped_column(Integer, nullable=False)
    balance: Mapped[int] = mapped_column(Integer, nullable=False)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return f"<CheckIn id={self.id} patient_id={self.patient_id} recorded_at={self.recorded_at}>"
