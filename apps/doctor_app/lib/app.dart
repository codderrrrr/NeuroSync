import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/patients/state/assignment_controller.dart';
import 'features/roster/presentation/home_screen.dart';
import 'features/roster/state/roster_controller.dart';

/// Root widget: decides between splash, login and home from auth state.
class NeuroSyncDoctorApp extends StatelessWidget {
  const NeuroSyncDoctorApp({
    super.key,
    required this.authController,
    required this.rosterController,
    required this.assignmentController,
  });

  final AuthController authController;
  final RosterController rosterController;
  final AssignmentController assignmentController;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: authController,
      roster: rosterController,
      assignments: assignmentController,
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
            return const HomeScreen();
          case AuthStatus.checking:
            return const _SplashScreen();
          case AuthStatus.signedOut:
            return const LoginScreen();
        }
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'NeuroSync',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
