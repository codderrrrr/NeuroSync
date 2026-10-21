import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The sizes the controls are built at.
///
/// A phone in a hand and a desktop in a clinic want different amounts of
/// space, so the sizes are part of the theme rather than fixed: the patient
/// app asks for a compact set, the portal for a comfortable one.
///
/// The floor is 48dp, which is above the 44dp minimum a fingertip needs, so
/// a control is still comfortable to hit with a hand that is not steady.
@immutable
class AppMetrics extends ThemeExtension<AppMetrics> {
  const AppMetrics({
    required this.primaryControlHeight,
    required this.secondaryControlHeight,
    required this.textScale,
  });

  /// The height of a primary control: the one a patient is asked to press.
  final double primaryControlHeight;

  /// The height of a secondary control.
  final double secondaryControlHeight;

  /// How much the type scale is multiplied by.
  final double textScale;

  /// The sizes the doctor portal uses: a mouse, a desk, a big screen.
  static const AppMetrics comfortable = AppMetrics(
    primaryControlHeight: 72,
    secondaryControlHeight: 56,
    textScale: 1,
  );

  /// The sizes the patient app uses: a phone, held in one hand, often by
  /// someone who is not young.
  static const AppMetrics compact = AppMetrics(
    primaryControlHeight: 60,
    secondaryControlHeight: 48,
    textScale: 0.88,
  );

  /// The sizes of the mood [context] is currently in.
  static AppMetrics of(BuildContext context) =>
      Theme.of(context).extension<AppMetrics>() ?? comfortable;

  @override
  AppMetrics copyWith({
    double? primaryControlHeight,
    double? secondaryControlHeight,
    double? textScale,
  }) {
    return AppMetrics(
      primaryControlHeight: primaryControlHeight ?? this.primaryControlHeight,
      secondaryControlHeight:
          secondaryControlHeight ?? this.secondaryControlHeight,
      textScale: textScale ?? this.textScale,
    );
  }

  @override
  AppMetrics lerp(ThemeExtension<AppMetrics>? other, double t) {
    if (other is! AppMetrics) {
      return this;
    }
    return AppMetrics(
      primaryControlHeight:
          lerpDouble(primaryControlHeight, other.primaryControlHeight, t)!,
      secondaryControlHeight:
          lerpDouble(secondaryControlHeight, other.secondaryControlHeight, t)!,
      textScale: lerpDouble(textScale, other.textScale, t)!,
    );
  }
}
