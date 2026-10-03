import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/assignment_repository.dart';
import '../models/assignment.dart';

/// Loads and creates exercises for one patient.
class AssignmentController extends ChangeNotifier {
  AssignmentController({required AssignmentRepository repository})
      : _repository = repository;

  final AssignmentRepository _repository;

  int? _patientId;
  List<Assignment> _assignments = const <Assignment>[];
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<Assignment> get assignments => _assignments;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  /// Loads the exercises for [patientId]. A failure keeps prior data and
  /// surfaces the error, matching the roster controller.
  Future<void> loadAssignments(int patientId) async {
    _patientId = patientId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _assignments = await _repository.list(patientId);
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Assigns a new exercise; returns true when it was created.
  Future<bool> createAssignment({
    required int patientId,
    required String? title,
    required String assessmentSlug,
    required int durationSeconds,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.create(
        patientId: patientId,
        title: title,
        assessmentSlug: assessmentSlug,
        durationSeconds: durationSeconds,
      );
      if (_patientId == patientId) {
        await loadAssignments(patientId);
      }
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
