import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/monitoring_repository.dart';
import '../models/monitoring_plan.dart';
import '../models/monitoring_session.dart';

/// Loads the patient's monitoring plan and drives one session at a time.
class MonitoringController extends ChangeNotifier {
  MonitoringController({required MonitoringRepository repository})
      : _repository = repository;

  final MonitoringRepository _repository;

  MonitoringPlan? _plan;
  MonitoringSession? _activeSession;
  List<MonitoringSession> _history = const <MonitoringSession>[];
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _hasLoadedPlan = false;
  bool _hasLoadedHistory = false;
  String? _errorMessage;

  MonitoringPlan? get plan => _plan;
  MonitoringSession? get activeSession => _activeSession;
  List<MonitoringSession> get history => _history;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get hasLoadedPlan => _hasLoadedPlan;
  bool get hasLoadedHistory => _hasLoadedHistory;
  String? get errorMessage => _errorMessage;

  /// Loads the current monitoring plan from the backend.
  ///
  /// A 404 means the patient has no plan yet, which is a normal state, not an
  /// error: the home screen shows a quiet explanation instead.
  Future<void> loadPlan() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _plan = await _repository.getPlan();
      _hasLoadedPlan = true;
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        _plan = null;
        _hasLoadedPlan = true;
      } else {
        _errorMessage = error.message;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the completed-session history for the check-ins tab.
  Future<void> loadHistory() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _history = await _repository.listSessions();
      _hasLoadedHistory = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Opens a session for a plan item and remembers it as the active one.
  Future<bool> startSession(MonitoringPlanItem item) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _activeSession = await _repository.startSession(planItemId: item.id);
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Completes the active session with the runner's raw tap offsets.
  ///
  /// The completed session, including the server-computed result, is kept as
  /// [lastCompletedSession] so the result screen can show exactly what the
  /// backend stored.
  Future<bool> completeSession(List<int> tapOffsetsMs) async {
    final MonitoringSession? active = _activeSession;
    if (active == null) {
      return false;
    }
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final MonitoringSession completed = await _repository.completeSession(
        sessionId: active.id,
        tapOffsetsMs: tapOffsetsMs,
      );
      _lastCompletedSession = completed;
      _activeSession = null;
      _hasLoadedHistory = false; // history is stale once a session completes
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  MonitoringSession? _lastCompletedSession;
  MonitoringSession? get lastCompletedSession => _lastCompletedSession;

  void clearLastCompletedSession() {
    _lastCompletedSession = null;
  }

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
    _errorMessage = null;
  }
}
