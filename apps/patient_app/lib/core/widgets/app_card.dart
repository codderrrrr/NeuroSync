import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// White rounded card used for grouped content.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

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
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}
