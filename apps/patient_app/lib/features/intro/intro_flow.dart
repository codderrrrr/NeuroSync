import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

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
  /// A short floor so the mark never flashes past. The real gate is the
  /// session check and the preferences read; when both are already done the
  /// patient moves on as soon as this minimum has passed, rather than waiting
  /// out a fixed duration.
  static const Duration _splashMinimum = Duration(milliseconds: 900);

  bool _splashElapsed = false;
  bool _prefsLoaded = false;
  bool _seenOnboarding = false;
  _IntroStage _stage = _IntroStage.onboarding;
  bool _initialSignUp = false;

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.delayed(_splashMinimum, () {
      if (mounted) {
        setState(() => _splashElapsed = true);
      }
    }));
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final bool seen = await IntroPrefs.hasSeenOnboarding();
    if (!mounted) {
      return;
    }
    setState(() {
      _seenOnboarding = seen;
      _prefsLoaded = true;
    });
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
      return _crossfade(const SplashScreen());
    }

    // Returning patients skip the intro entirely; patients who just finished
    // onboarding move through welcome according to the current stage.
    if (_seenOnboarding && _stage == _IntroStage.onboarding) {
      return _crossfade(const AuthFlow());
    }

    final Widget stage;
    switch (_stage) {
      case _IntroStage.onboarding:
        stage = OnboardingScreen(onFinished: _completeOnboarding);
      case _IntroStage.welcome:
        stage = WelcomeScreen(
          onCreateAccount: () => _openAuth(signUp: true),
          onSignIn: () => _openAuth(signUp: false),
        );
      case _IntroStage.auth:
        stage = AuthFlow(initialShowSignUp: _initialSignUp);
    }
    return _crossfade(stage);
  }

  /// Every stage of the first-time experience sits on the app's own base and
  /// hands over with a short crossfade, so neither the handover between
  /// stages nor the frame behind them can flash another colour.
  Widget _crossfade(Widget child) => ColoredBox(
        color: AppColors.of(context).background,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: child,
        ),
      );
}
