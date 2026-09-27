import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../auth/presentation/auth_flow.dart';
import '../auth/presentation/splash_screen.dart';
import '../auth/state/auth_controller.dart';
import 'intro_prefs.dart';
import 'onboarding_screen.dart';
import 'welcome_screen.dart';

enum _IntroStage { onboarding, welcome, auth }

/// First-time experience orchestrator:
///
/// splash -> onboarding (once) -> welcome -> authentication.
///
/// Returning patients go straight from the splash to the authentication
/// screens, and authenticated patients go straight home (decided above).
class IntroFlow extends StatefulWidget {
  const IntroFlow({super.key});

  @override
  State<IntroFlow> createState() => _IntroFlowState();
}

class _IntroFlowState extends State<IntroFlow> {
  /// The splash entrance plays in full before anything else appears.
  static const Duration _splashMinimum = Duration(milliseconds: 1600);

  bool _splashElapsed = false;
  bool _prefsLoaded = false;
  bool _seenOnboarding = false;
  _IntroStage _stage = _IntroStage.onboarding;
  bool _initialSignUp = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_splashMinimum, () {
      if (mounted) {
        setState(() => _splashElapsed = true);
      }
    });
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final bool seen = await IntroPrefs.hasSeenOnboarding();
    if (mounted) {
      setState(() {
        _seenOnboarding = seen;
        _prefsLoaded = true;
      });
    }
  }

  void _completeOnboarding() {
    // Move immediately; persisting the flag happens in the background so a
    // slow secure-storage write never delays the experience.
    setState(() {
      _seenOnboarding = true;
      _stage = _IntroStage.welcome;
    });
    unawaited(IntroPrefs.markSeenOnboarding());
  }

  void _openAuth({required bool signUp}) {
    setState(() {
      _initialSignUp = signUp;
      _stage = _IntroStage.auth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;
    final bool showSplash =
        auth.status == AuthStatus.checking || !_splashElapsed || !_prefsLoaded;

    if (showSplash) {
      return const SplashScreen();
    }

    // Returning patients skip the intro entirely; patients who just finished
    // onboarding move through welcome according to the current stage.
    if (_seenOnboarding && _stage == _IntroStage.onboarding) {
      return const AuthFlow();
    }

    switch (_stage) {
      case _IntroStage.onboarding:
        return OnboardingScreen(onFinished: _completeOnboarding);
      case _IntroStage.welcome:
        return WelcomeScreen(
          onCreateAccount: () => _openAuth(signUp: true),
          onSignIn: () => _openAuth(signUp: false),
        );
      case _IntroStage.auth:
        return AuthFlow(initialShowSignUp: _initialSignUp);
    }
  }
}
