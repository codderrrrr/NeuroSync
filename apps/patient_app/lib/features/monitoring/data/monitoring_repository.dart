import '../../../core/network/api_client.dart';
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

  /// Completes a session with the raw tap events captured by the runner.
  Future<MonitoringSession> completeSession({
    required int sessionId,
    required List<int> tapOffsetsMs,
  }) async {
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/monitoring/sessions/$sessionId/complete',
      <String, dynamic>{
        'events': <Map<String, dynamic>>[
          for (final int offsetMs in tapOffsetsMs)
            <String, dynamic>{'event_type': 'tap', 'offset_ms': offsetMs},
        ],
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

  Future<MonitoringSession> getSession(int sessionId) async {
    final Map<String, dynamic> body =
        await _apiClient.getObject('/monitoring/sessions/$sessionId');
    return MonitoringSession.fromJson(body);
  }
}
