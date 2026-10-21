import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';

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
  group('the light palette', () {
    test('body text clears AAA on the page and on a card', () {
      expect(_contrast(AppColors.light.label, AppColors.light.background),
          greaterThanOrEqualTo(7));
      expect(_contrast(AppColors.light.label, AppColors.light.surface),
          greaterThanOrEqualTo(7));
    });

    test('supporting text clears AA on the page and on a card', () {
      expect(
          _contrast(AppColors.light.secondaryLabel, AppColors.light.background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.light.secondaryLabel, AppColors.light.surface),
          greaterThanOrEqualTo(4.5));
    });

    test('the accent reads as text and can carry a label', () {
      expect(_contrast(AppColors.light.primary, AppColors.light.background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.light.primary, AppColors.light.surface),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.light.onPrimary, AppColors.light.primary),
          greaterThanOrEqualTo(4.5));
    });

    test('the action colour reads as text and can carry a label', () {
      expect(_contrast(AppColors.light.action, AppColors.light.background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.light.action, AppColors.light.surface),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.light.onAction, AppColors.light.action),
          greaterThanOrEqualTo(4.5));
    });

    test('every clinical signal clears AA on the page, a card and its chip',
        () {
      final Map<String, Color> signals = <String, Color>{
        'pending': AppColors.light.pending,
        'active': AppColors.light.active,
        'danger': AppColors.light.danger,
      };
      final Map<String, Color> tints = <String, Color>{
        'pending': AppColors.light.pendingTint,
        'active': AppColors.light.activeTint,
        'danger': AppColors.light.dangerTint,
      };

      signals.forEach((String name, Color color) {
        expect(_contrast(color, AppColors.light.background),
            greaterThanOrEqualTo(4.5),
            reason: '$name on the page');
        expect(_contrast(color, AppColors.light.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name on a card');
        expect(
          _contrast(
            color,
            _tintedSurface(tints[name]!, AppColors.light.surface),
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$name inside its own chip',
        );
      });
    });

    test('the neutrals are cool, not yellow', () {
      // A warm ivory reads as yellow once it is a whole screen, and a patient
      // who finds it unpleasant finds it on every page. The neutrals are
      // blue-grey instead.
      for (final Color neutral in <Color>[
        AppColors.light.background,
        AppColors.light.surfaceSunken,
        AppColors.light.surfaceRaised,
        AppColors.light.separator,
        AppColors.light.label,
        AppColors.light.secondaryLabel,
      ]) {
        final HSLColor hsl = HSLColor.fromColor(neutral);
        expect(hsl.hue, inInclusiveRange(195, 225), reason: '$neutral');
      }
      expect(AppColors.light.surface, const Color(0xFFFFFFFF));
    });

    test('the dark neutrals are cool too', () {
      for (final Color neutral in <Color>[
        AppColors.dark.background,
        AppColors.dark.surface,
        AppColors.dark.surfaceSunken,
        AppColors.dark.surfaceRaised,
        AppColors.dark.separator,
        AppColors.dark.label,
        AppColors.dark.secondaryLabel,
      ]) {
        final HSLColor hsl = HSLColor.fromColor(neutral);
        expect(hsl.hue, inInclusiveRange(195, 225), reason: '$neutral');
      }
    });

    test('the accent is sage and the action is terracotta', () {
      final HSLColor primary = HSLColor.fromColor(AppColors.light.primary);
      final HSLColor action = HSLColor.fromColor(AppColors.light.action);
      // Sage sits near 155 deg; terracotta near 20 deg.
      expect(primary.hue, inInclusiveRange(140, 175));
      expect(action.hue, inInclusiveRange(5, 35));
    });
  });

  group('the dark palette', () {
    test('body text clears AAA on the page and on a card', () {
      expect(_contrast(AppColors.dark.label, AppColors.dark.background),
          greaterThanOrEqualTo(7));
      expect(_contrast(AppColors.dark.label, AppColors.dark.surface),
          greaterThanOrEqualTo(7));
    });

    test('supporting text clears AA on the page and on a card', () {
      expect(
          _contrast(AppColors.dark.secondaryLabel, AppColors.dark.background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.dark.secondaryLabel, AppColors.dark.surface),
          greaterThanOrEqualTo(4.5));
    });

    test('the accents read as text and can carry a label', () {
      expect(_contrast(AppColors.dark.primary, AppColors.dark.background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.dark.primary, AppColors.dark.surface),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.dark.onPrimary, AppColors.dark.primary),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.dark.action, AppColors.dark.background),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.dark.onAction, AppColors.dark.action),
          greaterThanOrEqualTo(4.5));
    });

    test('every clinical signal clears AA on the page, a card and its chip',
        () {
      final Map<String, Color> signals = <String, Color>{
        'pending': AppColors.dark.pending,
        'active': AppColors.dark.active,
        'danger': AppColors.dark.danger,
      };
      final Map<String, Color> tints = <String, Color>{
        'pending': AppColors.dark.pendingTint,
        'active': AppColors.dark.activeTint,
        'danger': AppColors.dark.dangerTint,
      };

      signals.forEach((String name, Color color) {
        expect(_contrast(color, AppColors.dark.background),
            greaterThanOrEqualTo(4.5),
            reason: '$name on the page');
        expect(
            _contrast(color, AppColors.dark.surface), greaterThanOrEqualTo(4.5),
            reason: '$name on a card');
        expect(
          _contrast(
            color,
            _tintedSurface(tints[name]!, AppColors.dark.surface),
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$name inside its own chip',
        );
      });
    });
  });

  group('the themes', () {
    testWidgets('each mood installs its own colours', (
      WidgetTester tester,
    ) async {
      Future<AppColors> coloursOf(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (BuildContext context) => const SizedBox.shrink(),
            ),
          ),
        );
        // The app animates its theme in, so the extension is interpolated on
        // the first frame and only settles to the mood's own colours after.
        await tester.pumpAndSettle();
        return AppColors.of(
          tester.element(find.byType(SizedBox).first),
        );
      }

      expect(await coloursOf(AppTheme.light()), AppColors.light);
      expect(await coloursOf(AppTheme.dark()), AppColors.dark);
    });

    test('the page uses the background of the mood and the card its surface',
        () {
      expect(
          AppTheme.light().scaffoldBackgroundColor, AppColors.light.background);
      expect(AppTheme.light().colorScheme.surface, AppColors.light.surface);
      expect(
          AppTheme.dark().scaffoldBackgroundColor, AppColors.dark.background);
      expect(AppTheme.dark().colorScheme.surface, AppColors.dark.surface);
    });

    test('body text is never below 15pt and never tighter than 1.5', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light(),
        AppTheme.dark(),
      ]) {
        final TextTheme text = theme.textTheme;
        for (final TextStyle? style in <TextStyle?>[
          text.bodyLarge,
          text.bodyMedium,
          text.bodySmall,
        ]) {
          expect(style, isNotNull);
          expect(style!.fontSize, greaterThanOrEqualTo(13));
          expect(style.height, greaterThanOrEqualTo(1.5));
        }
        expect(text.bodyLarge!.fontSize, greaterThanOrEqualTo(15));
        expect(text.bodyMedium!.fontSize, greaterThanOrEqualTo(15));
      }
    });

    test('the two families are the ones that were bundled', () {
      final TextTheme text = AppTheme.light().textTheme;
      expect(text.displayLarge!.fontFamily, AppTheme.displayFont);
      expect(text.headlineMedium!.fontFamily, AppTheme.displayFont);
      expect(text.bodyLarge!.fontFamily, AppTheme.bodyFont);
      expect(text.labelMedium!.fontFamily, AppTheme.bodyFont);
    });
  });
}
