import '../../../core/network/api_client.dart';
import '../models/canvas_event.dart';
import '../models/monitoring_plan.dart';
import '../models/monitoring_session.dart';

/// Monitoring endpoints for the signed-in patient.
///
/// The plan, its items and every assessment come from the backend; the app
/// never carries its own list of tests.
class MonitoringRepository {
  MonitoringRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<MonitoringPlan> getPlan() async {
    final Map<String, dynamic> body =
        await _apiClient.getObject('/monitoring/plan');
    return MonitoringPlan.fromJson(body);
  }

  Future<MonitoringSession> startSession({required int planItemId}) async {
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/monitoring/sessions',
      <String, dynamic>{'plan_item_id': planItemId},
    );
    return MonitoringSession.fromJson(body);
  }

  /// Completes a session with the raw events captured by the runner.
  ///
  /// [medicationEventId] attaches a dose the patient already reported as
  /// supporting context. It is optional and the server never guesses one: when
  /// it is null the resulting context stays unknown. The server also rejects it
  /// for a test that has no comparison for it to support, so the app only asks
  /// during the finger-tapping runner.
  Future<MonitoringSession> completeSession({
    required int sessionId,
    List<int> tapOffsetsMs = const <int>[],
    List<CanvasEvent> canvasEvents = const <CanvasEvent>[],
    int? medicationEventId,
  }) async {
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/monitoring/sessions/$sessionId/complete',
      <String, dynamic>{
        'events': <Map<String, dynamic>>[
          for (final int offsetMs in tapOffsetsMs)
            <String, dynamic>{'event_type': 'tap', 'offset_ms': offsetMs},
          for (final CanvasEvent event in canvasEvents) event.toJson(),
        ],
        'medication_event_id': medicationEventId,
      },
    );
    return MonitoringSession.fromJson(body);
  }

  /// The patient's completed sessions, newest first.
  Future<List<MonitoringSession>> listSessions({int limit = 30}) async {
    final List<dynamic> items = await _apiClient.getList(
      '/monitoring/sessions?limit=$limit',
    );
    return items
        .cast<Map<String, dynamic>>()
        .map(MonitoringSession.fromJson)
        .toList(growable: false);
  }
}
