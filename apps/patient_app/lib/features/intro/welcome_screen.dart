import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import 'visuals/movement_mark.dart';

/// The calm conclusion of onboarding: two ways into authentication.
///
/// The mark draws itself in again rather than waiting as a static logo, so
/// arriving here reads as a continuation of the chapters instead of a new
/// screen that happens to share the palette.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onCreateAccount,
    required this.onSignIn,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final IntroScale scale = IntroScale.of(context);
    final double margin = MediaQuery.sizeOf(context).width < 360 ? 20 : 24;

    return Scaffold(
      body: IntroTextScale(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(margin, 8, margin, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Center(
                    // Centred while it fits, scrollable rather than clipped in
                    // landscape or at large text sizes.
                    child: SingleChildScrollView(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder:
                            (BuildContext context, double t, Widget? child) {
                          return Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, (1 - t) * 12),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 1100),
                              curve: Curves.easeInOutCubic,
                              builder:
                                  (BuildContext context, double t, Widget? _) =>
                                      MovementMark(
                                progress: t,
                                color: scheme.primary,
                                size: const Size(96, 54),
                              ),
                            ),
                            const SizedBox(height: 36),
                            ReadingWidth(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'Welcome to NeuroSync.',
                                    style: TextStyle(
                                      fontSize: scale.headline + 4,
                                      height: 1.1,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.6,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Your care journey, connected.',
                                    style: TextStyle(
                                      fontSize: scale.body + 1,
                                      height: 1.4,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Create account',
                  onPressed: onCreateAccount,
                  tactile: true,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Sign in',
                  onPressed: onSignIn,
                  tactile: true,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Your information is protected.',
                    style: TextStyle(
                      fontSize: scale.footnote,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
