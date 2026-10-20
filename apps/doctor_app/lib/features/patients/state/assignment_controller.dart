import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/assignment_repository.dart';
import '../models/assessment_option.dart';
import '../models/assignment.dart';

/// The tests a doctor can assign, and one patient's assigned exercises.
///
/// The catalogue is loaded once and kept for the session: it is NeuroSync-owned
/// reference data, not per-patient state, and every screen that lets a doctor
/// configure a test renders from the same list.
class AssignmentController extends ChangeNotifier with ApiStateController {
  AssignmentController({required AssignmentRepository repository})
      : _repository = repository;

  final AssignmentRepository _repository;

  int? _patientId;
  List<Assignment> _assignments = const <Assignment>[];
  List<AssessmentOption> _assessments = const <AssessmentOption>[];
  bool _hasLoaded = false;
  bool _hasLoadedCatalog = false;

  List<Assignment> get assignments => _assignments;

  /// Every catalog test, including any that has no runner yet.
  List<AssessmentOption> get assessments => _assessments;

  /// Only the tests that can actually be assigned to a patient.
  List<AssessmentOption> get assignableAssessments => _assessments
      .where((AssessmentOption option) => option.isSupported)
      .toList(growable: false);

  bool get hasLoaded => _hasLoaded;
  bool get hasLoadedCatalog => _hasLoadedCatalog;

  /// The catalog entry for [slug], or null while the catalogue is still loading.
  AssessmentOption? assessmentFor(String slug) {
    for (final AssessmentOption option in _assessments) {
      if (option.slug == slug) {
        return option;
      }
    }
    return null;
  }

  /// Loads the tests this doctor may assign. A failure keeps whatever was
  /// already loaded so an editor stays usable while offline.
  Future<void> loadCatalog() => runLoad(() async {
        _assessments = await _repository.listAssessments();
        _hasLoadedCatalog = true;
      });

  /// Loads the exercises for [patientId]. A failure keeps prior data and
  /// surfaces the error, matching the roster controller.
  Future<void> loadAssignments(int patientId) {
    _patientId = patientId;
    return runLoad(() async {
      _assignments = await _repository.list(patientId);
      _hasLoaded = true;
    });
  }

  /// Assigns a new exercise; returns true when it was created.
  Future<bool> createAssignment({
    required int patientId,
    required String? title,
    required String assessmentSlug,
    required int durationSeconds,
    Map<String, Object> parameters = const <String, Object>{},
  }) =>
      runSubmit(() async {
        await _repository.create(
          patientId: patientId,
          title: title,
          assessmentSlug: assessmentSlug,
          durationSeconds: durationSeconds,
          parameters: parameters,
        );
        if (_patientId == patientId) {
          await loadAssignments(patientId);
        }
      });

  /// Changes an exercise already assigned; returns true when it was saved.
  Future<bool> updateAssignment({
    required int patientId,
    required int assignmentId,
    String? title,
    int? durationSeconds,
    Map<String, Object>? parameters,
  }) =>
      runSubmit(() async {
        await _repository.update(
          patientId: patientId,
          assignmentId: assignmentId,
          title: title,
          durationSeconds: durationSeconds,
          parameters: parameters,
        );
        if (_patientId == patientId) {
          await loadAssignments(patientId);
        }
      });

  /// Takes an exercise off the patient's plan; returns true when it was removed.
  Future<bool> removeAssignment({
    required int patientId,
    required int assignmentId,
  }) =>
      runSubmit(() async {
        await _repository.remove(
          patientId: patientId,
          assignmentId: assignmentId,
        );
        if (_patientId == patientId) {
          await loadAssignments(patientId);
        }
      });

  void clear() {
    _patientId = null;
    _assignments = const <Assignment>[];
    clearError();
    notifyListeners();
  }
}
