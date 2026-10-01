import '../../../core/network/api_client.dart';
import '../models/assignment.dart';

/// Doctor-side assignment endpoints for one linked patient.
class AssignmentRepository {
  AssignmentRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Assignment>> list(int patientId) async {
    final List<dynamic> body =
        await _apiClient.getList('/doctor/patients/$patientId/assignments');
    return body
        .cast<Map<String, dynamic>>()
        .map(Assignment.fromJson)
        .toList(growable: false);
  }

  Future<Assignment> create({
    required int patientId,
    required String? title,
    required String assessmentSlug,
    required int durationSeconds,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'assessment_slug': assessmentSlug,
      'duration_seconds': durationSeconds,
    };
    if (title != null && title.trim().isNotEmpty) {
      payload['title'] = title.trim();
    }
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/doctor/patients/$patientId/assignments',
      payload,
    );
    return Assignment.fromJson(body);
  }
}
