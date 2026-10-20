import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/doctor_link_repository.dart';
import '../models/doctor_link.dart';

/// Loads and creates the signed-in patient's doctor links.
class DoctorLinkController extends ChangeNotifier {
  DoctorLinkController({required DoctorLinkRepository repository})
      : _repository = repository;

  final DoctorLinkRepository _repository;

  List<DoctorLink> _links = const <DoctorLink>[];
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  String? _lastRequestedDoctorName;

  List<DoctorLink> get links => _links;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  /// Confirmation shown after a link request succeeds.
  bool get hasPendingConfirmation => _lastRequestedDoctorName != null;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _links = await _repository.listLinks();
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Requests a link and prepends the link the server returned.
  ///
  /// The returned link is authoritative server state, so no extra round trip is
  /// needed to show it.
  Future<bool> request(String doctorCode) async {
    _isSubmitting = true;
    _errorMessage = null;
    _lastRequestedDoctorName = null;
    notifyListeners();
    try {
      final DoctorLink link = await _repository.requestLink(doctorCode.trim());
      _links = <DoctorLink>[link, ..._links];
      _hasLoaded = true;
      _lastRequestedDoctorName = doctorCode.trim();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void acknowledgeConfirmation() {
    if (_lastRequestedDoctorName == null) {
      return;
    }
    _lastRequestedDoctorName = null;
    notifyListeners();
  }

  void clear() {
    _links = const <DoctorLink>[];
    _hasLoaded = false;
    _errorMessage = null;
    _lastRequestedDoctorName = null;
  }
}
