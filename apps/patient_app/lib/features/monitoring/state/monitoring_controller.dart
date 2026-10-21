import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/monitoring_repository.dart';
import '../models/canvas_event.dart';
import '../models/monitoring_plan.dart';
import '../models/monitoring_session.dart';

/// Loads the patient's monitoring plan and drives one session at a time.
class MonitoringController extends ChangeNotifier with ApiStateController {
  MonitoringController({required MonitoringRepository repository})
      : _repository = repository;

  final MonitoringRepository _repository;

  MonitoringPlan? _plan;
  MonitoringSession? _activeSession;
  List<MonitoringSession> _history = const <MonitoringSession>[];
  bool _hasLoadedPlan = false;
  bool _hasLoadedHistory = false;

  MonitoringPlan? get plan => _plan;
  MonitoringSession? get activeSession => _activeSession;
  List<MonitoringSession> get history => _history;
  bool get hasLoadedPlan => _hasLoadedPlan;
  bool get hasLoadedHistory => _hasLoadedHistory;

  /// Loads the current monitoring plan from the backend.
  ///
  /// A 404 means the patient has no plan yet, which is a normal state, not an
  /// error: the home screen shows a quiet explanation instead.
  Future<void> loadPlan() => runLoad(
        () async {
          _plan = await _repository.getPlan();
          _hasLoadedPlan = true;
        },
        onError: (ApiException error) {
          if (error.statusCode == 404) {
            _plan = null;
            _hasLoadedPlan = true;
          } else {
            reportError(error.message);
          }
        },
      );

  /// Loads the completed-session history for the tests tab.
  ///
  /// The history writes to its own error slot: a history that will not load
  /// must not blank the plan's error, or a patient with a plan would be told
  /// their plan is broken.
  Future<void> loadHistory() => runLoad(
        () async {
          _history = await _repository.listSessions();
          _hasLoadedHistory = true;
        },
        slot: historySlot,
      );

  /// The error slot the history writes to.
  static const String historySlot = 'history';

  /// Opens a session for a plan item and remembers it as the active one.
  Future<bool> startSession(MonitoringPlanItem item) => runSubmit(() async {
        _activeSession = await _repository.startSession(planItemId: item.id);
      });

  /// Completes the active session with the runner's raw event stream.
  ///
  /// One method for both runners: a finger-tapping recording arrives as tap
  /// offsets, a tracing recording as canvas events, and the backend decides
  /// which it is meant to be from the assessment. [medicationEventId] is the
  /// dose the patient reported, passed through untouched - the app does not
  /// decide whether the timing counts, and a session completed without one is a
  /// complete and valid outcome rather than a degraded one.
  ///
  /// The completed session, including the server-computed result, is kept as
  /// [lastCompletedSession] so the result screen can show exactly what the
  /// backend stored.
  Future<bool> completeSession(
    List<int> tapOffsetsMs, {
    List<CanvasEvent> canvasEvents = const <CanvasEvent>[],
    int? medicationEventId,
  }) async {
    final MonitoringSession? active = _activeSession;
    if (active == null) {
      return false;
    }
    return runSubmit(() async {
      final MonitoringSession completed = await _repository.completeSession(
        sessionId: active.id,
        tapOffsetsMs: tapOffsetsMs,
        canvasEvents: canvasEvents,
        medicationEventId: medicationEventId,
      );
      _lastCompletedSession = completed;
      _activeSession = null;
      _hasLoadedHistory = false; // history is stale once a session completes
    });
  }

  MonitoringSession? _lastCompletedSession;
  MonitoringSession? get lastCompletedSession => _lastCompletedSession;

  /// Drops in-progress session state without telling the server; used when the
  /// patient leaves the runner before finishing.
  void abandonSession() {
    _activeSession = null;
    notifyListeners();
  }

  void clear() {
    _plan = null;
    _activeSession = null;
    _lastCompletedSession = null;
    _history = const <MonitoringSession>[];
    _hasLoadedPlan = false;
    _hasLoadedHistory = false;
    clearError();
  }
}
