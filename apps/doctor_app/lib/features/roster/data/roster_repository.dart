import '../../../core/network/api_client.dart';
import '../models/roster_models.dart';

/// Doctor-side roster endpoints.
class RosterRepository {
  RosterRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<PendingRequest>> pendingRequests() async {
    final List<dynamic> body =
        await _apiClient.getList('/doctor/patient-links/pending');
    return body
        .cast<Map<String, dynamic>>()
        .map(PendingRequest.fromJson)
        .toList(growable: false);
  }

  Future<List<RosterPatient>> patients() async {
    final List<dynamic> body = await _apiClient.getList('/doctor/patients');
    return body
        .cast<Map<String, dynamic>>()
        .map(RosterPatient.fromJson)
        .toList(growable: false);
  }

  Future<void> accept(int linkId) => _apiClient
      .postObject('/doctor/patient-links/$linkId/accept', <String, dynamic>{});
}
