import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/medication_repository.dart';
import '../models/medication.dart';

/// The patient's own medication list and the doses they report.
///
/// Nothing here decides what a dose *means*. The controller records what the
/// patient said and keeps the returned row; classifying that against an
/// assessment is the backend's job, and the app renders its answer.
class MedicationController extends ChangeNotifier with ApiStateController {
  MedicationController({required MedicationRepository repository})
      : _repository = repository;

  final MedicationRepository _repository;

  List<Medication> _medications = const <Medication>[];
  bool _hasLoaded = false;

  List<Medication> get medications => _medications;

  /// Only active medications describe the patient's current regimen, so only
  /// these are offered when attaching context to a new assessment.
  List<Medication> get activeMedications => _medications
      .where((Medication medication) => medication.isActive)
      .toList(growable: false);

  bool get hasLoaded => _hasLoaded;

  Future<void> load() => runLoad(() async {
        _medications = await _repository.listMedications();
        _hasLoaded = true;
      });

  /// Adds a medication the patient reports taking.
  ///
  /// Returns true on success. The medication is stored exactly as typed; the
  /// app never normalises a dose or proposes a different one.
  Future<bool> add({
    required String name,
    String? doseLabel,
    String? frequencyLabel,
  }) {
    if (name.trim().isEmpty) {
      reportError('A medication needs a name.');
      return Future<bool>.value(false);
    }
    return runSubmit(() async {
      final Medication medication = await _repository.createMedication(
        name: name,
        doseLabel: doseLabel,
        frequencyLabel: frequencyLabel,
      );
      _medications = <Medication>[medication, ..._medications];
      _hasLoaded = true;
    });
  }

  Future<bool> setActive({
    required int medicationId,
    required bool isActive,
  }) =>
      runSubmit(() async {
        final Medication updated = await _repository.setActive(
          medicationId: medicationId,
          isActive: isActive,
        );
        _medications = _medications
            .map(
              (Medication medication) =>
                  medication.id == updated.id ? updated : medication,
            )
            .toList(growable: false);
      });

  /// Records one reported dose and returns the stored event.
  ///
  /// Returns null when the report could not be saved, in which case the caller
  /// attaches no context at all — a missed dose report must never become a
  /// fabricated one.
  Future<MedicationEvent?> reportDose({
    required int medicationId,
    required MedicationAdherence adherence,
    DateTime? takenAt,
  }) =>
      runSubmitValue<MedicationEvent>(() => _repository.recordDose(
            medicationId: medicationId,
            adherence: adherence,
            takenAt: takenAt,
          ));

  void clear() {
    _medications = const <Medication>[];
    _hasLoaded = false;
    clearError();
  }
}
