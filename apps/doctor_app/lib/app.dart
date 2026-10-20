import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';
import 'package:neurosync_core/widgets/splash_screen.dart';
import 'package:flutter/services.dart';

import 'app/portal_shell.dart';
import 'app_scope.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/exceptions/state/exception_controller.dart';
import 'features/patients/state/assignment_controller.dart';
import 'features/roster/presentation/profile_sheet.dart';
import 'features/roster/state/roster_controller.dart';

/// Root widget: decides between splash, login and home from auth state.
class NeuroSyncDoctorApp extends StatelessWidget {
  const NeuroSyncDoctorApp({
    super.key,
    required this.authController,
    required this.rosterController,
    required this.assignmentController,
    required this.exceptionController,
  });

  final AuthController authController;
  final RosterController rosterController;
  final AssignmentController assignmentController;
  final ExceptionController exceptionController;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: authController,
      roster: rosterController,
      assignments: assignmentController,
      exceptions: exceptionController,
      child: MaterialApp(
        title: 'NeuroSync Doctor',
        debugShowCheckedModeBanner: false,
        // The same palette and typography system as the patient app: one
        // dark theme, Apple-style, so the two sides of the product feel
        // like one product.
        theme: AppTheme.dark(),
        builder: (BuildContext context, Widget? child) =>
            AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          child: child!,
        ),
        home: const _RootView(),
      ),
    );
  }
}

class _RootView extends StatelessWidget {
  const _RootView();

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;

    return ListenableBuilder(
      listenable: auth,
      builder: (BuildContext context, Widget? child) {
        switch (auth.status) {
          case AuthStatus.signedIn:
            return PortalShell(
              doctorName: auth.doctor?.name ?? '',
              onOpenProfile: () => showProfileSheet(context),
              onSignOut: () => AppScope.of(context).auth.signOut(),
            );
          case AuthStatus.checking:
            return const SplashScreen();
          case AuthStatus.signedOut:
            return const LoginScreen();
        }
      },
    );
  }
}
