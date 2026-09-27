import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/intro/visuals/movement_mark.dart';

/// Dark, minimal launch screen: the mark draws itself in, then the wordmark
/// fades beneath it. No spinner, no progress text - the session check runs
/// quietly behind the entrance.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  late final Animation<double> _markProgress = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.62, curve: Curves.easeInOutCubic),
  );

  late final Animation<double> _wordmarkOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                return MovementMark(
                  progress: _markProgress.value,
                  color: scheme.primary,
                  size: const Size(132, 72),
                );
              },
            ),
            const SizedBox(height: 26),
            FadeTransition(
              opacity: _wordmarkOpacity,
              child: Padding(
                // Optical centering: letter spacing adds a trailing gap.
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  'NeuroSync',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 6,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
