import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/doctor_links/state/doctor_link_controller.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/intro/intro_flow.dart';

/// Root widget: decides between splash, login and home from auth state.
class NeuroSyncApp extends StatefulWidget {
  const NeuroSyncApp({
    super.key,
    required this.authController,
    required this.doctorLinkController,
    required this.checkInController,
    required this.monitoringController,
  });

  final AuthController authController;
  final DoctorLinkController doctorLinkController;
  final CheckInController checkInController;
  final MonitoringController monitoringController;

  @override
  State<NeuroSyncApp> createState() => _NeuroSyncAppState();
}

class _NeuroSyncAppState extends State<NeuroSyncApp> {
  @override
  void initState() {
    super.initState();
    // Check for an existing session exactly once, on launch.
    widget.authController.restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: widget.authController,
      doctorLinks: widget.doctorLinkController,
      checkIns: widget.checkInController,
      monitoring: widget.monitoringController,
      child: MaterialApp(
        title: 'NeuroSync',
        debugShowCheckedModeBanner: false,
        // One theme for the whole app: dark, warm, and the same palette the
        // first-time experience uses, so signing in changes screens and not
        // worlds.
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
            return const HomeScreen();
          case AuthStatus.checking:
          case AuthStatus.signedOut:
            return const IntroFlow();
        }
      },
    );
  }
}
