import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/check_in_repository.dart';
import '../models/check_in.dart';

/// Loads and creates the signed-in patient's symptom check-ins.
class CheckInController extends ChangeNotifier {
  CheckInController({required CheckInRepository repository})
      : _repository = repository;

  final CheckInRepository _repository;

  List<CheckIn> _checkIns = const <CheckIn>[];
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  List<CheckIn> get checkIns => _checkIns;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _checkIns = await _repository.listCheckIns();
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Records a check-in and prepends the check-in the server returned.
  ///
  /// The returned check-in is authoritative server state, so no extra round
  /// trip is needed to show it at the top of the history.
  Future<bool> create({
    required int tremor,
    required int stiffness,
    required int slowness,
    required int balance,
    String? note,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final CheckIn checkIn = await _repository.createCheckIn(
        tremor: tremor,
        stiffness: stiffness,
        slowness: slowness,
        balance: balance,
        note: note,
      );
      _checkIns = <CheckIn>[checkIn, ..._checkIns];
      _hasLoaded = true;
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clear() {
    _checkIns = const <CheckIn>[];
    _hasLoaded = false;
    _errorMessage = null;
  }
}
