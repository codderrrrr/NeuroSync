import 'package:neurosync_core/neurosync_core.dart';
import '../models/medication.dart';

/// Medication endpoints for the signed-in patient.
///
/// Records exactly what the patient reports and nothing more. Nothing here
/// interprets a dose, a schedule, or a timing: those stay on the backend,
/// where the rules are testable.
class MedicationRepository {
  MedicationRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Medication>> listMedications() async {
    final List<dynamic> items = await _apiClient.getList('/medications');
    return items
        .cast<Map<String, dynamic>>()
        .map(Medication.fromJson)
        .toList(growable: false);
  }

  Future<Medication> createMedication({
    required String name,
    String? doseLabel,
    String? frequencyLabel,
  }) async {
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/medications',
      <String, dynamic>{
        'name': name.trim(),
        'dose_label': _clean(doseLabel),
        'frequency_label': _clean(frequencyLabel),
      },
    );
    return Medication.fromJson(body);
  }

  Future<Medication> setActive({
    required int medicationId,
    required bool isActive,
  }) async {
    // The API takes this as a query parameter, not a body.
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/medications/$medicationId?is_active=$isActive',
      const <String, dynamic>{},
    );
    return Medication.fromJson(body);
  }

  Future<List<MedicationEvent>> listEvents({int limit = 20}) async {
    final List<dynamic> items =
        await _apiClient.getList('/medications/events?limit=$limit');
    return items
        .cast<Map<String, dynamic>>()
        .map(MedicationEvent.fromJson)
        .toList(growable: false);
  }

  /// Records one reported dose and returns it as the backend stored it.
  ///
  /// A null [takenAt] is a legitimate report: the patient is saying they took
  /// it but could not say when. The backend keeps that as unknown timing
  /// rather than filling in a plausible number.
  Future<MedicationEvent> recordDose({
    required int medicationId,
    required MedicationAdherence adherence,
    DateTime? takenAt,
    DateTime? scheduledAt,
  }) async {
    final Map<String, dynamic> body = await _apiClient.postObject(
      '/medications/events',
      <String, dynamic>{
        'medication_id': medicationId,
        'adherence': adherence.apiValue,
        'taken_at': takenAt?.toUtc().toIso8601String(),
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      },
    );
    return MedicationEvent.fromJson(body);
  }

  /// Blank text is dropped rather than stored as an empty label.
  static String? _clean(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
