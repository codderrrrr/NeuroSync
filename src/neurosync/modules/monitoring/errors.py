"""Monitoring domain errors and their messages.

Every error the monitoring module raises lives here, so the exception types and
the wording that goes with them are stated once rather than scattered through
the services that raise them.
"""


class MonitoringError(Exception):
    """Base class for monitoring domain errors."""


class UnsupportedAssessmentError(MonitoringError):
    """Raised when an assessment that is not being handed out would become a task.

    ``is_supported`` is false both for a test with no runner yet and for one
    deliberately held back, and neither may reach a patient.
    """


class PlanNotFoundError(MonitoringError):
    """Raised when the patient has no active monitoring plan."""


class PlanItemNotFoundError(MonitoringError):
    """Raised when a plan item does not exist for this patient."""


class InactiveSessionError(MonitoringError):
    """Raised when completing a session that is not in progress."""


class SessionNotFoundError(MonitoringError):
    """Raised when a session does not exist for this patient."""


class InvalidEventDataError(MonitoringError):
    """Raised when a session's event stream is not a valid recording."""


class UnknownMedicationEventError(MonitoringError):
    """Raised when a session references a dose event the patient does not own.

    Surfacing this instead of silently dropping the context keeps the
    ownership boundary honest: another patient's event must not quietly
    become "no medication information" for this session.
    """


class MedicationContextNotSupportedError(MonitoringError):
    """Raised when a dose is reported for an assessment that cannot use it.

    A canvas recording has no longitudinal comparison yet, so there is nothing
    for the dose timing to be supporting context for. Rejecting the report is
    honest; accepting and dropping it would read as the patient declining to
    give their medication, which is the opposite of what happened.
    """


# Error messages, kept beside the errors they belong to.
ERR_PLAN_NEEDS_ASSESSMENTS = "A monitoring plan needs at least one assessment."
ERR_UNKNOWN_ASSESSMENTS = "Unknown assessment definition ids: {ids}"
ERR_UNASSIGNABLE_ASSESSMENTS = (
    "Assessments that are not being handed out cannot be assigned: {slugs}"
)
ERR_MISSING_DEFINITION = "The session's assessment definition is missing."
ERR_MISSING_PLAN_ITEM = "The session's monitoring plan item is missing."
ERR_MISSING_RESULT = "The session's recording result is missing."
ERR_NON_MONOTONIC_OFFSETS = "Event offsets must be non-decreasing."
ERR_NON_TAP_RECORDING = "Only finger-tapping recordings take part in longitudinal comparison."
ERR_MISSING_CANVAS_COORDS = "Canvas events must carry numeric 'x' and 'y' values."
ERR_UNKNOWN_EXECUTION_TYPE = "No runner is implemented for execution type {type}."
ERR_MEDICATION_CONTEXT_NOT_SUPPORTED = (
    "Medication context is recorded for assessments that have a longitudinal comparison."
)
