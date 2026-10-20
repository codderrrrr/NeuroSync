"""Session service: one execution of one plan item, from start to close.

The event stream is stored exactly as captured. Which runner interprets it is
decided by the assessment's catalog ``execution_type``, never by what the
client happened to send.
"""

from dataclasses import replace
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from neurosync.modules.monitoring.assessment_catalog import (
    ExecutionType,
    get_spec,
    required_strokes,
)
from neurosync.modules.monitoring.canvas_features import extract_canvas_features
from neurosync.modules.monitoring.errors import (
    ERR_MISSING_DEFINITION,
    ERR_MISSING_PLAN_ITEM,
    ERR_NON_MONOTONIC_OFFSETS,
    ERR_UNASSIGNABLE_ASSESSMENTS,
    ERR_UNKNOWN_EXECUTION_TYPE,
    InactiveSessionError,
    InvalidEventDataError,
    MedicationContextNotSupportedError,
    MonitoringError,
    SessionNotFoundError,
    UnsupportedAssessmentError,
)
from neurosync.modules.monitoring.features import extract_tap_features
from neurosync.modules.monitoring.longitudinal import FeatureValues
from neurosync.modules.monitoring.longitudinal_service import (
    LongitudinalRecording,
    record_longitudinal_result,
    resolve_medication_context_for_recording,
)
from neurosync.modules.monitoring.models import (
    AssessmentDefinition,
    LongitudinalResult,
    MonitoringPlanItem,
    MonitoringResult,
    MonitoringSession,
    MonitoringSessionEvent,
    SessionStatus,
)
from neurosync.modules.monitoring.plan_service import (
    get_plan_item_for_patient,
    resolve_item_duration_seconds,
    resolve_item_parameters,
)
from neurosync.modules.monitoring.quality import evaluate_canvas_quality, evaluate_quality
from neurosync.modules.monitoring.schemas import (
    EVENT_TYPE_TAP,
    CompleteSessionRequest,
    TapEventRequest,
    canvas_strokes,
    event_offsets_ms,
)


def _to_tap_offsets(events: list[TapEventRequest]) -> list[int]:
    """Validate the raw event stream and reduce it to tap offsets."""
    try:
        offsets = event_offsets_ms(events)
    except ValueError as exc:
        raise InvalidEventDataError(str(exc)) from exc
    if sorted(offsets) != offsets:
        raise InvalidEventDataError(ERR_NON_MONOTONIC_OFFSETS)
    return offsets


async def start_session(
    *,
    session: AsyncSession,
    patient_id: int,
    plan_item_id: int,
) -> MonitoringSession:
    """Open an in-progress session for one of the patient's plan items."""
    item = await get_plan_item_for_patient(
        session=session,
        patient_id=patient_id,
        plan_item_id=plan_item_id,
    )
    definition = await session.get(AssessmentDefinition, item.assessment_definition_id)
    if definition is None or not definition.is_supported:
        # The plan read path already hides these, so reaching this guard means
        # a client asked for one by id. A test can be held back after a doctor
        # assigned it, and the patient must not be able to open a session for a
        # task NeuroSync has decided not to hand out.
        raise UnsupportedAssessmentError(
            ERR_UNASSIGNABLE_ASSESSMENTS.format(slugs=[str(item.assessment_definition_id)])
        )

    monitoring_session = MonitoringSession(
        patient_id=patient_id,
        plan_id=item.plan_id,
        plan_item_id=item.id,
        assessment_definition_id=item.assessment_definition_id,
        status=SessionStatus.IN_PROGRESS.value,
        started_at=datetime.now(UTC),
    )
    session.add(monitoring_session)
    await session.commit()
    # Re-read with the result relationship eagerly loaded: AsyncSession never
    # lazy-loads relationships implicitly, so the caller can serialize the
    # returned object without triggering IO.
    return await get_session_for_patient(
        session=session,
        patient_id=patient_id,
        monitoring_session_id=monitoring_session.id,
    )


async def complete_session(
    *,
    session: AsyncSession,
    patient_id: int,
    monitoring_session_id: int,
    payload: CompleteSessionRequest,
) -> tuple[MonitoringSession, MonitoringResult | None]:
    """Persist raw events, derive the result, and close the session.

    The event stream is stored exactly as captured; everything else in the
    result is derived deterministically from it. Which runner interprets the
    stream is decided by the assessment's catalog ``execution_type``, never by
    what the client happened to send. Completing twice fails explicitly instead
    of duplicating results.
    """
    monitoring_session = await get_session_for_patient(
        session=session,
        patient_id=patient_id,
        monitoring_session_id=monitoring_session_id,
    )
    if monitoring_session.status != SessionStatus.IN_PROGRESS.value:
        raise InactiveSessionError

    definition = await session.get(
        AssessmentDefinition,
        monitoring_session.assessment_definition_id,
    )
    if definition is None:
        raise MonitoringError(ERR_MISSING_DEFINITION)
    item = await session.get(MonitoringPlanItem, monitoring_session.plan_item_id)
    if item is None:
        raise MonitoringError(ERR_MISSING_PLAN_ITEM)
    # Judge the recording against the duration the plan actually asked for, not
    # the catalog default: a patient who complies with a longer assignment must
    # not be recorded as `invalid` for running past the shorter default.
    target_ms = resolve_item_duration_seconds(item, definition) * 1000

    execution_type = _execution_type_of(definition)
    if execution_type is ExecutionType.CANVAS_TASK:
        return await _complete_canvas_session(
            session=session,
            patient_id=patient_id,
            monitoring_session=monitoring_session,
            definition=definition,
            item=item,
            payload=payload,
            target_ms=target_ms,
        )
    return await _complete_tap_session(
        session=session,
        patient_id=patient_id,
        monitoring_session=monitoring_session,
        payload=payload,
        target_ms=target_ms,
    )


def _execution_type_of(definition: AssessmentDefinition) -> ExecutionType:
    """Return the assessment's execution type, failing on an unknown one.

    A catalog entry nobody has written a runner for cannot be completed, and
    guessing would mean interpreting the event stream the wrong way.
    """
    try:
        return ExecutionType(definition.execution_type)
    except ValueError as exc:
        raise UnsupportedAssessmentError(
            ERR_UNKNOWN_EXECUTION_TYPE.format(type=definition.execution_type)
        ) from exc


async def _complete_tap_session(
    *,
    session: AsyncSession,
    patient_id: int,
    monitoring_session: MonitoringSession,
    payload: CompleteSessionRequest,
    target_ms: int,
) -> tuple[MonitoringSession, MonitoringResult]:
    """Record one finger-tapping execution and compare it with the history."""
    offsets = _to_tap_offsets(payload.events)
    features = extract_tap_features(offsets)
    quality = evaluate_quality(features=features, target_duration_ms=target_ms)

    now = datetime.now(UTC)
    # Classify the reported dose before writing anything, and do it exactly
    # once. Resolving here rather than inside the longitudinal step both
    # rejects another patient's event outright - instead of degrading it into
    # "no medication information" - and hands the result forward instead of
    # fetching the same event twice.
    recording = LongitudinalRecording(
        monitoring_session_id=monitoring_session.id,
        assessment_definition_id=monitoring_session.assessment_definition_id,
        quality=quality.value,
        values=FeatureValues(
            taps_per_second=features.taps_per_second,
            mean_inter_tap_interval_ms=features.mean_inter_tap_interval_ms,
            inter_tap_variability_ms=features.inter_tap_variability_ms,
            longest_pause_ms=features.longest_pause_ms,
        ),
        completed_at=now,
        medication_event_id=payload.medication_event_id,
    )
    context, event = await resolve_medication_context_for_recording(
        session=session,
        patient_id=patient_id,
        recording=recording,
    )

    for offset in offsets:
        session.add(
            MonitoringSessionEvent(
                session_id=monitoring_session.id,
                event_type=EVENT_TYPE_TAP,
                offset_ms=offset,
            )
        )
    result = MonitoringResult(
        session_id=monitoring_session.id,
        total_taps=features.total_taps,
        duration_ms=features.duration_ms,
        mean_inter_tap_interval_ms=features.mean_inter_tap_interval_ms,
        inter_tap_variability_ms=features.inter_tap_variability_ms,
        longest_pause_ms=features.longest_pause_ms,
        taps_per_second=features.taps_per_second,
        quality=quality.value,
    )
    session.add(result)
    monitoring_session.status = SessionStatus.COMPLETED.value
    monitoring_session.completed_at = now
    # Flush the recording first so the longitudinal step sees it as committed
    # history for the sessions that follow, and because the comparison must
    # read back the quality just stored.
    await session.flush()

    # Longitudinal layer: compare this recording with the patient's own
    # history. The session being completed is excluded from that history, so it
    # is judged only against what came before it. The reported dose event, if
    # any, travels with the recording as supporting context.
    await record_longitudinal_result(
        session=session,
        patient_id=patient_id,
        recording=replace(
            recording,
            medication_context=context,
            medication_event=event,
        ),
    )

    await session.commit()
    return await _reloaded_session(session, patient_id, monitoring_session), result


async def _complete_canvas_session(  # noqa: PLR0913 - explicit arguments beat a config object
    *,
    session: AsyncSession,
    patient_id: int,
    monitoring_session: MonitoringSession,
    definition: AssessmentDefinition,
    item: MonitoringPlanItem,
    payload: CompleteSessionRequest,
    target_ms: int,
) -> tuple[MonitoringSession, MonitoringResult]:
    """Record one canvas (tracing) execution.

    Canvas recordings are described, not compared: the longitudinal layer is
    defined over finger-tapping features, and building a second comparison for
    every canvas assessment is a separate piece of work. Until that exists this
    session stores its raw events, its deterministic features and its quality,
    and reports no state and no medication context - rather than a comparison
    against a finger-tapping baseline, which would mean nothing.
    """
    if payload.medication_event_id is not None:
        raise MedicationContextNotSupportedError

    try:
        strokes = canvas_strokes(payload.events)
    except ValueError as exc:
        raise InvalidEventDataError(str(exc)) from exc

    offsets = [point.offset_ms for stroke in strokes for point in stroke]
    if sorted(offsets) != offsets:
        raise InvalidEventDataError(ERR_NON_MONOTONIC_OFFSETS)

    features = extract_canvas_features(strokes)
    spec = get_spec(definition.slug)
    parameters = resolve_item_parameters(item, definition)
    quality = evaluate_canvas_quality(
        features=features,
        target_duration_ms=target_ms,
        required_strokes=1 if spec is None else required_strokes(spec, parameters),
    )

    for event in payload.events:
        session.add(
            MonitoringSessionEvent(
                session_id=monitoring_session.id,
                event_type=event.event_type,
                offset_ms=event.offset_ms,
                payload=event.payload,
            )
        )
    result = MonitoringResult(
        session_id=monitoring_session.id,
        duration_ms=features.duration_ms,
        longest_pause_ms=features.longest_pause_ms,
        total_points=features.total_points,
        stroke_count=features.stroke_count,
        path_length=features.path_length,
        mean_speed_px_per_second=features.mean_speed_px_per_second,
        peak_speed_px_per_second=features.peak_speed_px_per_second,
        path_efficiency=features.path_efficiency,
        quality=quality.value,
    )
    session.add(result)
    monitoring_session.status = SessionStatus.COMPLETED.value
    monitoring_session.completed_at = datetime.now(UTC)

    await session.commit()
    return await _reloaded_session(session, patient_id, monitoring_session), result


async def _reloaded_session(
    session: AsyncSession,
    patient_id: int,
    monitoring_session: MonitoringSession,
) -> MonitoringSession:
    """Re-read a completed session with its relationships eagerly loaded.

    AsyncSession never lazy-loads, and a long-lived request session can hold a
    pre-write copy of this row, so the database is re-read rather than the
    identity map reused.
    """
    return await get_session_for_patient(
        session=session,
        patient_id=patient_id,
        monitoring_session_id=monitoring_session.id,
    )


async def get_session_for_patient(
    *,
    session: AsyncSession,
    patient_id: int,
    monitoring_session_id: int,
) -> MonitoringSession:
    """Return the session when (and only when) the patient owns it."""
    monitoring_session = await session.scalar(
        select(MonitoringSession)
        .options(
            selectinload(MonitoringSession.result),
            selectinload(MonitoringSession.longitudinal).selectinload(
                LongitudinalResult.medication_event
            ),
        )
        .where(
            MonitoringSession.id == monitoring_session_id,
            MonitoringSession.patient_id == patient_id,
        )
        # A long-lived request session can hold a pre-write copy of this row;
        # the database, not the identity map, is authoritative.
        .execution_options(populate_existing=True)
    )
    if monitoring_session is None:
        raise SessionNotFoundError
    return monitoring_session


async def list_patient_sessions(
    *,
    session: AsyncSession,
    patient_id: int,
    limit: int,
) -> list[MonitoringSession]:
    """Return the patient's completed sessions, newest first."""
    statement = (
        select(MonitoringSession)
        .options(
            selectinload(MonitoringSession.result),
            selectinload(MonitoringSession.longitudinal).selectinload(
                LongitudinalResult.medication_event
            ),
        )
        .where(
            MonitoringSession.patient_id == patient_id,
            MonitoringSession.status == SessionStatus.COMPLETED.value,
        )
        .order_by(MonitoringSession.started_at.desc(), MonitoringSession.id.desc())
        .limit(limit)
    )
    return list(await session.scalars(statement))
