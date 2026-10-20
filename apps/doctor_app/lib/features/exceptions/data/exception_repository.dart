import 'package:neurosync_core/neurosync_core.dart';
import '../models/review_exception.dart';

/// The doctor's specialist review queue.
///
/// Read and write endpoints for routed observations. The server owns the
/// scoping: every call here returns only what the signed-in doctor is already
/// linked to, so there is no client-side filtering of other people's patients.
class ExceptionRepository {
  ExceptionRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// The queue, newest first, optionally narrowed to one state.
  Future<List<ReviewExceptionSummary>> list({
    ExceptionFilter filter = ExceptionFilter.all,
    int? patientId,
  }) async {
    final Map<String, String> query = <String, String>{};
    final String? status = filter.statusQuery;
    if (status != null) {
      query['status'] = status;
    }
    if (patientId != null) {
      query['patient_id'] = '$patientId';
    }
    final String suffix = query.isEmpty ? '' : '?${_encode(query)}';
    final List<dynamic> body =
        await _apiClient.getList('/doctor/exceptions$suffix');
    return body
        .cast<Map<String, dynamic>>()
        .map(ReviewExceptionSummary.fromJson)
        .toList(growable: false);
  }

  /// One exception with the recording and reference behind the decision.
  Future<ReviewExceptionDetail> detail(int exceptionId) async {
    final Map<String, dynamic> body =
        await _apiClient.getObject('/doctor/exceptions/$exceptionId');
    return ReviewExceptionDetail.fromJson(body);
  }

  /// Closes an exception and returns it as the server now holds it.
  ///
  /// The server refuses a second review, so a conflict here means someone else
  /// got there first rather than that this call was malformed.
  Future<ReviewExceptionDetail> review({
    required int exceptionId,
    required ReviewOutcome outcome,
    String? note,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'status': outcome.wire,
    };
    final String trimmed = note?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      payload['note'] = trimmed;
    }
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/doctor/exceptions/$exceptionId/review',
      payload,
    );
    return ReviewExceptionDetail.fromJson(body);
  }

  static String _encode(Map<String, String> query) =>
      query.entries.map((e) => '${e.key}=${e.value}').join('&');
}
