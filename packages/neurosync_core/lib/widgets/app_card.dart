import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// White rounded card used for grouped content.
///
/// Pass [onTap] when the whole card should act as one control, so the tap
/// target matches what the eye reads as a single object rather than shrinking
/// it to whatever text happens to be inside.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Light mode keeps the familiar soft shadow; on dark surfaces a shadow
    // would only muddy the composition, so the surface color carries it.
    final List<BoxShadow>? shadow = theme.brightness == Brightness.light
        ? const <BoxShadow>[
            BoxShadow(
                color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))
          ]
        : null;
    final Widget card = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: shadow,
      ),
      child: child,
    );

    if (onTap == null) {
      return card;
    }
    // Clipped so the ink highlight follows the rounded corners instead of
    // spilling into a rectangle behind them.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
