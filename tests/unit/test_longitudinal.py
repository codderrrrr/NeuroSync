"""Unit tests for the deterministic longitudinal comparison.

These exercise the pure module directly: no database, no API. Everything here
is a function of the observations passed in, which is what makes the rule
changeable later without redesign.
"""

import pytest

from neurosync.modules.medication.models import MedicationContext
from neurosync.modules.monitoring.longitudinal import (
    MIN_BASELINE_OBSERVATIONS,
    REDUCED_CONFIDENCE_TOLERANCE_MULTIPLIER,
    FeatureValues,
    Observation,
    assess_observation,
    build_baseline,
    compare_to_baseline,
)
from neurosync.modules.monitoring.models import BaselineConfidence, LongitudinalState

# A steady 30s recording at one tap per second: 30 taps, ~0.97 taps/s,
# 1000 ms mean interval.
USUAL = FeatureValues(
    taps_per_second=0.969,
    mean_inter_tap_interval_ms=1000,
    inter_tap_variability_ms=50,
    longest_pause_ms=400,
)


def _observation(session_id: int, quality: str = "valid", **overrides: object) -> Observation:
    values = FeatureValues(
        taps_per_second=float(overrides.get("taps_per_second", USUAL.taps_per_second)),
        mean_inter_tap_interval_ms=int(
            overrides.get("mean_inter_tap_interval_ms", USUAL.mean_inter_tap_interval_ms)
        ),
        inter_tap_variability_ms=int(
            overrides.get("inter_tap_variability_ms", USUAL.inter_tap_variability_ms)
        ),
        longest_pause_ms=int(overrides.get("longest_pause_ms", USUAL.longest_pause_ms)),
    )
    return Observation(session_id=session_id, quality=quality, values=values)


# ------------------------------------------------------------------ baseline


def test_no_observations_means_no_baseline() -> None:
    assert build_baseline([]) is None


def test_a_single_observation_is_not_a_baseline() -> None:
    # One observation must never be treated as this patient's usual range.
    assert build_baseline([_observation(1)]) is None


def test_two_observations_are_still_insufficient() -> None:
    observations = [_observation(1), _observation(2)]
    assert len(observations) < MIN_BASELINE_OBSERVATIONS
    assert build_baseline(observations) is None


def test_three_usable_observations_establish_a_baseline() -> None:
    baseline = build_baseline([_observation(1), _observation(2), _observation(3)])

    assert baseline is not None
    assert baseline.is_established
    assert baseline.observation_count == 3
    assert baseline.valid_observation_count == 3
    assert baseline.borderline_observation_count == 0
    assert baseline.confidence is BaselineConfidence.FULL


def test_invalid_and_incomplete_sessions_are_excluded() -> None:
    # Three unusable sessions must not be enough to establish anything.
    observations = [
        _observation(1, quality="invalid"),
        _observation(2, quality="incomplete"),
        _observation(3, quality="invalid"),
        _observation(4, quality="incomplete"),
    ]
    assert build_baseline(observations) is None


def test_unusable_sessions_do_not_count_towards_the_minimum() -> None:
    # Two usable plus three unusable is still only two usable.
    observations = [
        _observation(1),
        _observation(2),
        _observation(3, quality="invalid"),
        _observation(4, quality="incomplete"),
        _observation(5, quality="invalid"),
    ]
    assert build_baseline(observations) is None


def test_baseline_uses_the_median_not_the_mean() -> None:
    # One outlier must not drag the reference away from the patient's real
    # performance, and the value must be reproducible from the contributors.
    observations = [
        _observation(1, taps_per_second=0.97, mean_inter_tap_interval_ms=1000),
        _observation(2, taps_per_second=0.97, mean_inter_tap_interval_ms=1000),
        _observation(3, taps_per_second=4.00, mean_inter_tap_interval_ms=250),
    ]
    baseline = build_baseline(observations)

    assert baseline is not None
    assert baseline.values.taps_per_second == 0.97
    assert baseline.values.mean_inter_tap_interval_ms == 1000


def test_borderline_history_lowers_confidence_but_still_contributes() -> None:
    observations = [
        _observation(1, quality="borderline"),
        _observation(2, quality="borderline"),
        _observation(3, quality="borderline"),
    ]
    baseline = build_baseline(observations)

    assert baseline is not None
    assert baseline.observation_count == 3
    assert baseline.borderline_observation_count == 3
    assert baseline.valid_observation_count == 0
    assert baseline.confidence is BaselineConfidence.REDUCED


def test_mostly_valid_history_keeps_full_confidence() -> None:
    observations = [
        _observation(1),
        _observation(2),
        _observation(3),
        _observation(4, quality="borderline"),
    ]
    baseline = build_baseline(observations)

    assert baseline is not None
    assert baseline.observation_count == 4
    assert baseline.confidence is BaselineConfidence.FULL


def test_baseline_explains_how_it_was_built() -> None:
    baseline = build_baseline([_observation(1), _observation(2), _observation(3)])

    assert baseline is not None
    explanation = baseline.explanation()
    assert "3 comparable session" in explanation
    assert "3 valid" in explanation


# --------------------------------------------------------------- comparison


def _usual_baseline() -> object:
    baseline = build_baseline([_observation(1), _observation(2), _observation(3)])
    assert baseline is not None
    return baseline


def test_a_repeat_of_usual_performance_is_within_baseline() -> None:
    assessment = compare_to_baseline(baseline=_usual_baseline(), observed=USUAL)

    assert assessment.state is LongitudinalState.WITHIN_BASELINE
    assert assessment.changed_features == []


def test_small_natural_variation_stays_within_baseline() -> None:
    observed = FeatureValues(
        taps_per_second=USUAL.taps_per_second * 1.05,
        mean_inter_tap_interval_ms=1030,
        inter_tap_variability_ms=58,
        longest_pause_ms=430,
    )
    assessment = compare_to_baseline(baseline=_usual_baseline(), observed=observed)

    assert assessment.state is LongitudinalState.WITHIN_BASELINE


def test_slower_tapping_beyond_tolerance_is_changed() -> None:
    observed = FeatureValues(
        taps_per_second=0.40,
        mean_inter_tap_interval_ms=2400,
        inter_tap_variability_ms=90,
        longest_pause_ms=600,
    )
    assessment = compare_to_baseline(baseline=_usual_baseline(), observed=observed)

    assert assessment.state is LongitudinalState.CHANGED
    assert "mean_inter_tap_interval_ms" in assessment.changed_features


def test_each_tracked_feature_has_its_own_tolerance() -> None:
    assessment = compare_to_baseline(baseline=_usual_baseline(), observed=USUAL)

    tolerances = {c.feature_key: c.tolerance for c in assessment.comparisons}
    assert tolerances["taps_per_second"] > 0
    assert all(value > 0 for value in tolerances.values())


def test_reduced_confidence_widens_the_tolerance() -> None:
    full = compare_to_baseline(baseline=_usual_baseline(), observed=USUAL)

    reduced_baseline = build_baseline(
        [
            _observation(1, quality="borderline"),
            _observation(2, quality="borderline"),
            _observation(3, quality="borderline"),
        ]
    )
    assert reduced_baseline is not None
    reduced = compare_to_baseline(baseline=reduced_baseline, observed=USUAL)

    full_tolerance = {c.feature_key: c.tolerance for c in full.comparisons}
    reduced_tolerance = {c.feature_key: c.tolerance for c in reduced.comparisons}
    for key, tolerance in full_tolerance.items():
        assert reduced_tolerance[key] == pytest.approx(
            tolerance * REDUCED_CONFIDENCE_TOLERANCE_MULTIPLIER
        )


# ------------------------------------------------------- assessment pipeline


def test_no_history_produces_insufficient_data_not_a_verdict() -> None:
    assessment = assess_observation(
        observations=[],
        current=_observation(9),
    )

    assert assessment.state is LongitudinalState.INSUFFICIENT_DATA
    assert assessment.changed_features == []
    assert assessment.usable_history_count == 0


def test_a_single_observation_produces_insufficient_data() -> None:
    # The current session must never establish the baseline it is judged by.
    assessment = assess_observation(
        observations=[_observation(1)],
        current=_observation(2),
    )

    assert assessment.state is LongitudinalState.INSUFFICIENT_DATA


def test_an_unusable_current_session_is_unreliable() -> None:
    for quality in ("invalid", "incomplete"):
        assessment = assess_observation(
            observations=[_observation(1), _observation(2), _observation(3)],
            current=_observation(4, quality=quality),
        )
        assert assessment.state is LongitudinalState.UNRELIABLE, quality
        assert assessment.comparisons == ()


def test_usable_history_compares_even_when_the_current_session_is_unusual() -> None:
    assessment = assess_observation(
        observations=[_observation(1), _observation(2), _observation(3)],
        current=_observation(4, taps_per_second=0.30, mean_inter_tap_interval_ms=3000),
    )

    assert assessment.state is LongitudinalState.CHANGED
    assert assessment.usable_history_count == 3


def test_unusable_history_is_not_counted_in_the_state() -> None:
    assessment = assess_observation(
        observations=[
            _observation(1),
            _observation(2),
            _observation(3),
            _observation(4, quality="invalid"),
            _observation(5, quality="incomplete"),
        ],
        current=_observation(6),
    )

    # Three usable sessions establish the baseline; the two unusable ones are
    # excluded from the count entirely.
    assert assessment.state is LongitudinalState.WITHIN_BASELINE
    assert assessment.usable_history_count == 3


def test_a_zero_baseline_value_still_gets_a_usable_tolerance() -> None:
    # A perfectly uniform recording really does produce zero rhythm variability.
    # Without the absolute floor, `relative_tolerance * 0` would judge the
    # feature on a zero-width band and flag every repeat as `changed`.
    uniform = FeatureValues(
        taps_per_second=1.034,
        mean_inter_tap_interval_ms=1000,
        inter_tap_variability_ms=0,
        longest_pause_ms=1000,
    )
    observation = Observation(session_id=1, quality="valid", values=uniform)
    baseline = build_baseline([observation, observation, observation])
    assert baseline is not None
    assert baseline.values.inter_tap_variability_ms == 0

    comparison = compare_to_baseline(baseline=baseline, observed=uniform)

    assert all(c.tolerance > 0 for c in comparison.comparisons)
    assert comparison.state is LongitudinalState.WITHIN_BASELINE


def test_a_zero_baseline_value_still_detects_a_real_change() -> None:
    # The floor must not be so wide that it hides a genuine shift.
    uniform = FeatureValues(1.034, 1000, 0, 1000)
    observation = Observation(session_id=1, quality="valid", values=uniform)
    baseline = build_baseline([observation, observation, observation])
    assert baseline is not None

    mild = compare_to_baseline(baseline=baseline, observed=FeatureValues(1.034, 1000, 15, 1000))
    irregular = compare_to_baseline(
        baseline=baseline, observed=FeatureValues(1.034, 1000, 80, 1000)
    )

    assert mild.state is LongitudinalState.WITHIN_BASELINE
    assert irregular.state is LongitudinalState.CHANGED


# ------------------------------------------------------ medication comparability


def _observed_with(context: MedicationContext, session_id: int) -> Observation:
    return Observation(
        session_id=session_id,
        quality="valid",
        values=USUAL,
        medication_context=context,
    )


def test_history_is_carried_so_comparability_can_be_counted() -> None:
    history = (
        _observed_with(MedicationContext.RECENTLY_AFTER_MEDICATION, 1),
        _observed_with(MedicationContext.RECENTLY_AFTER_MEDICATION, 2),
        _observed_with(MedicationContext.LATER_AFTER_MEDICATION, 3),
        _observed_with(MedicationContext.UNKNOWN, 4),
    )
    baseline = build_baseline(list(history))
    assert baseline is not None

    assessment = compare_to_baseline(baseline=baseline, observed=USUAL, history=history)

    assert assessment.comparable_history_count(MedicationContext.RECENTLY_AFTER_MEDICATION) == 2
    assert assessment.comparable_history_count(MedicationContext.LATER_AFTER_MEDICATION) == 1


def test_unknown_context_has_no_comparables_even_against_other_unknowns() -> None:
    """A run of unreported timing is an absence, never corroboration."""
    history = tuple(_observed_with(MedicationContext.UNKNOWN, i) for i in range(1, 6))
    baseline = build_baseline(list(history))
    assert baseline is not None

    assessment = compare_to_baseline(baseline=baseline, observed=USUAL, history=history)

    assert len(history) == 5
    assert assessment.comparable_history_count(MedicationContext.UNKNOWN) == 0


def test_unusable_history_never_counts_as_comparable() -> None:
    """Bad recordings stay in the count of history, never of support."""
    history = (
        Observation(
            session_id=1,
            quality="valid",
            values=USUAL,
            medication_context=MedicationContext.RECENTLY_AFTER_MEDICATION,
        ),
        Observation(
            session_id=2,
            quality="invalid",
            values=USUAL,
            medication_context=MedicationContext.RECENTLY_AFTER_MEDICATION,
        ),
    )
    baseline = build_baseline([history[0], history[0], history[0]])
    assert baseline is not None

    assessment = compare_to_baseline(baseline=baseline, observed=USUAL, history=history)

    assert assessment.comparable_history_count(MedicationContext.RECENTLY_AFTER_MEDICATION) == 1
