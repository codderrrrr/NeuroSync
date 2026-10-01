import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/roster_repository.dart';
import '../models/roster_models.dart';

/// Loads the doctor's pending requests and active roster, and accepts links.
class RosterController extends ChangeNotifier {
  RosterController({required RosterRepository repository})
      : _repository = repository;

  final RosterRepository _repository;

  List<PendingRequest> _pending = const <PendingRequest>[];
  List<RosterPatient> _patients = const <RosterPatient>[];
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isAccepting = false;
  String? _errorMessage;

  List<PendingRequest> get pending => _pending;
  List<RosterPatient> get patients => _patients;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get isAccepting => _isAccepting;
  String? get errorMessage => _errorMessage;

  /// Loads both sections. A failure leaves the previous data visible with the
  /// error surfaced, so a refresh never blanks the dashboard.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final List<PendingRequest> pending = await _repository.pendingRequests();
      final List<RosterPatient> patients = await _repository.patients();
      _pending = pending;
      _patients = patients;
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Accepts a pending request and refreshes both sections, since the accepted
  /// patient moves from the queue onto the roster.
  Future<bool> accept(PendingRequest request) async {
    _isAccepting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.accept(request.linkId);
      await loadDashboard();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isAccepting = false;
      notifyListeners();
    }
  }

  /// Marks the roster stale after a sign-out or account switch.
  void clear() {
    _pending = const <PendingRequest>[];
    _patients = const <RosterPatient>[];
    _hasLoaded = false;
    _errorMessage = null;
    notifyListeners();
  }
}
