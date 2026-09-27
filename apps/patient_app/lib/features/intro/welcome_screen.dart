import 'package:flutter/material.dart';

import '../../core/widgets/app_buttons.dart';
import 'visuals/movement_mark.dart';

/// The calm conclusion of onboarding: two ways into authentication.
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
    return Scaffold(
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double t, Widget? child) {
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 12),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const MovementMark(progress: 1, size: Size(96, 54)),
                      const SizedBox(height: 40),
                      Text(
                        'Welcome to NeuroSync.',
                        style: TextStyle(
                          fontSize: 36,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.6,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your care journey, connected.',
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PrimaryButton(
                    label: 'Create account', onPressed: onCreateAccount),
                const SizedBox(height: 12),
                SecondaryButton(label: 'Sign in', onPressed: onSignIn),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Your information is protected.',
                    style: TextStyle(
                      fontSize: 13,
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
