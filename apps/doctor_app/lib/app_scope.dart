import 'package:flutter/widgets.dart';

import 'features/auth/state/auth_controller.dart';
import 'features/patients/state/assignment_controller.dart';
import 'features/roster/state/roster_controller.dart';

/// Provides the application's controllers to the widget tree.
///
/// A plain [InheritedWidget] is enough here: widgets listen to the controllers
/// they care about with [ListenableBuilder], so rebuilds stay scoped to the
/// parts of the screen that actually change.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.auth,
    required this.roster,
    required this.assignments,
    required super.child,
  });

  final AuthController auth;
  final RosterController roster;
  final AssignmentController assignments;

  static AppScope of(BuildContext context) {
    final AppScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
