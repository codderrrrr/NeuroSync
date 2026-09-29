import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/core/theme/app_theme.dart';

/// WCAG 2.1 relative luminance of a colour.
double _luminance(Color color) {
  double linear(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

/// WCAG 2.1 contrast ratio between two opaque colours.
double _contrast(Color foreground, Color background) {
  final double a = _luminance(foreground);
  final double b = _luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// What a signal chip's background actually ends up as: its tint composited
/// over the card it sits on.
Color _tintedSurface(Color tint, Color surface) =>
    Color.alphaBlend(tint, surface);

void main() {
  group('readability', () {
    test('body text clears AAA on the page and on a card', () {
      expect(_contrast(AppTheme.darkLabel, AppTheme.darkBackground),
          greaterThanOrEqualTo(7));
      expect(_contrast(AppTheme.darkLabel, AppTheme.darkSurface),
          greaterThanOrEqualTo(7));
    });

    test('supporting text clears AA on the page and on a card', () {
      // 60% white is translucent, so what the eye sees is the composite.
      expect(
          _contrast(
              _tintedSurface(
                  AppTheme.darkSecondaryLabel, AppTheme.darkBackground),
              AppTheme.darkBackground),
          greaterThanOrEqualTo(4.5));
      expect(
          _contrast(
              _tintedSurface(AppTheme.darkSecondaryLabel, AppTheme.darkSurface),
              AppTheme.darkSurface),
          greaterThanOrEqualTo(4.5));
    });

    test('the accent reads as text and can carry a label', () {
      expect(_contrast(AppTheme.accentMint, AppTheme.darkBackground),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppTheme.accentMint, AppTheme.darkSurface),
          greaterThanOrEqualTo(4.5));
      // Label on a filled button: the dark teal used as onPrimary, not the
      // page grey, which would fall short of AA on this accent.
      expect(_contrast(const Color(0xFF003548), AppTheme.accentMint),
          greaterThanOrEqualTo(4.5));
    });

    test('every clinical signal clears AA on the page, a card and its chip',
        () {
      const Map<String, Color> signals = <String, Color>{
        'pending': AppTheme.pending,
        'active': AppTheme.active,
        'danger': AppTheme.danger,
      };
      const Map<String, Color> tints = <String, Color>{
        'pending': AppTheme.pendingTint,
        'active': AppTheme.activeTint,
      };

      signals.forEach((String name, Color color) {
        expect(_contrast(color, AppTheme.darkBackground),
            greaterThanOrEqualTo(4.5),
            reason: '$name on the page');
        expect(
            _contrast(color, AppTheme.darkSurface), greaterThanOrEqualTo(4.5),
            reason: '$name on a card');
        final Color? tint = tints[name];
        if (tint != null) {
          expect(
            _contrast(
              color,
              _tintedSurface(tint, AppTheme.darkSurface),
            ),
            greaterThanOrEqualTo(4.5),
            reason: '$name inside its own chip',
          );
        }
      });
    });
  });

  group('the palette is Apple Dark Mode, not a warm room', () {
    test('the neutrals are colourless greys', () {
      const List<Color> neutrals = <Color>[
        AppTheme.darkBackground,
        AppTheme.darkSurface,
        AppTheme.darkSurfaceSecondary,
        AppTheme.darkSeparator,
        AppTheme.darkLabel,
      ];

      for (final Color neutral in neutrals) {
        final HSLColor hsl = HSLColor.fromColor(neutral);
        // Colourless in practice: Apple's system greys carry a trace of blue
        // (about 3% on #1C1C1E). Anything past this is a tinted room.
        expect(hsl.saturation, lessThanOrEqualTo(0.04), reason: '$neutral');
      }
    });

    test('the accent is system teal, saturated enough to hold on grey', () {
      final HSLColor accent = HSLColor.fromColor(AppTheme.accentMint);
      // System Teal sits near 197 deg. Sage was 125-150; that range must fail.
      expect(accent.hue, inInclusiveRange(185, 210));
      expect(accent.saturation, greaterThanOrEqualTo(0.8));
    });

    test('there is no separate warm highlight', () {
      expect(AppTheme.warmHighlight, AppTheme.accentMint);
    });

    test('the theme is dark, and the page uses the base colour', () {
      final ThemeData theme = AppTheme.dark();

      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppTheme.darkBackground);
      expect(theme.colorScheme.surface, AppTheme.darkSurface);
      expect(theme.colorScheme.onSurface, AppTheme.darkLabel);
      expect(theme.colorScheme.onSurfaceVariant, AppTheme.darkSecondaryLabel);
    });
  });
}
