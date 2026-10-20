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
class NeuroSyncDoctorApp extends StatefulWidget {
  const NeuroSyncDoctorApp({
    super.key,
    required this.authController,
    required this.rosterController,
    required this.assignmentController,
    required this.exceptionController,
    required this.themeController,
  });

  final AuthController authController;
  final RosterController rosterController;
  final AssignmentController assignmentController;
  final ExceptionController exceptionController;

  /// Which mood the application is in, and the doctor's choice of it.
  final ThemeController themeController;

  @override
  State<NeuroSyncDoctorApp> createState() => _NeuroSyncDoctorAppState();
}

class _NeuroSyncDoctorAppState extends State<NeuroSyncDoctorApp> {
  @override
  void initState() {
    super.initState();
    // The mood is read before the first frame, so the portal opens in the one
    // the doctor last chose rather than flashing the wrong one.
    widget.themeController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: widget.authController,
      roster: widget.rosterController,
      assignments: widget.assignmentController,
      exceptions: widget.exceptionController,
      theme: widget.themeController,
      child: ListenableBuilder(
        listenable: widget.themeController,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            title: 'NeuroSync Doctor',
            debugShowCheckedModeBanner: false,
            // The same palette and typography system as the patient app: warm
            // ivory for a bright clinic, slate for a dim one, so the two sides
            // of the product feel like one product.
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: widget.themeController.value,
            builder: (BuildContext context, Widget? child) =>
                AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    widget.themeController.value == ThemeMode.dark
                        ? Brightness.light
                        : Brightness.dark,
                statusBarBrightness:
                    widget.themeController.value == ThemeMode.dark
                        ? Brightness.dark
                        : Brightness.light,
              ),
              child: child!,
            ),
            home: const _RootView(),
          );
        },
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
