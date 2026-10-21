import 'package:flutter/material.dart';

/// Responsive type scale for the first-time experience.
///
/// Onboarding headlines are display text, not body text: on a short viewport
/// or at large system text sizes they shrink, while body and caption text
/// stay near the comfortable reading range. This keeps the composition intact
/// instead of letting a 34pt headline squeeze the visual out of the screen.
///
/// The scale follows the viewport, deliberately not the keyboard: a title that
/// changed size when a keyboard opened would be worse than one that does not.
/// Screens that must survive a keyboard derive their layout from the space
/// they are actually given, which the Scaffold already reduces.
class IntroScale {
  const IntroScale._(this.ratio);

  /// 1.0 on a normal-height device, down to [_minRatio] on very short ones.
  final double ratio;

  static const double _minRatio = 0.74;

  factory IntroScale.of(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    // Full height is the reference; landscape and split views compress.
    final double ratio = (media.size.height / 820).clamp(_minRatio, 1.0);
    return IntroScale._(ratio);
  }

  /// Display headline. Never below ~25pt even at the minimum compression.
  double get headline => _s(30, min: 25);

  /// Lead paragraph under the headline.
  double get body => _s(16, min: 15);

  /// Chapter kicker and other uppercase captions.
  double get kicker => _s(12, min: 11);

  /// Footnotes and quiet supporting text.
  double get footnote => _s(13, min: 12);

  /// Primary control label. Stays comfortably readable at all times.
  double get buttonLabel => _s(17, min: 16);

  double _s(double base, {required double min}) =>
      (base * ratio).clamp(min, double.infinity);

  TextTheme apply(TextTheme base) => base.copyWith(
        titleLarge: base.titleLarge?.copyWith(fontSize: headline),
        bodyLarge: base.bodyLarge?.copyWith(fontSize: body),
        bodyMedium: base.bodyMedium?.copyWith(fontSize: footnote),
        labelLarge: base.labelLarge?.copyWith(fontSize: buttonLabel),
      );
}

/// Wraps the first-time experience in a bounded text scale.
///
/// Reading this text above ~1.3x trades legibility for a broken layout, so
/// the scale is clamped within this subtree only - the signed-in screens stay
/// faithful to the system setting.
class IntroTextScale extends StatelessWidget {
  const IntroTextScale({super.key, required this.child});

  static const double _min = 1.0;
  static const double _max = 1.3;

  final Widget child;

  static double clampedOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1).clamp(_min, _max);

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(1);
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale.clamp(_min, _max))),
      child: child,
    );
  }
}

/// Caps the measure of a block of copy so it never stretches edge to edge on
/// a rotated phone or a tablet.
class ReadingWidth extends StatelessWidget {
  const ReadingWidth({
    super.key,
    required this.child,
    this.maxWidth = 420,
    this.align = Alignment.centerLeft,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry align;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
