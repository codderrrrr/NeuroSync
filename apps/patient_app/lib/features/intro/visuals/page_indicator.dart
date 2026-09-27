import 'package:flutter/material.dart';

/// Refined segmented page indicator for the onboarding experience.
///
/// The active segment widens into a small capsule instead of a heavy dot,
/// keeping the control quiet and native-feeling.
class PageIndicator extends StatelessWidget {
  const PageIndicator(
      {super.key, required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < count; i++) ...<Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            width: i == activeIndex ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == activeIndex
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
