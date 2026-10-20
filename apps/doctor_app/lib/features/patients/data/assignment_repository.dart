import 'package:neurosync_core/neurosync_core.dart';
import '../models/assessment_option.dart';
import '../models/assignment.dart';

/// Doctor-side endpoints for the test catalogue and for one patient's
/// assigned exercises.
class AssignmentRepository {
  AssignmentRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Every test a doctor can assign, with the settings they may change.
  ///
  /// Loaded from the API rather than carried in the app, so the catalogue the
  /// doctor picks from and the bounds the server enforces are the same data.
  Future<List<AssessmentOption>> listAssessments() async {
    final List<dynamic> body = await _apiClient.getList('/doctor/assessments');
    return body
        .cast<Map<String, dynamic>>()
        .map(AssessmentOption.fromJson)
        .toList(growable: false);
  }

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
    Map<String, Object> parameters = const <String, Object>{},
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'assessment_slug': assessmentSlug,
      'duration_seconds': durationSeconds,
    };
    if (title != null && title.trim().isNotEmpty) {
      payload['title'] = title.trim();
    }
    if (parameters.isNotEmpty) {
      payload['parameters'] = parameters;
    }
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/doctor/patients/$patientId/assignments',
      payload,
    );
    return Assignment.fromJson(body);
  }

  /// Change what an assigned exercise asks the patient to do.
  ///
  /// Only the fields the caller passes are sent, so the API applies exactly
  /// those and leaves the rest alone. `assessmentSlug` is not sent: changing
  /// which test a patient performs is a different instruction, and their
  /// recordings belong to the test they were taken for.
  Future<Assignment> update({
    required int patientId,
    required int assignmentId,
    String? title,
    int? durationSeconds,
    Map<String, Object>? parameters,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{};
    if (title != null) {
      payload['title'] = title;
    }
    if (durationSeconds != null) {
      payload['duration_seconds'] = durationSeconds;
    }
    if (parameters != null) {
      payload['parameters'] = parameters;
    }
    final Map<String, dynamic> body = await _apiClient.patchObject(
      '/doctor/patients/$patientId/assignments/$assignmentId',
      payload,
    );
    return Assignment.fromJson(body);
  }

  /// Take the exercise off the patient's next check-in.
  Future<void> remove({
    required int patientId,
    required int assignmentId,
  }) async {
    await _apiClient
        .delete('/doctor/patients/$patientId/assignments/$assignmentId');
  }
}
