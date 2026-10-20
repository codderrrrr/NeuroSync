import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/check_ins/state/check_in_controller.dart';
import 'features/doctor_links/state/doctor_link_controller.dart';
import 'features/intro/intro_flow.dart';
import 'features/medication/state/medication_controller.dart';
import 'features/monitoring/state/monitoring_controller.dart';
import 'features/shell/presentation/main_shell.dart';

/// Root widget: decides between splash, login and home from auth state.
class NeuroSyncApp extends StatefulWidget {
  const NeuroSyncApp({
    super.key,
    required this.authController,
    required this.doctorLinkController,
    required this.checkInController,
    required this.monitoringController,
    required this.medicationController,
    required this.themeController,
  });

  final AuthController authController;
  final DoctorLinkController doctorLinkController;
  final CheckInController checkInController;
  final MonitoringController monitoringController;
  final MedicationController medicationController;

  /// Which mood the application is in, and the patient's choice of it.
  final ThemeController themeController;

  @override
  State<NeuroSyncApp> createState() => _NeuroSyncAppState();
}

class _NeuroSyncAppState extends State<NeuroSyncApp> {
  @override
  void initState() {
    super.initState();
    // Check for an existing session exactly once, on launch.
    widget.authController.restoreSession();
    // The mood is read before the first frame, so the app opens in the one
    // the patient last chose rather than flashing the wrong one.
    widget.themeController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: widget.authController,
      doctorLinks: widget.doctorLinkController,
      checkIns: widget.checkInController,
      monitoring: widget.monitoringController,
      medications: widget.medicationController,
      theme: widget.themeController,
      child: ListenableBuilder(
        listenable: widget.themeController,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            title: 'NeuroSync',
            debugShowCheckedModeBanner: false,
            // Two moods, one palette: the warm ivory for daylight, the slate
            // for the evening and the bedside. The patient chooses.
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
            // The shell, not HomeScreen directly: check-ins and doctor
            // linking live on their own tabs and are otherwise unreachable.
            return const MainShell();
          case AuthStatus.checking:
          case AuthStatus.signedOut:
            return const IntroFlow();
        }
      },
    );
  }
}
