import 'package:flutter/widgets.dart';

import 'features/auth/state/auth_controller.dart';
import 'features/check_ins/state/check_in_controller.dart';
import 'features/doctor_links/state/doctor_link_controller.dart';
import 'features/medication/state/medication_controller.dart';
import 'features/monitoring/state/monitoring_controller.dart';

/// Provides the application's controllers to the widget tree.
///
/// A plain [InheritedWidget] is enough here: widgets listen to the controllers
/// they care about with [ListenableBuilder], so rebuilds stay scoped to the
/// parts of the screen that actually change.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.auth,
    required this.doctorLinks,
    required this.checkIns,
    required this.monitoring,
    required this.medications,
    required super.child,
  });

  final AuthController auth;
  final DoctorLinkController doctorLinks;
  final CheckInController checkIns;
  final MonitoringController monitoring;
  final MedicationController medications;

  static AppScope of(BuildContext context) {
    final AppScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
