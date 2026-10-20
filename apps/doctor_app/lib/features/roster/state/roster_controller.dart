import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/roster_repository.dart';
import '../models/roster_models.dart';

/// Loads the doctor's pending requests and active roster, and accepts links.
class RosterController extends ChangeNotifier with ApiStateController {
  RosterController({required RosterRepository repository})
      : _repository = repository;

  final RosterRepository _repository;

  List<PendingRequest> _pending = const <PendingRequest>[];
  List<RosterPatient> _patients = const <RosterPatient>[];
  bool _hasLoaded = false;

  List<PendingRequest> get pending => _pending;
  List<RosterPatient> get patients => _patients;
  bool get hasLoaded => _hasLoaded;

  /// Whether a request is being accepted right now.
  bool get isAccepting => isSubmitting;

  /// Loads both sections. A failure leaves the previous data visible with the
  /// error surfaced, so a refresh never blanks the dashboard.
  Future<void> loadDashboard() => runLoad(() async {
        final List<PendingRequest> pending = await _repository.pendingRequests();
        final List<RosterPatient> patients = await _repository.patients();
        _pending = pending;
        _patients = patients;
        _hasLoaded = true;
      });

  /// Accepts a pending request and refreshes both sections, since the accepted
  /// patient moves from the queue onto the roster.
  Future<bool> accept(PendingRequest request) => runSubmit(() async {
        await _repository.accept(request.linkId);
        await loadDashboard();
      });
}
