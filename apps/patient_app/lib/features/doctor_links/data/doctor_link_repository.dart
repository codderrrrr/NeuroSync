import 'package:neurosync_core/neurosync_core.dart';
import '../models/doctor_link.dart';

/// Doctor-linking endpoints for the signed-in patient.
class DoctorLinkRepository {
  DoctorLinkRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<DoctorLink>> listLinks() async {
    final List<dynamic> items = await _apiClient.getList('/doctor-links');
    return items
        .cast<Map<String, dynamic>>()
        .map(DoctorLink.fromJson)
        .toList(growable: false);
  }

  Future<DoctorLink> requestLink(String doctorCode) async {
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/doctor-links',
      <String, dynamic>{'doctor_code': doctorCode},
    );
    return DoctorLink.fromJson(body);
  }
}
