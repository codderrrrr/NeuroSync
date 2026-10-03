"""Unit tests for the pure medication-context rules.

These cover the two decisions that must stay deterministic and explainable:
where an assessment fell relative to a reported dose, and how much supporting
information stands behind an interpretation. Everything here is a pure
function of its inputs — no database, no HTTP.
"""

from dataclasses import replace
from datetime import UTC, datetime, timedelta

import pytest

from neurosync.modules.medication.context import (
    MINUTES_PER_HOUR,
    EvidenceInputs,
    MedicationContextResult,
    MedicationContextWindows,
    MedicationTiming,
    assess_evidence_strength,
    classify_medication_context,
)
from neurosync.modules.medication.models import (
    EvidenceStrength,
    MedicationAdherence,
    MedicationContext,
)

NOW = datetime(2026, 3, 14, 9, 0, tzinfo=UTC)


def _timing(
    *,
    adherence: MedicationAdherence = MedicationAdherence.TAKEN,
    taken_at: datetime | None = None,
    scheduled_at: datetime | None = None,
    is_active: bool = True,
    medication_name: str | None = "Levodopa",
) -> MedicationTiming:
    return MedicationTiming(
        adherence=adherence,
        taken_at=taken_at,
        scheduled_at=scheduled_at,
        is_active=is_active,
        medication_name=medication_name,
    )


# ------------------------------------------------- event before the assessment


def test_a_dose_just_taken_is_recently_after() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(minutes=30)),
    )

    assert result.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    assert result.minutes_since == 30


def test_a_dose_two_hours_earlier_is_later_after() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(hours=2)),
    )

    assert result.context is MedicationContext.LATER_AFTER_MEDICATION
    assert result.minutes_since == 120


def test_the_recent_window_boundary_is_inclusive() -> None:
    """Exactly on the boundary counts as recent, so the label is reproducible."""
    windows = MedicationContextWindows()
    on_boundary = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - windows.recent_after),
    )
    just_past = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - windows.recent_after - timedelta(minutes=1)),
    )

    assert on_boundary.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    assert on_boundary.minutes_since == 60
    assert just_past.context is MedicationContext.LATER_AFTER_MEDICATION


def test_the_window_is_configurable_rather_than_fixed() -> None:
    """A caller can widen the window and the same input relabels itself."""
    timing = _timing(taken_at=NOW - timedelta(minutes=45))

    default = classify_medication_context(assessment_at=NOW, timing=timing)
    widened = classify_medication_context(
        assessment_at=NOW,
        timing=timing,
        windows=MedicationContextWindows(recent_after=timedelta(hours=2)),
    )

    assert default.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    assert widened.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    assert widened.minutes_since == 45

    narrowed = classify_medication_context(
        assessment_at=NOW,
        timing=timing,
        windows=MedicationContextWindows(recent_after=timedelta(minutes=30)),
    )
    assert narrowed.context is MedicationContext.LATER_AFTER_MEDICATION


def test_a_dose_in_the_future_is_before_medication() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW + timedelta(minutes=60)),
    )

    assert result.context is MedicationContext.BEFORE_MEDICATION
    # Absolute: the direction lives in the context, so the stored number
    # never needs a sign convention to read.
    assert result.minutes_since == 60


# ------------------------------------------------------ unknown must stay unknown


@pytest.mark.parametrize(
    "timing",
    [
        pytest.param(None, id="no-event-attached"),
        pytest.param(_timing(taken_at=None), id="taken-but-no-time"),
        pytest.param(
            _timing(adherence=MedicationAdherence.NOT_TAKEN, taken_at=None),
            id="not-taken",
        ),
        pytest.param(
            _timing(
                adherence=MedicationAdherence.NOT_SURE,
                # A time the patient was unsure about must not be promoted to
                # certainty just because a number exists.
                taken_at=NOW - timedelta(minutes=30),
            ),
            id="not-sure-even-with-a-time",
        ),
        pytest.param(
            _timing(taken_at=NOW - timedelta(minutes=30), is_active=False),
            id="inactive-medication",
        ),
    ],
)
def test_unreliable_timing_stays_unknown(timing: MedicationTiming | None) -> None:
    result = classify_medication_context(assessment_at=NOW, timing=timing)

    assert result.context is MedicationContext.UNKNOWN
    assert result.minutes_since is None


def test_a_missing_assessment_time_stays_unknown() -> None:
    """Without a reference point there is no elapsed time to report."""
    result = classify_medication_context(
        assessment_at=None,
        timing=_timing(taken_at=NOW - timedelta(minutes=30)),
    )

    assert result.context is MedicationContext.UNKNOWN
    assert result.minutes_since is None


def test_a_scheduled_time_alone_does_not_become_a_context() -> None:
    """Only an actual dose establishes timing; an expectation does not."""
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=None, scheduled_at=NOW - timedelta(minutes=90)),
    )

    assert result.context is MedicationContext.UNKNOWN


def test_naive_timestamps_are_read_as_utc_rather_than_crashing() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=(NOW - timedelta(minutes=20)).replace(tzinfo=None)),
    )

    assert result.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    assert result.minutes_since == 20


# ------------------------------------------------------------- explanations


def test_the_note_describes_timing_and_nothing_else() -> None:
    recent = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(minutes=105)),
    )
    before = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW + timedelta(minutes=45)),
    )
    unknown = classify_medication_context(assessment_at=NOW, timing=None)

    assert "1h 45m after" in recent.explanation()
    assert "before the reported medication" in before.explanation()
    assert unknown.explanation() == "Medication timing was not available for this assessment."


@pytest.mark.parametrize(
    ("minutes", "rendered"),
    [
        (5, "5 min"),
        (60, "1h"),
        (105, "1h 45m"),
        (MINUTES_PER_HOUR * 4, "4h"),
    ],
)
def test_durations_are_rendered_the_way_a_person_would_say_them(
    minutes: int,
    rendered: str,
) -> None:
    result = MedicationContextResult(
        context=MedicationContext.LATER_AFTER_MEDICATION,
        minutes_since=minutes,
    )

    assert rendered in result.explanation()


def test_an_unknown_context_never_renders_a_duration() -> None:
    """A stale duration must not leak into the note for an unknown context."""
    result = MedicationContextResult(
        context=MedicationContext.UNKNOWN,
        minutes_since=None,
    )

    assert result.explanation() == "Medication timing was not available for this assessment."
    # No digits at all: an unknown context has nothing to count.
    assert not any(character.isdigit() for character in result.explanation())


# -------------------------------------------------------- evidence strength


def _inputs(**overrides: object) -> EvidenceInputs:
    """A well-supported reading with known timing, adjusted by keyword.

    Starting from one fully-supported baseline and overriding only what a test
    is actually about keeps each assertion readable.
    """
    defaults = EvidenceInputs(
        session_is_usable=True,
        baseline_established=True,
        baseline_confidence_is_full=True,
        usable_history_count=4,
        comparable_observation_count=3,
        medication_context=MedicationContext.RECENTLY_AFTER_MEDICATION,
    )
    return replace(defaults, **overrides)


def test_known_timing_with_corroborating_history_is_stronger() -> None:
    assert assess_evidence_strength(inputs=_inputs()) is EvidenceStrength.STRONGER


def test_an_unusable_recording_supports_nothing() -> None:
    assert (
        assess_evidence_strength(inputs=_inputs(session_is_usable=False))
        is EvidenceStrength.INSUFFICIENT
    )


def test_no_baseline_supports_nothing() -> None:
    assert (
        assess_evidence_strength(inputs=_inputs(baseline_established=False))
        is EvidenceStrength.INSUFFICIENT
    )


def test_a_thin_or_uncertain_baseline_stays_limited() -> None:
    assert (
        assess_evidence_strength(inputs=_inputs(usable_history_count=1)) is EvidenceStrength.LIMITED
    )
    assert (
        assess_evidence_strength(inputs=_inputs(baseline_confidence_is_full=False))
        is EvidenceStrength.LIMITED
    )


def test_missing_medication_information_can_never_be_stronger() -> None:
    """The comparison stands on its own, but there is no timing to contextualise."""
    assert (
        assess_evidence_strength(inputs=_inputs(medication_context=MedicationContext.UNKNOWN))
        is EvidenceStrength.MODERATE
    )


def test_known_timing_without_matching_history_stays_moderate() -> None:
    """Timing alone is not corroboration: the context must repeat."""
    assert (
        assess_evidence_strength(inputs=_inputs(comparable_observation_count=1))
        is EvidenceStrength.MODERATE
    )


def test_evidence_never_improves_when_timing_is_unknown() -> None:
    """No combination of history can lift an unknown context past moderate."""
    for history in range(0, 12):
        for comparable in range(0, 12):
            strength = assess_evidence_strength(
                inputs=_inputs(
                    usable_history_count=history,
                    comparable_observation_count=comparable,
                    medication_context=MedicationContext.UNKNOWN,
                )
            )
            assert strength is not EvidenceStrength.STRONGER


def test_evidence_thresholds_are_configurable() -> None:
    inputs = _inputs(usable_history_count=2, comparable_observation_count=2)

    assert assess_evidence_strength(inputs=inputs) is EvidenceStrength.LIMITED
    assert (
        assess_evidence_strength(
            inputs=inputs,
            minimum_history_for_moderate=2,
            minimum_comparable_for_stronger=2,
        )
        is EvidenceStrength.STRONGER
    )


def test_evidence_strength_is_never_numeric() -> None:
    """The categories are the whole vocabulary; no percentage may leak in."""
    assert {member.value for member in EvidenceStrength} == {
        "insufficient",
        "limited",
        "moderate",
        "stronger",
    }


# -------------------------------------------------------- sub-minute fidelity


def test_a_dose_one_second_short_of_the_window_is_still_recent() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(minutes=59, seconds=59)),
    )

    assert result.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    # Floor, not round: 59m59s is 59 whole minutes.
    assert result.minutes_since == 59


def test_a_dose_exactly_on_the_window_boundary_counts_as_recent() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(minutes=60)),
    )

    assert result.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    assert result.minutes_since == 60


def test_a_dose_one_second_past_the_window_has_moved_on() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(minutes=60, seconds=1)),
    )

    # Still 60 whole minutes, but in the other window. The label comes from the
    # comparison and the number from the elapsed time; they are separate facts.
    assert result.context is MedicationContext.LATER_AFTER_MEDICATION
    assert result.minutes_since == 60


def test_a_dose_seconds_ago_reports_zero_whole_minutes() -> None:
    result = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(seconds=30)),
    )

    assert result.context is MedicationContext.RECENTLY_AFTER_MEDICATION
    assert result.minutes_since == 0


def test_aware_and_naive_timestamps_classify_identically() -> None:
    aware = classify_medication_context(
        assessment_at=NOW,
        timing=_timing(taken_at=NOW - timedelta(minutes=59, seconds=59)),
    )
    naive = classify_medication_context(
        assessment_at=NOW.replace(tzinfo=None),
        timing=_timing(taken_at=(NOW - timedelta(minutes=59, seconds=59)).replace(tzinfo=None)),
    )

    assert (aware.context, aware.minutes_since) == (naive.context, naive.minutes_since)
