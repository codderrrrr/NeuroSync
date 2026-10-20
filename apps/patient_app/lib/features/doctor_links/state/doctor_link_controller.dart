import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/doctor_link_repository.dart';
import '../models/doctor_link.dart';

/// Loads and creates the signed-in patient's doctor links.
class DoctorLinkController extends ChangeNotifier with ApiStateController {
  DoctorLinkController({required DoctorLinkRepository repository})
      : _repository = repository;

  final DoctorLinkRepository _repository;

  List<DoctorLink> _links = const <DoctorLink>[];
  bool _hasLoaded = false;
  String? _lastRequestedDoctorName;

  List<DoctorLink> get links => _links;
  bool get hasLoaded => _hasLoaded;

  /// Confirmation shown after a link request succeeds.
  bool get hasPendingConfirmation => _lastRequestedDoctorName != null;

  Future<void> load() => runLoad(() async {
        _links = await _repository.listLinks();
        _hasLoaded = true;
      });

  /// Requests a link and prepends the link the server returned.
  ///
  /// The returned link is authoritative server state, so no extra round trip
  /// is needed to show it.
  Future<bool> request(String doctorCode) {
    _lastRequestedDoctorName = null;
    return runSubmit(() async {
      final DoctorLink link = await _repository.requestLink(doctorCode.trim());
      _links = <DoctorLink>[link, ..._links];
      _hasLoaded = true;
      _lastRequestedDoctorName = doctorCode.trim();
    });
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
    _lastRequestedDoctorName = null;
    clearError();
  }
}
