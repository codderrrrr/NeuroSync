"""Monitoring use cases: catalog, plans, sessions, and results.

Every patient-scoped lookup is filtered by the ``patient_id`` derived from the
authenticated session, so an object that exists but belongs to someone else is
indistinguishable from one that does not exist. Use cases that write own their
transaction, matching the other modules.

The work is split across focused services, and this module is the single place
callers import from:

* ``catalog_service`` - the assessment definitions and how they are rendered.
* ``plan_service`` - what a patient has been asked to do, and for how long.
* ``session_service`` - one execution of one plan item, from start to close.
* ``longitudinal_service`` - baselines, observations, and what a recording means.

The names below are re-exported so that a caller reaching for
``monitoring.service`` keeps working unchanged.
"""

from neurosync.modules.exceptions import service as exception_service
from neurosync.modules.monitoring.catalog_service import (
    assessment_response,
    get_assessment_catalog,
    get_assessment_definition,
    seed_assessment_catalog,
)
from neurosync.modules.monitoring.errors import (
    ERR_MEDICATION_CONTEXT_NOT_SUPPORTED,
    ERR_MISSING_CANVAS_COORDS,
    ERR_MISSING_DEFINITION,
    ERR_MISSING_PLAN_ITEM,
    ERR_MISSING_RESULT,
    ERR_NON_MONOTONIC_OFFSETS,
    ERR_NON_TAP_RECORDING,
    ERR_PLAN_NEEDS_ASSESSMENTS,
    ERR_UNASSIGNABLE_ASSESSMENTS,
    ERR_UNKNOWN_ASSESSMENTS,
    ERR_UNKNOWN_EXECUTION_TYPE,
    InactiveSessionError,
    InvalidEventDataError,
    MedicationContextNotSupportedError,
    MonitoringError,
    PlanItemNotFoundError,
    PlanNotFoundError,
    SessionNotFoundError,
    UnknownMedicationEventError,
    UnsupportedAssessmentError,
)
from neurosync.modules.monitoring.longitudinal_service import (
    LongitudinalRecording,
    baseline_explanation,
    get_baseline,
    list_observations,
    rebuild_baseline,
    record_longitudinal_result,
    resolve_medication_context_for_recording,
)
from neurosync.modules.monitoring.plan_service import (
    create_plan,
    get_patient_plan,
    get_plan_item_for_patient,
    resolve_item_duration_seconds,
    resolve_item_parameters,
)
from neurosync.modules.monitoring.session_service import (
    complete_session,
    get_session_for_patient,
    list_patient_sessions,
    start_session,
)

__all__ = [
    # catalog
    "assessment_response",
    "get_assessment_catalog",
    "get_assessment_definition",
    "seed_assessment_catalog",
    # plans
    "create_plan",
    "get_patient_plan",
    "get_plan_item_for_patient",
    "resolve_item_duration_seconds",
    "resolve_item_parameters",
    # sessions
    "complete_session",
    "get_session_for_patient",
    "list_patient_sessions",
    "start_session",
    # longitudinal
    "LongitudinalRecording",
    "baseline_explanation",
    "get_baseline",
    "list_observations",
    "rebuild_baseline",
    "record_longitudinal_result",
    "resolve_medication_context_for_recording",
    # errors
    "ERR_MEDICATION_CONTEXT_NOT_SUPPORTED",
    "ERR_MISSING_CANVAS_COORDS",
    "ERR_MISSING_DEFINITION",
    "ERR_MISSING_PLAN_ITEM",
    "ERR_MISSING_RESULT",
    "ERR_NON_MONOTONIC_OFFSETS",
    "ERR_NON_TAP_RECORDING",
    "ERR_PLAN_NEEDS_ASSESSMENTS",
    "ERR_UNKNOWN_ASSESSMENTS",
    "ERR_UNKNOWN_EXECUTION_TYPE",
    "ERR_UNASSIGNABLE_ASSESSMENTS",
    "InactiveSessionError",
    "InvalidEventDataError",
    "MedicationContextNotSupportedError",
    "MonitoringError",
    "PlanItemNotFoundError",
    "PlanNotFoundError",
    "SessionNotFoundError",
    "UnknownMedicationEventError",
    "UnsupportedAssessmentError",
    # The review-queue service, reachable through this module as it always
    # was. The routing call itself lives in the longitudinal service, but the
    # module it routes through is this same object.
    "exception_service",
]
