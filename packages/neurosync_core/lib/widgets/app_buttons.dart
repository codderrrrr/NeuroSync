import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'tactile_button.dart';

/// Filled primary action with an inline loading state.
///
/// On dark, FilledButton's ambient elevation paints the accent colour as a
/// glow around the control, so the control is deliberately flat and gains its
/// presence from the fill itself. Disabled is an opaque neutral surface rather
/// than translucent accent, which reads as muddy on a dark background.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.tactile = false,
    this.labelFontSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Adds the press response. Enabled by the dark first-time experience only.
  final bool tactile;

  /// The label size. Left unset, the label is the fixed portal size.
  final double? labelFontSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool enabled = isLoading ? false : onPressed != null;
    final Widget button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor:
            enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.07),
        foregroundColor: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
        // Pressed stays inside the accent family instead of adding a
        // translucent wash on top of it.
        overlayColor: const Color(0x1F000000),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.fieldRadius),
        ),
        textStyle: TextStyle(
          fontSize: labelFontSize ?? 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: scheme.onPrimary),
            )
          : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return SizedBox(
      height: AppTheme.controlHeight,
      child: tactile ? TactileButton(enabled: enabled, child: button) : button,
    );
  }
}

/// Card-style secondary action.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.tactile = false,
    this.labelFontSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool tactile;

  /// The label size. Left unset, the label is the fixed portal size.
  final double? labelFontSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // On a dark background a hairline is the only thing that separates a
    // control surface from the page; on light the card already stands off it.
    final BorderSide? hairline = scheme.brightness == Brightness.dark
        ? BorderSide(color: scheme.outline)
        : null;
    final Widget button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: color ?? scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: hairline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.fieldRadius),
        ),
        textStyle: TextStyle(
          fontSize: labelFontSize ?? 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return SizedBox(
      height: AppTheme.controlHeight,
      child: tactile
          ? TactileButton(enabled: onPressed != null, child: button)
          : button,
    );
  }
}
