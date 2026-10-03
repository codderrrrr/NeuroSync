"""Persistence models for the monitoring domain.

The catalog is seeded from ``assessment_catalog.ASSESSMENT_CATALOG`` so code and
database cannot drift. Plans group ordered assessment items; a plan is only
publishable while every item's assessment is supported. Sessions capture one
execution of one item, their raw events, and one derived result row.

The longitudinal layer adds two more rows per patient: ``patient_baselines``,
the patient's own finger-tapping reference derived from their usable history,
and ``longitudinal_results``, the state one session reached against it. Both
are reproducible from the stored observations; neither is a clinical score.
"""

from datetime import UTC, datetime
from enum import StrEnum

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from neurosync.db.session import Base, sql_values
from neurosync.modules.medication.models import (
    EvidenceStrength,
    MedicationContext,
    MedicationEvent,
)


class PlanStatus(StrEnum):
    """Lifecycle of a monitoring plan."""

    DRAFT = "draft"
    ACTIVE = "active"
    ARCHIVED = "archived"


class SessionStatus(StrEnum):
    """Lifecycle of one execution of a plan item."""

    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"


class RecordingQuality(StrEnum):
    """Deterministic quality state of one recorded session.

    Quality describes the recording, never the patient.
    """

    VALID = "valid"
    BORDERLINE = "borderline"
    INVALID = "invalid"
    INCOMPLETE = "incomplete"


class LongitudinalState(StrEnum):
    """How one observation compares with the patient's own history.

    A monitoring state for a specialist to review. It is not a clinical
    interpretation and carries no diagnosis or severity meaning.
    """

    INSUFFICIENT_DATA = "insufficient_data"
    WITHIN_BASELINE = "within_baseline"
    CHANGED = "changed"
    UNRELIABLE = "unreliable"


class BaselineConfidence(StrEnum):
    """How much the contributing observations can be trusted."""

    FULL = "full"
    REDUCED = "reduced"


class AssessmentDefinition(Base):
    """A test NeuroSync knows how to describe.

    ``is_supported`` records whether a runner exists; a definition without a
    runner must never be assigned to a patient as an executable task.
    """

    __tablename__ = "assessment_definitions"

    id: Mapped[int] = mapped_column(primary_key=True)
    slug: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    instructions: Mapped[str] = mapped_column(Text, nullable=False)
    execution_type: Mapped[str] = mapped_column(String(32), nullable=False)
    default_duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    is_supported: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
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
        return f"<AssessmentDefinition id={self.id} slug={self.slug}>"


class MonitoringPlan(Base):
    """A set of ordered assessments a patient should perform.

    ``doctor_id`` is optional: a plan can be created by a doctor through the
    portal, or by a development seed for a patient who has no doctor yet.
    Plans are only ever read by patient, so an owner is never required and the
    patient execution model does not depend on one.
    """

    __tablename__ = "monitoring_plans"
    __table_args__ = (
        CheckConstraint(
            f"status IN ({sql_values(PlanStatus)})",
            name="ck_monitoring_plans_status",
        ),
        Index("ix_monitoring_plans_patient_id_status", "patient_id", "status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )
    doctor_id: Mapped[int | None] = mapped_column(
        ForeignKey("doctors.id", ondelete="SET NULL"),
        nullable=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=PlanStatus.DRAFT.value,
    )
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
        return f"<MonitoringPlan id={self.id} patient_id={self.patient_id} status={self.status}>"


class MonitoringPlanItem(Base):
    """One assessment in a plan, at an explicit position in the ordering."""

    __tablename__ = "monitoring_plan_items"
    __table_args__ = (
        CheckConstraint("position >= 0", name="ck_monitoring_plan_items_position"),
        CheckConstraint(
            "duration_seconds IS NULL OR duration_seconds > 0",
            name="ck_monitoring_plan_items_duration",
        ),
        Index("ix_monitoring_plan_items_plan_id_position", "plan_id", "position"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    plan_id: Mapped[int] = mapped_column(
        ForeignKey("monitoring_plans.id", ondelete="CASCADE"),
        nullable=False,
    )
    assessment_definition_id: Mapped[int] = mapped_column(
        ForeignKey("assessment_definitions.id", ondelete="RESTRICT"),
        nullable=False,
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # Optional per-item recording target. When set (a doctor's assignment), it
    # overrides the assessment's default duration for this item only; when
    # null the catalog default applies.
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return f"<MonitoringPlanItem id={self.id} plan_id={self.plan_id} position={self.position}>"


class MonitoringSession(Base):
    """One execution of one plan item by one patient."""

    __tablename__ = "monitoring_sessions"
    __table_args__ = (
        CheckConstraint(
            f"status IN ({sql_values(SessionStatus)})",
            name="ck_monitoring_sessions_status",
        ),
        Index("ix_monitoring_sessions_patient_id_started_at", "patient_id", "started_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )
    plan_id: Mapped[int] = mapped_column(
        ForeignKey("monitoring_plans.id", ondelete="CASCADE"),
        nullable=False,
    )
    plan_item_id: Mapped[int] = mapped_column(
        ForeignKey("monitoring_plan_items.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Denormalised from the plan item so history and ownership checks do not
    # need joins through the plan.
    assessment_definition_id: Mapped[int] = mapped_column(
        ForeignKey("assessment_definitions.id", ondelete="RESTRICT"),
        nullable=False,
    )
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=SessionStatus.IN_PROGRESS.value,
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    # At most one derived result per session; loaded eagerly wherever the
    # session is read so history views never issue per-row queries.
    result: Mapped["MonitoringResult | None"] = relationship(
        uselist=False,
        passive_deletes=True,
    )

    # At most one longitudinal state per session, loaded eagerly alongside the
    # recording result for the same reason.
    longitudinal: Mapped["LongitudinalResult | None"] = relationship(
        uselist=False,
        passive_deletes=True,
    )

    def __repr__(self) -> str:
        return f"<MonitoringSession id={self.id} patient_id={self.patient_id} status={self.status}>"


class MonitoringSessionEvent(Base):
    """One raw client event captured during a session.

    Rows are stored exactly as reported: raw observations only. Everything
    derived from them lives in ``monitoring_results``.
    """

    __tablename__ = "monitoring_session_events"
    __table_args__ = (
        CheckConstraint("offset_ms >= 0", name="ck_monitoring_session_events_offset"),
        Index("ix_monitoring_session_events_session_id_offset", "session_id", "offset_ms"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("monitoring_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    offset_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    def __repr__(self) -> str:
        return f"<MonitoringSessionEvent id={self.id} session_id={self.session_id}>"


class MonitoringResult(Base):
    """Deterministic summary of one session's recording.

    Values describe the recording only (duration, tap counts, rhythm
    statistics, quality). Nothing here is a clinical score and nothing here
    diagnoses the patient.
    """

    __tablename__ = "monitoring_results"
    __table_args__ = (
        CheckConstraint(
            f"quality IN ({sql_values(RecordingQuality)})",
            name="ck_monitoring_results_quality",
        ),
        CheckConstraint("total_taps >= 0", name="ck_monitoring_results_total_taps"),
        CheckConstraint("duration_ms >= 0", name="ck_monitoring_results_duration_ms"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("monitoring_sessions.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    total_taps: Mapped[int] = mapped_column(Integer, nullable=False)
    duration_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    mean_inter_tap_interval_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    inter_tap_variability_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    longest_pause_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    taps_per_second: Mapped[float] = mapped_column(nullable=False)
    quality: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return (
            f"<MonitoringResult id={self.id} session_id={self.session_id} quality={self.quality}>"
        )


class PatientBaseline(Base):
    """A patient's own finger-tapping reference, derived from their history.

    One row per patient and assessment. The stored values are medians of that
    patient's usable observations, so the row is a cache of a deterministic
    computation rather than an independently maintained number:
    :func:`longitudinal.build_baseline` reproduces it exactly from the stored
    results, which is what makes the comparison auditable.

    Every value here describes the patient's own recorded performance. Nothing
    is a population norm, a clinical score, or a diagnosis.
    """

    __tablename__ = "patient_baselines"
    __table_args__ = (
        CheckConstraint(
            f"confidence IN ({sql_values(BaselineConfidence)})",
            name="ck_patient_baselines_confidence",
        ),
        CheckConstraint(
            "observation_count >= 0",
            name="ck_patient_baselines_observation_count",
        ),
        UniqueConstraint(
            "patient_id",
            "assessment_definition_id",
            name="uq_patient_baselines_patient_assessment",
        ),
        Index("ix_patient_baselines_patient_id", "patient_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("patients.id", ondelete="CASCADE"),
        nullable=False,
    )
    assessment_definition_id: Mapped[int] = mapped_column(
        ForeignKey("assessment_definitions.id", ondelete="RESTRICT"),
        nullable=False,
    )
    # How many usable observations produced this baseline, split by quality so
    # a specialist can see how much of it was borderline.
    observation_count: Mapped[int] = mapped_column(Integer, nullable=False)
    valid_observation_count: Mapped[int] = mapped_column(Integer, nullable=False)
    borderline_observation_count: Mapped[int] = mapped_column(Integer, nullable=False)
    # Medians of the duration-independent finger-tapping features.
    taps_per_second: Mapped[float] = mapped_column(nullable=False)
    mean_inter_tap_interval_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    inter_tap_variability_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    longest_pause_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    confidence: Mapped[str] = mapped_column(String(16), nullable=False)
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
            f"<PatientBaseline id={self.id} patient_id={self.patient_id} "
            f"observations={self.observation_count}>"
        )


class LongitudinalResult(Base):
    """The longitudinal state one session reached, with the evidence for it.

    Exactly one row per session, mirroring ``monitoring_results``. The stored
    baseline reference and ``changed_features`` are the audit trail: they say
    which baseline the session was judged against and which features fell
    outside their tolerance, so a state can always be explained after the fact.
    """

    __tablename__ = "longitudinal_results"
    __table_args__ = (
        CheckConstraint(
            f"state IN ({sql_values(LongitudinalState)})",
            name="ck_longitudinal_results_state",
        ),
        CheckConstraint(
            "usable_history_count >= 0",
            name="ck_longitudinal_results_usable_history_count",
        ),
        CheckConstraint(
            f"medication_context IN ({sql_values(MedicationContext)})",
            name="ck_longitudinal_results_medication_context",
        ),
        CheckConstraint(
            f"evidence_strength IN ({sql_values(EvidenceStrength)})",
            name="ck_longitudinal_results_evidence_strength",
        ),
        # Elapsed time is absolute; direction lives in medication_context.
        CheckConstraint(
            "minutes_since_medication IS NULL OR minutes_since_medication >= 0",
            name="ck_longitudinal_results_minutes_since_medication",
        ),
        Index("ix_longitudinal_results_session_id", "session_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("monitoring_sessions.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    # Null when no baseline existed to judge against (insufficient history).
    baseline_id: Mapped[int | None] = mapped_column(
        ForeignKey("patient_baselines.id", ondelete="SET NULL"),
        nullable=True,
    )
    state: Mapped[str] = mapped_column(String(24), nullable=False)
    usable_history_count: Mapped[int] = mapped_column(Integer, nullable=False)
    baseline_confidence: Mapped[str | None] = mapped_column(
        String(16),
        nullable=True,
    )
    # Which tracked features were outside their tolerance: the "why" behind a
    # `changed` state.
    changed_features: Mapped[list | None] = mapped_column(JSON, nullable=True)

    # --- medication context -------------------------------------------------
    # Supporting context for the comparison above, never a replacement for it.
    # All nullable: a session recorded before this layer existed, or one with no
    # medication information, stays exactly as valid as it was.
    medication_event_id: Mapped[int | None] = mapped_column(
        ForeignKey("medication_events.id", ondelete="SET NULL"),
        nullable=True,
    )
    # `unknown` whenever the timing could not be established. Never defaulted
    # away, so an absent timestamp cannot look like a known window.
    medication_context: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=MedicationContext.UNKNOWN.value,
    )
    minutes_since_medication: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
    )
    # How much supporting information stood behind the interpretation. A
    # description of how much was recorded, not a probability.
    evidence_strength: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=EvidenceStrength.INSUFFICIENT.value,
    )
    comparable_observation_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
    )

    # Eager-loaded wherever a session is read, so the result screen and history
    # can name the medication without a per-row query.
    medication_event: Mapped["MedicationEvent | None"] = relationship(
        uselist=False,
        passive_deletes=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )

    def __repr__(self) -> str:
        return f"<LongitudinalResult id={self.id} session_id={self.session_id} state={self.state}>"
