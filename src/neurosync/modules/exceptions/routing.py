"""Deterministic specialist-review routing rules.

One question, answered as a pure function of facts already stored:

> Does this longitudinal observation meet a configured rule that makes it worth
> putting in front of a specialist?

An exception is **not** a diagnosis, a prediction, or a statement about what is
wrong with the patient. It is a routing decision: "this observation is
supported well enough that a human should look at it." Everything clinical
about interpreting it stays with the doctor who reviews it.

Every threshold here is an **engineering default** chosen to keep the queue
small and reproducible, not a clinically validated rule. They live in this one
module, named and configurable, so changing them is a deliberate edit rather
than a hunt through the codebase.
"""

from dataclasses import dataclass
from enum import StrEnum

from neurosync.modules.medication.models import EvidenceStrength, MedicationContext
from neurosync.modules.monitoring.models import LongitudinalState


class ExceptionType(StrEnum):
    """Why a record was routed for review.

    Deliberately small, and deliberately about the *observation* rather than
    about the patient. There is no ``progression``, ``medication_failure`` or
    ``wearing_off`` here, because nothing in the stored data supports a claim
    of that kind and inventing one would turn a routing decision into a
    diagnosis.
    """

    # The same deviation keeps appearing across consecutive usable sessions.
    PERSISTENT_CHANGE = "persistent_change"
    # The deviation recurs under a known medication context, corroborated by
    # earlier recordings in that same context. Says *when* it was seen, never
    # that the medication caused it.
    CONTEXTUAL_CHANGE = "contextual_change"
    # A single deviation, but one the evidence supports well enough that a
    # specialist should still see it.
    REVIEW_REQUESTED = "review_requested"


class RoutingRule(StrEnum):
    """The named rule that produced a decision, stored with the exception.

    Persisting the rule rather than only the type is what makes a queue entry
    answerable months later: "why is this here?" has a stored answer, not a
    re-derived one.
    """

    REPEATED_CHANGE = "repeated_change"
    CONTEXT_CORROBORATED_CHANGE = "context_corroborated_change"
    SUPPORTED_SINGLE_CHANGE = "supported_single_change"


# ---------------------------------------------------------------------------
# Engineering defaults. See the module docstring: these are routing choices,
# not clinical thresholds, and no clinical body has endorsed them.
# ---------------------------------------------------------------------------

# How many consecutive usable `changed` results (this one included) make a
# change "persistent". Three means one deviation is not enough on its own: a
# single unusual morning should not fill a review queue.
PERSISTENCE_OBSERVATIONS = 3

# How many earlier usable sessions recorded under the *same* medication context
# are needed before a contextual change counts as corroborated. Matching the
# evidence-strength rule for `stronger` keeps one vocabulary across the system.
MIN_COMPARABLE_FOR_CONTEXT = 3

# The weakest evidence that may be routed at all. `insufficient` means nothing
# was compared; `limited` means the comparison rests on a thin history. Neither
# is a reason to spend a clinician's attention.
MINIMUM_ROUTABLE_EVIDENCE = EvidenceStrength.MODERATE


@dataclass(frozen=True, slots=True)
class RoutingObservation:
    """The facts routing needs about one already-computed longitudinal result.

    Read from stored rows, never recalculated here. Grouping them keeps the
    rules readable and lets a test build any scenario without a database.

    Deliberately only four fields: which features changed is part of the
    *evidence a reviewer reads*, not part of the routing decision, so it is not
    an input here.
    """

    state: LongitudinalState
    evidence_strength: EvidenceStrength
    medication_context: MedicationContext
    comparable_observation_count: int


@dataclass(frozen=True, slots=True)
class RoutingDecision:
    """The structured answer, with enough detail to explain itself.

    A decision carries its own explanation rather than leaving the caller to
    reconstruct one, so the sentence a doctor reads is generated from the same
    facts that produced the decision.
    """

    should_route: bool
    exception_type: ExceptionType | None = None
    rule: RoutingRule | None = None
    rationale: str = ""
    # The count that justified the decision: consecutive changes, or matching
    # contextual observations. Zero when no rule fired.
    supporting_observations: int = 0


def _no_route(rationale: str) -> RoutingDecision:
    return RoutingDecision(should_route=False, rationale=rationale)


def _route(
    exception_type: ExceptionType,
    rule: RoutingRule,
    rationale: str,
    supporting_observations: int,
) -> RoutingDecision:
    return RoutingDecision(
        should_route=True,
        exception_type=exception_type,
        rule=rule,
        rationale=rationale,
        supporting_observations=supporting_observations,
    )


def route_observation(
    *,
    current: RoutingObservation,
    recent_states: tuple[LongitudinalState, ...] = (),
    persistence_observations: int = PERSISTENCE_OBSERVATIONS,
    minimum_comparable_for_context: int = MIN_COMPARABLE_FOR_CONTEXT,
    minimum_evidence: EvidenceStrength = MINIMUM_ROUTABLE_EVIDENCE,
) -> RoutingDecision:
    """Decide whether one observation belongs in the review queue.

    ``recent_states`` is the patient's most recent *usable* longitudinal
    results, newest first, **excluding** the current observation. Unusable
    sessions are left out by the caller rather than passed in as noise: an
    invalid recording should not break a run of good ones, and it should never
    count towards persistence.

    The rule order is the whole contract, and it is conservative by
    construction - the first two checks reject, the rest only ever narrow which
    exception type applies:

    1. Only a `changed` observation is ever routed. `insufficient_data`,
       `within_baseline` and `unreliable` are the absence of a finding.
    2. Evidence must reach the configured minimum.
    3. Persistence is checked before context so a genuinely repeated change is
       labelled as such rather than as a single one.
    """
    if current.state is not LongitudinalState.CHANGED:
        return _no_route(_no_change_rationale(current.state))

    if _evidence_rank(current.evidence_strength) < _evidence_rank(minimum_evidence):
        return _no_route("The evidence supporting this observation is too limited to route.")

    consecutive = _consecutive_changes(
        recent_states=recent_states,
        persistence_observations=persistence_observations,
    )
    if consecutive >= persistence_observations:
        return _route(
            exception_type=ExceptionType.PERSISTENT_CHANGE,
            rule=RoutingRule.REPEATED_CHANGE,
            rationale=(
                "Repeated change from the patient's own baseline across "
                f"{consecutive} consecutive usable sessions."
            ),
            supporting_observations=consecutive,
        )

    if (
        current.medication_context is not MedicationContext.UNKNOWN
        and current.comparable_observation_count >= minimum_comparable_for_context
    ):
        return _route(
            exception_type=ExceptionType.CONTEXTUAL_CHANGE,
            rule=RoutingRule.CONTEXT_CORROBORATED_CHANGE,
            rationale=(
                "Change from the patient's own baseline, recorded with known "
                "medication timing and seen before under the same context."
            ),
            supporting_observations=current.comparable_observation_count,
        )

    return _route(
        exception_type=ExceptionType.REVIEW_REQUESTED,
        rule=RoutingRule.SUPPORTED_SINGLE_CHANGE,
        rationale=(
            "A single change from the patient's own baseline that the "
            "recorded evidence supports well enough to review."
        ),
        supporting_observations=1,
    )


def _no_change_rationale(state: LongitudinalState) -> str:
    """Say plainly why there was nothing to route, in the pipeline's own terms."""
    match state:
        case LongitudinalState.WITHIN_BASELINE:
            return "The recording sits within the patient's usual range."
        case LongitudinalState.INSUFFICIENT_DATA:
            return "There is not enough history yet to compare against."
        case LongitudinalState.UNRELIABLE:
            return "The recording could not be compared."
        case LongitudinalState.CHANGED:
            # Unreachable in practice - the caller only asks about
            # observations that are *not* changed. Kept total so a future
            # state cannot silently fall through to no sentence at all.
            return "The recording changed from the patient's usual range."


def _consecutive_changes(
    *,
    recent_states: tuple[LongitudinalState, ...],
    persistence_observations: int,
) -> int:
    """Count the run of changes ending at the current observation, plus one.

    ``recent_states`` excludes the current result, so a run of N prior changes
    plus the current one is ``N + 1``. The walk stops at the first non-change:
    ``changed, within_baseline, changed`` is one change today, not three.
    """
    needed = persistence_observations - 1
    if needed <= 0:
        return 1
    consecutive = 1
    for state in recent_states:
        if state is not LongitudinalState.CHANGED:
            break
        consecutive += 1
        if consecutive >= persistence_observations:
            break
    return consecutive


# Evidence is ordered, so "at least this strong" is a comparison rather than a
# set membership test that would need rewriting every time a level is added.
_EVIDENCE_ORDER: tuple[EvidenceStrength, ...] = (
    EvidenceStrength.INSUFFICIENT,
    EvidenceStrength.LIMITED,
    EvidenceStrength.MODERATE,
    EvidenceStrength.STRONGER,
)


def _evidence_rank(value: EvidenceStrength) -> int:
    return _EVIDENCE_ORDER.index(value)
