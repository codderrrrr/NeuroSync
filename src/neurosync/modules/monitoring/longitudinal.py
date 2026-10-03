"""Patient-specific longitudinal comparison for finger tapping.

This module answers exactly one question about a repeated finger-tapping
recording: *is this broadly consistent with this patient's own previous
performance, or does it show a meaningful change?*

Three rules make it deterministic and explainable:

1. **Patient-specific.** A baseline is the median of this patient's own usable
   history. There are no population norms and no reference cohort, so a
   patient is only ever compared with themselves.
2. **Quality-aware.** An unusable recording (``invalid`` or ``incomplete``) is
   never compared and never contributes. A ``borderline`` recording does
   contribute, but it lowers the baseline's confidence and widens the tolerance
   before a change is declared, so poor-quality data can never become a
   confident conclusion.
3. **Comparable observations only.** Every tracked feature is a rate or rhythm
   statistic that does not depend on how long the recording ran, so sessions
   of different assigned durations stay comparable.

Nothing here is clinical. The output is a monitoring state for a specialist to
review, never a diagnosis, a severity stage, or a treatment suggestion.
"""

import statistics
from dataclasses import dataclass

from neurosync.modules.medication.models import MedicationContext
from neurosync.modules.monitoring.models import BaselineConfidence, LongitudinalState

# How many usable observations this patient's own history must contain before a
# baseline is considered established. Three is the smallest number for which a
# median is meaningfully different from any single observation, and it keeps
# the burden on the patient low. This is the single knob for the
# minimum-history rule: raising it changes the resulting states and nothing
# else needs redesigning.
MIN_BASELINE_OBSERVATIONS = 3

# The share of contributing observations that must be ``valid`` (rather than
# ``borderline``) for the baseline to be treated as full-confidence.
MIN_VALID_SHARE_FOR_FULL_CONFIDENCE = 0.75

# A reduced-confidence baseline gets a wider band before a change is declared.
REDUCED_CONFIDENCE_TOLERANCE_MULTIPLIER = 1.5

# Quality states that may contribute to a baseline or be compared against one.
USABLE_QUALITIES = ("valid", "borderline")


@dataclass(frozen=True, slots=True)
class TrackedFeature:
    """One compared finger-tapping feature and how far it may drift.

    ``relative_tolerance`` scales with the size of the baseline value, while
    ``absolute_floor`` covers small values where a purely relative band would
    collapse to nothing. The larger of the two wins, so a feature can never be
    judged on a zero-width tolerance.
    """

    key: str
    label: str
    relative_tolerance: float
    absolute_floor: float


# Only duration-independent rate and rhythm statistics are tracked. total_taps
# and duration_ms change with the assigned recording length, so comparing them
# across sessions of different lengths would measure the assignment rather than
# the patient.
TRACKED_FEATURES: tuple[TrackedFeature, ...] = (
    TrackedFeature(
        key="taps_per_second",
        label="Tapping rate",
        relative_tolerance=0.15,
        absolute_floor=0.20,
    ),
    TrackedFeature(
        key="mean_inter_tap_interval_ms",
        label="Mean interval",
        relative_tolerance=0.20,
        absolute_floor=30.0,
    ),
    TrackedFeature(
        key="inter_tap_variability_ms",
        label="Rhythm variability",
        relative_tolerance=0.30,
        absolute_floor=20.0,
    ),
    TrackedFeature(
        key="longest_pause_ms",
        label="Longest pause",
        relative_tolerance=0.40,
        absolute_floor=80.0,
    ),
)


@dataclass(frozen=True, slots=True)
class FeatureValues:
    """The compared subset of one finger-tapping observation."""

    taps_per_second: float
    mean_inter_tap_interval_ms: int
    inter_tap_variability_ms: int
    longest_pause_ms: int

    def value_for(self, feature_key: str) -> float:
        """Return the value of one tracked feature, named by its ``TRACKED_FEATURES`` key."""
        match feature_key:
            case "taps_per_second":
                return float(self.taps_per_second)
            case "mean_inter_tap_interval_ms":
                return float(self.mean_inter_tap_interval_ms)
            case "inter_tap_variability_ms":
                return float(self.inter_tap_variability_ms)
            case "longest_pause_ms":
                return float(self.longest_pause_ms)
            case _:
                raise KeyError(feature_key)


@dataclass(frozen=True, slots=True)
class Observation:
    """One completed finger-tapping session considered as baseline evidence.

    ``session_id`` is kept so a stored baseline can be traced back to the rows
    it was derived from.
    """

    session_id: int
    quality: str
    values: FeatureValues
    # The medication context this observation was recorded under. Defaults to
    # unknown so an observation from before this layer existed is treated as
    # having no context rather than being retrofitted with one.
    medication_context: MedicationContext = MedicationContext.UNKNOWN

    @property
    def is_usable(self) -> bool:
        """Usable observations are valid or borderline; nothing else."""
        return self.quality in USABLE_QUALITIES

    @property
    def is_valid(self) -> bool:
        return self.quality == "valid"


@dataclass(frozen=True, slots=True)
class PatientBaseline:
    """This patient's own finger-tapping baseline, rebuilt from stored history.

    The values are medians rather than means so that one unusual session cannot
    drag the reference away from the patient's real performance, and so the
    baseline can be reproduced exactly from the rows that produced it.
    """

    observation_count: int
    valid_observation_count: int
    borderline_observation_count: int
    values: FeatureValues
    confidence: BaselineConfidence

    @property
    def is_established(self) -> bool:
        """A baseline exists once it met the minimum-history rule."""
        return self.observation_count >= MIN_BASELINE_OBSERVATIONS

    def explanation(self) -> str:
        """Describe how this baseline was built, for traceability."""
        return (
            f"Baseline established from {self.observation_count} comparable "
            f"session(s): {self.valid_observation_count} valid and "
            f"{self.borderline_observation_count} borderline."
        )


def build_baseline(observations: list[Observation]) -> PatientBaseline | None:
    """Return this patient's baseline from their usable history, or ``None``.

    ``None`` means the minimum-history rule is not met yet, which is a normal
    state rather than an error: the patient simply has not recorded enough
    usable sessions. Only usable observations contribute; a recording that was
    invalid or incomplete is excluded entirely.

    The result is a pure function of ``observations``, so a persisted baseline
    can always be reproduced from the stored rows that produced it.
    """
    usable = [observation for observation in observations if observation.is_usable]
    if len(usable) < MIN_BASELINE_OBSERVATIONS:
        return None

    valid_count = sum(1 for observation in usable if observation.is_valid)
    borderline_count = len(usable) - valid_count
    confidence = (
        BaselineConfidence.FULL
        if valid_count / len(usable) >= MIN_VALID_SHARE_FOR_FULL_CONFIDENCE
        else BaselineConfidence.REDUCED
    )

    medians = {
        feature.key: statistics.median(
            [observation.values.value_for(feature.key) for observation in usable]
        )
        for feature in TRACKED_FEATURES
    }

    return PatientBaseline(
        observation_count=len(usable),
        valid_observation_count=valid_count,
        borderline_observation_count=borderline_count,
        values=FeatureValues(
            taps_per_second=medians["taps_per_second"],
            mean_inter_tap_interval_ms=int(medians["mean_inter_tap_interval_ms"]),
            inter_tap_variability_ms=int(medians["inter_tap_variability_ms"]),
            longest_pause_ms=int(medians["longest_pause_ms"]),
        ),
        confidence=confidence,
    )


@dataclass(frozen=True, slots=True)
class FeatureComparison:
    """One feature measured against the patient's own baseline."""

    feature_key: str
    label: str
    baseline_value: float
    observed_value: float
    tolerance: float

    @property
    def difference(self) -> float:
        """Signed drift from the baseline, positive when the value rose."""
        return self.observed_value - self.baseline_value

    @property
    def exceeded(self) -> bool:
        """Whether the drift is wide enough to count as a meaningful change."""
        return abs(self.difference) > self.tolerance


@dataclass(frozen=True, slots=True)
class LongitudinalAssessment:
    """The monitoring state for one session, with the evidence behind it."""

    state: LongitudinalState
    baseline: PatientBaseline | None
    comparisons: tuple[FeatureComparison, ...]
    usable_history_count: int
    # The usable prior observations, kept so comparability can be counted
    # without re-querying.
    history: tuple[Observation, ...] = ()

    @property
    def changed_features(self) -> list[str]:
        """Keys of the features that were outside their tolerance."""
        return [comparison.feature_key for comparison in self.comparisons if comparison.exceeded]

    def comparable_history_count(self, context: MedicationContext) -> int:
        """How many usable prior observations shared this medication context.

        Observations recorded with an unknown context never count as
        comparable to one recorded with known timing: mixing them would let a
        difference in context masquerade as a difference in the patient.

        ``unknown`` has no comparables at all, including other ``unknown``
        observations. A run of sessions in which nobody reported medication
        timing is an absence of context, not corroboration of one, so counting
        it would report a pile of supporting evidence for something that was
        never recorded.
        """
        if context is MedicationContext.UNKNOWN:
            return 0
        return len(
            [
                observation
                for observation in self.history
                if observation.is_usable and observation.medication_context is context
            ]
        )


def compare_to_baseline(
    *,
    baseline: PatientBaseline,
    observed: FeatureValues,
    history: tuple[Observation, ...] = (),
) -> LongitudinalAssessment:
    """Compare one observation against an established baseline.

    ``changed`` is declared when any single tracked feature drifts beyond its
    tolerance. The asymmetry is deliberate: this layer only informs a
    specialist, so missing a real change is worse than reporting one that
    turns out to be ordinary day-to-day variation.
    """
    multiplier = (
        1.0
        if baseline.confidence is BaselineConfidence.FULL
        else REDUCED_CONFIDENCE_TOLERANCE_MULTIPLIER
    )

    comparisons = tuple(
        FeatureComparison(
            feature_key=feature.key,
            label=feature.label,
            baseline_value=baseline.values.value_for(feature.key),
            observed_value=observed.value_for(feature.key),
            tolerance=(
                max(
                    feature.absolute_floor,
                    feature.relative_tolerance * abs(baseline.values.value_for(feature.key)),
                )
                * multiplier
            ),
        )
        for feature in TRACKED_FEATURES
    )

    changed = any(comparison.exceeded for comparison in comparisons)
    return LongitudinalAssessment(
        state=LongitudinalState.CHANGED if changed else LongitudinalState.WITHIN_BASELINE,
        baseline=baseline,
        comparisons=comparisons,
        usable_history_count=baseline.observation_count,
        history=history,
    )


def assess_observation(
    *,
    observations: list[Observation],
    current: Observation,
    persisted_baseline: PatientBaseline | None = None,
) -> LongitudinalAssessment:
    """Produce the longitudinal state for one completed finger-tapping session.

    The rule order is the whole contract:

    1. An unusable recording is ``unreliable``. It is never compared, because
       bad data cannot support any conclusion.
    2. Otherwise the baseline is (re)built from the patient's *prior* usable
       history. If there is not enough of it, the state is
       ``insufficient_data`` rather than a guess.
    3. Otherwise the current observation is compared against that baseline.

    ``observations`` must contain only sessions completed before ``current``:
    a session never contributes to the baseline it is judged against, so it can
    never validate itself.
    """
    usable_history = [observation for observation in observations if observation.is_usable]

    if not current.is_usable:
        return LongitudinalAssessment(
            state=LongitudinalState.UNRELIABLE,
            baseline=None,
            comparisons=(),
            usable_history_count=len(usable_history),
            history=tuple(usable_history),
        )

    baseline = build_baseline(usable_history) or persisted_baseline
    if baseline is None or not baseline.is_established:
        return LongitudinalAssessment(
            state=LongitudinalState.INSUFFICIENT_DATA,
            baseline=baseline,
            comparisons=(),
            usable_history_count=len(usable_history),
            history=tuple(usable_history),
        )

    return compare_to_baseline(
        baseline=baseline,
        observed=current.values,
        history=tuple(usable_history),
    )
