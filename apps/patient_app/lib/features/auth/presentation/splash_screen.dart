import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/intro_scale.dart';
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
  /// Short enough not to feel like a wait, long enough for the mark to read as
  /// a deliberate entrance rather than a flash.
  static const Duration _entrance = Duration(milliseconds: 1100);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _entrance,
  );

  late final Animation<double> _markProgress = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.62, curve: Curves.easeInOutCubic),
  );

  late final Animation<double> _wordmarkOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With system animation turned off the mark appears finished and the
    // wordmark fully faded in, rather than animating to a state the patient
    // has asked not to be shown.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The stage can be rebuilt while the entrance is still running; restart it
    // so a reduced-motion change takes effect immediately.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: IntroTextScale(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedBuilder(
                  animation: _controller,
                  builder: (BuildContext context, Widget? child) =>
                      MovementMark(
                    progress: _markProgress.value,
                    color: scheme.primary,
                    size: const Size(132, 72),
                  ),
                ),
                const SizedBox(height: 26),
                AnimatedBuilder(
                  animation: _wordmarkOpacity,
                  builder: (BuildContext context, Widget? child) => Opacity(
                    opacity: _wordmarkOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - _wordmarkOpacity.value) * 6),
                      child: child,
                    ),
                  ),
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
        ),
      ),
    );
  }
}
