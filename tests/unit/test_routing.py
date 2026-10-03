"""Unit tests for the deterministic specialist-review routing rules.

Routing is a pure function of stored facts, so every rule is exercised here
without a database. Each test names the situation it describes rather than the
branch it hits, because what matters is the behaviour a clinician would rely
on: a normal recording is never routed, one unusual morning is not a finding,
and the gap between them is exactly what these thresholds encode.
"""

import subprocess
import sys

import pytest

from neurosync.modules.exceptions.routing import (
    MIN_COMPARABLE_FOR_CONTEXT,
    MINIMUM_ROUTABLE_EVIDENCE,
    PERSISTENCE_OBSERVATIONS,
    ExceptionType,
    RoutingObservation,
    RoutingRule,
    route_observation,
)
from neurosync.modules.medication.models import EvidenceStrength, MedicationContext
from neurosync.modules.monitoring.models import LongitudinalState

CHANGED = LongitudinalState.CHANGED
STEADY = LongitudinalState.WITHIN_BASELINE


def _observation(**overrides: object) -> RoutingObservation:
    """A well-supported change with no medication context, by default."""
    fields: dict[str, object] = {
        "state": CHANGED,
        "evidence_strength": EvidenceStrength.MODERATE,
        "medication_context": MedicationContext.UNKNOWN,
        "comparable_observation_count": 0,
    }
    fields.update(overrides)
    return RoutingObservation(**fields)  # type: ignore[arg-type]


# ------------------------------------------------------------- nothing routes


@pytest.mark.parametrize(
    "state",
    [
        LongitudinalState.WITHIN_BASELINE,
        LongitudinalState.INSUFFICIENT_DATA,
        LongitudinalState.UNRELIABLE,
    ],
)
def test_a_recording_that_did_not_change_is_never_routed(
    state: LongitudinalState,
) -> None:
    """The absence of a finding is not something to put in front of a doctor."""
    decision = route_observation(current=_observation(state=state))

    assert decision.should_route is False
    assert decision.exception_type is None
    assert decision.rule is None
    assert decision.supporting_observations == 0
    assert decision.rationale


@pytest.mark.parametrize(
    ("evidence", "expected_route"),
    [
        (EvidenceStrength.INSUFFICIENT, False),
        (EvidenceStrength.LIMITED, False),
        (EvidenceStrength.MODERATE, True),
        (EvidenceStrength.STRONGER, True),
    ],
)
def test_evidence_strength_gates_routing(
    evidence: EvidenceStrength,
    expected_route: bool,
) -> None:
    """Thin evidence never reaches a clinician, however large the deviation."""
    decision = route_observation(current=_observation(evidence_strength=evidence))

    assert decision.should_route is expected_route


def test_thin_evidence_outranks_a_repeated_change() -> None:
    """Evidence is checked before the pattern, so repetition cannot buy a route."""
    decision = route_observation(
        current=_observation(evidence_strength=EvidenceStrength.LIMITED),
        recent_states=(CHANGED, CHANGED),
    )

    assert decision.should_route is False
    assert decision.rationale != ""


def test_the_default_evidence_floor_is_the_documented_one() -> None:
    assert MINIMUM_ROUTABLE_EVIDENCE is EvidenceStrength.MODERATE


# ------------------------------------------------------------ persistent change


def test_three_consecutive_changes_route_as_persistent() -> None:
    """The current result plus two prior ones is a run worth a specialist."""
    decision = route_observation(
        current=_observation(),
        recent_states=(CHANGED, CHANGED),
    )

    assert decision.should_route is True
    assert decision.exception_type is ExceptionType.PERSISTENT_CHANGE
    assert decision.rule is RoutingRule.REPEATED_CHANGE
    assert decision.supporting_observations == 3


def test_two_changes_are_not_yet_a_persistent_change() -> None:
    """One short of the threshold falls through to the single-change rule."""
    decision = route_observation(
        current=_observation(),
        recent_states=(CHANGED,),
    )

    assert decision.exception_type is ExceptionType.REVIEW_REQUESTED
    assert decision.rule is RoutingRule.SUPPORTED_SINGLE_CHANGE
    assert decision.supporting_observations == 1


def test_a_longer_run_reports_the_full_count() -> None:
    """Only as many observations as the threshold are fetched and counted."""
    decision = route_observation(
        current=_observation(),
        recent_states=(CHANGED, CHANGED, CHANGED, CHANGED),
    )

    assert decision.supporting_observations == PERSISTENCE_OBSERVATIONS


def test_a_steady_recording_in_the_middle_breaks_the_run() -> None:
    """``changed, within_baseline, changed`` is one change today, not three."""
    decision = route_observation(
        current=_observation(),
        recent_states=(CHANGED, STEADY, CHANGED),
    )

    assert decision.exception_type is ExceptionType.REVIEW_REQUESTED
    assert decision.supporting_observations == 1


def test_no_history_at_all_is_a_single_change() -> None:
    decision = route_observation(current=_observation())

    assert decision.should_route is True
    assert decision.exception_type is ExceptionType.REVIEW_REQUESTED
    assert decision.supporting_observations == 1


# ------------------------------------------------------------ contextual change


def test_a_known_context_with_enough_history_routes_as_contextual() -> None:
    """Recurrence under one known medication context is its own kind of finding."""
    decision = route_observation(
        current=_observation(
            medication_context=MedicationContext.LATER_AFTER_MEDICATION,
            comparable_observation_count=MIN_COMPARABLE_FOR_CONTEXT,
        ),
    )

    assert decision.should_route is True
    assert decision.exception_type is ExceptionType.CONTEXTUAL_CHANGE
    assert decision.rule is RoutingRule.CONTEXT_CORROBORATED_CHANGE
    assert decision.supporting_observations == MIN_COMPARABLE_FOR_CONTEXT


def test_a_known_context_without_enough_history_falls_through() -> None:
    """One observation under a context is not corroboration by anything."""
    decision = route_observation(
        current=_observation(
            medication_context=MedicationContext.RECENTLY_AFTER_MEDICATION,
            comparable_observation_count=MIN_COMPARABLE_FOR_CONTEXT - 1,
        ),
    )

    assert decision.exception_type is ExceptionType.REVIEW_REQUESTED


def test_an_unknown_context_never_routes_as_contextual() -> None:
    """Unknown timing cannot corroborate anything, however much history there is."""
    decision = route_observation(
        current=_observation(
            medication_context=MedicationContext.UNKNOWN,
            comparable_observation_count=99,
        ),
    )

    assert decision.exception_type is ExceptionType.REVIEW_REQUESTED
    assert decision.rule is RoutingRule.SUPPORTED_SINGLE_CHANGE


def test_persistence_outranks_context() -> None:
    """A repeated change is labelled a repeated change, not a contextual one."""
    decision = route_observation(
        current=_observation(
            medication_context=MedicationContext.BEFORE_MEDICATION,
            comparable_observation_count=99,
        ),
        recent_states=(CHANGED, CHANGED),
    )

    assert decision.exception_type is ExceptionType.PERSISTENT_CHANGE


# ------------------------------------------------------------------ rationale


def test_every_decision_explains_itself() -> None:
    """A stored queue row must answer "why is this here?" on its own."""
    decisions = [
        route_observation(current=_observation(state=STEADY)),
        route_observation(current=_observation(evidence_strength=EvidenceStrength.LIMITED)),
        route_observation(current=_observation(), recent_states=(CHANGED, CHANGED)),
        route_observation(
            current=_observation(
                medication_context=MedicationContext.BEFORE_MEDICATION,
                comparable_observation_count=5,
            )
        ),
        route_observation(current=_observation()),
    ]

    for decision in decisions:
        assert decision.rationale.strip()
        assert decision.rationale[0].isupper()
        assert decision.rationale.endswith(".")


# ---------------------------------------------------------------- overridable


def test_the_persistence_threshold_can_be_lowered() -> None:
    """Thresholds are a deployment decision, not a hardcoded constant."""
    decision = route_observation(
        current=_observation(),
        recent_states=(CHANGED,),
        persistence_observations=2,
    )

    assert decision.exception_type is ExceptionType.PERSISTENT_CHANGE
    assert decision.supporting_observations == 2


def test_the_persistence_threshold_can_be_raised() -> None:
    """A run of four does not clear a threshold of five."""
    decision = route_observation(
        current=_observation(),
        recent_states=(CHANGED,) * 3,
        persistence_observations=5,
    )

    assert decision.exception_type is ExceptionType.REVIEW_REQUESTED


def test_the_evidence_floor_can_be_raised() -> None:
    decision = route_observation(
        current=_observation(evidence_strength=EvidenceStrength.MODERATE),
        minimum_evidence=EvidenceStrength.STRONGER,
    )

    assert decision.should_route is False


def test_the_context_minimum_can_be_raised() -> None:
    decision = route_observation(
        current=_observation(
            medication_context=MedicationContext.BEFORE_MEDICATION,
            comparable_observation_count=3,
        ),
        minimum_comparable_for_context=4,
    )

    assert decision.exception_type is ExceptionType.REVIEW_REQUESTED


def test_a_persistence_threshold_of_one_routes_immediately() -> None:
    """Degenerate but valid: the very first change is already the whole run."""
    decision = route_observation(
        current=_observation(),
        persistence_observations=1,
    )

    assert decision.exception_type is ExceptionType.PERSISTENT_CHANGE
    assert decision.supporting_observations == 1


# ------------------------------------------------------------------- wording


def test_no_exception_type_claims_a_diagnosis() -> None:
    """The vocabulary is the guardrail: no disease, progression, or causation."""
    vocabulary = (
        " ".join(member.value for member in ExceptionType)
        + " "
        + " ".join(member.value for member in RoutingRule)
    )

    for forbidden in ("progression", "dementia", "parkinson", "failure", "wearing", "dose"):
        assert forbidden not in vocabulary


# ---------------------------------------------------------------- standalone


def test_the_routing_module_imports_without_the_rest_of_the_system() -> None:
    """Import it alone, in a fresh interpreter, with no other module pulled in.

    Routing is meant to be a pure, independently testable layer. It reads its
    two vocabularies from the domain models, so a package that eagerly imported
    a router would drag the service and API layers back into this import and
    close a cycle. This test is what keeps that from being reintroduced: it
    fails loudly if the import order of the whole application is ever needed
    again.
    """
    completed = subprocess.run(
        [sys.executable, "-c", "import neurosync.modules.exceptions.routing"],
        capture_output=True,
        text=True,
        check=False,
    )

    assert completed.returncode == 0, completed.stderr
