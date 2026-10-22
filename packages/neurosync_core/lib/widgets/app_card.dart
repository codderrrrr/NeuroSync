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
    final BorderRadius radius = BorderRadius.circular(AppTheme.cardRadius);

    // The card is a Material, and the ink is printed on it. A card that is a
    // plain Container has nothing for a splash to land on, so a press on the
    // card would leave no mark at all - and a press that leaves no mark is a
    // press the patient cannot tell landed.
    final Widget content = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: child,
    );

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          // The InkWell is inside the Material, so the splash lands on the
          // card the patient is pressing rather than behind it.
          : InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: content,
            ),
    );
  }
}
