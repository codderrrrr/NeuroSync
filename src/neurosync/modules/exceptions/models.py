"""Persistence for the specialist review queue.

A ``ReviewException`` is a *routing record*, not a clinical finding: it says
this observation met a configured rule and a specialist has not looked at it
yet. It therefore stores the decision (type, rule, rationale, supporting count)
and points at the longitudinal result that produced it.

It deliberately does **not** copy motor data. The state, evidence strength,
changed features and medication context all live on ``longitudinal_results``
and are read at query time, so the queue can never drift from the observation
it points at.
"""

from datetime import UTC, datetime
from enum import StrEnum

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from neurosync.db.session import Base, sql_values
from neurosync.modules.exceptions.routing import ExceptionType, RoutingRule
from neurosync.modules.monitoring.models import LongitudinalResult


class ExceptionStatus(StrEnum):
    """Where an exception sits in the reviewer's workflow.

    Three states, deliberately. ``OPEN`` means nobody has looked yet;
    ``REVIEWED`` means a doctor examined the evidence and recorded an outcome;
    ``DISMISSED`` means a doctor examined it and judged it needed no further
    action right now. Both closed states record *who* and *when*, and they are
    the doctor's words, not the system's.
    """

    OPEN = "open"
    REVIEWED = "reviewed"
    DISMISSED = "dismissed"


#: Statuses a doctor can set by acting on an exception. ``OPEN`` is the
#: arrival state, not an outcome a reviewer chooses.
REVIEWABLE_STATUSES: tuple[str, ...] = (
    ExceptionStatus.REVIEWED.value,
    ExceptionStatus.DISMISSED.value,
)


class ReviewException(Base):
    """One observation routed for specialist review."""

    __tablename__ = "review_exceptions"
    __table_args__ = (
        CheckConstraint(
            f"exception_type IN ({sql_values(ExceptionType)})",
            name="ck_review_exceptions_type",
        ),
        CheckConstraint(
            f"routing_rule IN ({sql_values(RoutingRule)})",
            name="ck_review_exceptions_routing_rule",
        ),
        CheckConstraint(
            f"status IN ({sql_values(ExceptionStatus)})",
            name="ck_review_exceptions_status",
        ),
        CheckConstraint(
            "supporting_observations >= 0",
            name="ck_review_exceptions_supporting_observations",
        ),
        # A closed exception must say who closed it and when. An open one must
        # not pretend it has been reviewed yet.
        CheckConstraint(
            "(status = 'open') = (reviewed_by_doctor_id IS NULL)",
            name="ck_review_exceptions_review_state_consistent",
        ),
        # The doctor roster is read constantly and always for one doctor.
        Index("ix_review_exceptions_doctor_queue", "patient_id", "status", "created_at"),
        Index("ix_review_exceptions_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    # The originating observation. UNIQUE is the duplicate guarantee: one
    # longitudinal result can produce at most one exception, so reprocessing
    # the same session cannot fill the queue with copies of itself. The
    # database enforces it, not the application.
    longitudinal_result_id: Mapped[int] = mapped_column(
        ForeignKey("longitudinal_results.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )

    # Denormalised from the session, the same way `MedicationEvent` carries its
    # own patient, so scoping the queue to a patient is a single index lookup
    # rather than a join through monitoring_sessions.
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )

    exception_type: Mapped[str] = mapped_column(String(32), nullable=False)
    routing_rule: Mapped[str] = mapped_column(String(40), nullable=False)

    # Why this entered the queue, in words, generated from the same facts as the
    # decision. Stored so the answer survives even if the thresholds change.
    rationale: Mapped[str] = mapped_column(String(500), nullable=False)

    # The count that justified the decision: consecutive changed sessions, or
    # comparable observations under one medication context.
    supporting_observations: Mapped[int] = mapped_column(Integer, nullable=False)

    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=ExceptionStatus.OPEN.value,
    )

    reviewed_by_doctor_id: Mapped[int | None] = mapped_column(
        ForeignKey("doctors.id", ondelete="SET NULL"),
        nullable=True,
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    # The reviewing doctor's own words. Never generated: this system does not
    # write clinical conclusions into its own database.
    review_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    # Loaded eagerly wherever the queue is listed, so rendering a page does not
    # issue one query per row for the observation it points at.
    longitudinal_result: Mapped["LongitudinalResult"] = relationship(
        uselist=False,
        passive_deletes=True,
        overlaps="medication_event",
    )

    def __repr__(self) -> str:
        return (
            f"<ReviewException id={self.id} patient_id={self.patient_id} "
            f"type={self.exception_type} status={self.status}>"
        )
