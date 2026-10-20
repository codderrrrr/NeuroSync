import 'package:neurosync_core/neurosync_core.dart';
import '../models/check_in.dart';

/// Check-in endpoints for the signed-in patient.
class CheckInRepository {
  CheckInRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<CheckIn>> listCheckIns() async {
    final List<dynamic> items = await _apiClient.getList('/check-ins');
    return items
        .cast<Map<String, dynamic>>()
        .map(CheckIn.fromJson)
        .toList(growable: false);
  }

  /// Records a check-in for right now.
  ///
  /// `recorded_at` is deliberately omitted so the server stamps the moment the
  /// patient saved it; the response carries the authoritative timestamp.
  Future<CheckIn> createCheckIn({
    required int tremor,
    required int stiffness,
    required int slowness,
    required int balance,
    String? note,
  }) async {
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/check-ins',
      <String, dynamic>{
        'tremor': tremor,
        'stiffness': stiffness,
        'slowness': slowness,
        'balance': balance,
        'note': note,
      },
    );
    return CheckIn.fromJson(body);
  }
}
