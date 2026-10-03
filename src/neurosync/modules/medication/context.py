"""Deterministic medication-context classification and evidence strength.

Two rules live here, and both are pure functions of their inputs:

1. **Where did this assessment fall relative to a reported dose?** Classified
   from explicit timestamps only. When the timing is missing or unreliable the
   answer is ``unknown`` — never a plausible-looking window. Guessing would
   manufacture a clinical claim out of absent data.

2. **How much supporting information stands behind an interpretation?** A
   four-step description of how much was recorded, never a probability.

Nothing here detects wearing-off, judges whether a medication worked, or
recommends anything. These functions classify *timing*; interpretation of what
that timing means for a patient is a clinical task this system does not perform.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from neurosync.modules.medication.models import (
    EvidenceStrength,
    MedicationAdherence,
    MedicationContext,
)

# All windows are engineering defaults for categorising reported timing. They
# are not pharmacological onset/offset estimates and carry no clinical claim:
# they exist so the same input always produces the same label. They live here,
# in one place, rather than scattered as literals through the codebase.
MINUTES_PER_HOUR = 60
DEFAULT_RECENT_AFTER_WINDOW = timedelta(minutes=60)


@dataclass(frozen=True, slots=True)
class MedicationContextWindows:
    """The configurable boundaries used to classify timing.

    ``recent_after`` separates "shortly after a dose" from "later after". There
    is deliberately no upper bound: once the timing is known, the honest label
    is "later after", not "unknown". ``unknown`` is reserved for genuinely
    missing information.
    """

    recent_after: timedelta = DEFAULT_RECENT_AFTER_WINDOW


DEFAULT_WINDOWS = MedicationContextWindows()


@dataclass(frozen=True, slots=True)
class MedicationTiming:
    """The reported facts about one dose, as far as they are known.

    ``is_active`` travels with the timing so an inactive medication resolves to
    ``unknown`` without the caller having to remember that rule.
    """

    adherence: MedicationAdherence
    taken_at: datetime | None = None
    scheduled_at: datetime | None = None
    is_active: bool = True
    medication_name: str | None = None

    @property
    def timing_is_known(self) -> bool:
        """Whether an actual dose time was reported and can be trusted.

        ``not_sure`` is treated as not known even if a time happens to be
        attached: a patient who could not remember when must not have their
        uncertainty quietly overwritten by a number they were unsure about.
        """
        return self.adherence is MedicationAdherence.TAKEN and self.taken_at is not None


@dataclass(frozen=True, slots=True)
class MedicationContextResult:
    """The classified context, plus everything needed to explain it."""

    context: MedicationContext
    # Absolute minutes between the reported dose and the assessment; null when
    # unknown. Always non-negative: the direction lives in ``context``, so a
    # stored value never needs a sign convention to interpret.
    minutes_since: int | None = None

    def explanation(self) -> str:
        """A cautious, factual sentence for the patient or a specialist.

        Describes timing only. It never says a medication worked, stopped
        working, or should change.
        """
        if self.context is MedicationContext.UNKNOWN:
            return "Medication timing was not available for this assessment."
        if self.minutes_since is None:
            return "Medication timing was not available for this assessment."
        if self.context is MedicationContext.BEFORE_MEDICATION:
            return "This assessment was recorded before the reported medication time."
        return (
            f"This assessment was recorded approximately "
            f"{_humanise_minutes(self.minutes_since)} after the reported medication."
        )


def _humanise_minutes(minutes: int) -> str:
    """Render a duration the way a person would say it."""
    if minutes < MINUTES_PER_HOUR:
        return f"{minutes} min"
    hours, rest = divmod(minutes, MINUTES_PER_HOUR)
    if rest == 0:
        return f"{hours}h"
    return f"{hours}h {rest}m"


def classify_medication_context(
    *,
    assessment_at: datetime | None,
    timing: MedicationTiming | None,
    windows: MedicationContextWindows = DEFAULT_WINDOWS,
) -> MedicationContextResult:
    """Classify where an assessment fell relative to a reported dose.

    Every branch that cannot establish a real elapsed time returns ``unknown``.
    That includes: no associated event, an inactive medication, a dose reported
    as not taken or not sure, a missing assessment timestamp, and a missing
    actual dose time.
    """
    if assessment_at is None or timing is None:
        return MedicationContextResult(context=MedicationContext.UNKNOWN)

    if not timing.is_active:
        # An inactive medication cannot describe the patient's current regimen.
        return MedicationContextResult(context=MedicationContext.UNKNOWN)

    if not timing.timing_is_known:
        return MedicationContextResult(context=MedicationContext.UNKNOWN)

    taken_at = timing.taken_at
    assert taken_at is not None  # guaranteed by timing_is_known
    if taken_at.tzinfo is None:
        taken_at = taken_at.replace(tzinfo=UTC)
    reference = (
        assessment_at if assessment_at.tzinfo is not None else assessment_at.replace(tzinfo=UTC)
    )

    elapsed = reference - taken_at
    if elapsed < timedelta(0):
        return MedicationContextResult(
            context=MedicationContext.BEFORE_MEDICATION,
            minutes_since=abs(int(elapsed.total_seconds() // 60)),
        )

    minutes = int(elapsed.total_seconds() // 60)
    context = (
        MedicationContext.RECENTLY_AFTER_MEDICATION
        if elapsed <= windows.recent_after
        else MedicationContext.LATER_AFTER_MEDICATION
    )
    return MedicationContextResult(context=context, minutes_since=minutes)


@dataclass(frozen=True, slots=True)
class EvidenceInputs:
    """What was actually recorded for this interpretation.

    Grouped into one value so the rule reads as a single question rather than a
    long argument list, and so adding a factor later does not change the
    signature of every caller.
    """

    # Whether there was a usable recording and an established baseline at all.
    session_is_usable: bool
    baseline_established: bool
    baseline_confidence_is_full: bool
    # Usable prior sessions, and how many of them shared this context.
    usable_history_count: int
    comparable_observation_count: int
    medication_context: MedicationContext


def assess_evidence_strength(
    *,
    inputs: EvidenceInputs,
    minimum_history_for_moderate: int = 4,
    minimum_comparable_for_stronger: int = 3,
) -> EvidenceStrength:
    """Describe how much supporting information stands behind an interpretation.

    Deliberately coarse and never numeric. The thresholds are engineering
    defaults describing how much data was recorded, not calibrated confidence.

    The ordering matters: each step down removes a source of support. Notably,
    a session with no medication timing can still be ``moderate`` — the
    comparison stands on its own — but can never reach ``stronger``, because
    stronger medication-aware evidence requires known timing that is also
    corroborated by earlier recordings in the same context.
    """
    if not inputs.session_is_usable or not inputs.baseline_established:
        # Nothing was compared against anything.
        return EvidenceStrength.INSUFFICIENT
    if (
        not inputs.baseline_confidence_is_full
        or inputs.usable_history_count < minimum_history_for_moderate
    ):
        return EvidenceStrength.LIMITED
    if inputs.medication_context is MedicationContext.UNKNOWN:
        # The comparison itself stands, but there is no timing to contextualise
        # it with, so it must not be presented as medication-aware evidence.
        return EvidenceStrength.MODERATE
    if inputs.comparable_observation_count < minimum_comparable_for_stronger:
        # Timing is known here, but too few earlier recordings shared it for the
        # context to be well corroborated.
        return EvidenceStrength.MODERATE
    return EvidenceStrength.STRONGER
