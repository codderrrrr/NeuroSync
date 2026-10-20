import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/check_in_repository.dart';
import '../models/check_in.dart';

/// Loads and creates the signed-in patient's symptom check-ins.
class CheckInController extends ChangeNotifier with ApiStateController {
  CheckInController({required CheckInRepository repository})
      : _repository = repository;

  final CheckInRepository _repository;

  List<CheckIn> _checkIns = const <CheckIn>[];
  bool _hasLoaded = false;

  List<CheckIn> get checkIns => _checkIns;
  bool get hasLoaded => _hasLoaded;

  Future<void> load() => runLoad(() async {
        _checkIns = await _repository.listCheckIns();
        _hasLoaded = true;
      });

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
  }) =>
      runSubmit(() async {
        final CheckIn checkIn = await _repository.createCheckIn(
          tremor: tremor,
          stiffness: stiffness,
          slowness: slowness,
          balance: balance,
          note: note,
        );
        _checkIns = <CheckIn>[checkIn, ..._checkIns];
        _hasLoaded = true;
      });

  void clear() {
    _checkIns = const <CheckIn>[];
    _hasLoaded = false;
    clearError();
  }
}
