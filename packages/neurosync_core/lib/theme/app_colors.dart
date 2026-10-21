import 'package:flutter/material.dart';

/// NeuroSync's colour system, in both its moods.
///
/// The palette is warm and organic rather than clinical blue: a sage green
/// carries the brand, a muted terracotta carries the action that asks
/// something of the patient, and the surfaces are a warm ivory that reads as
/// paper rather than as a screen.
///
/// A [ThemeExtension] rather than a set of constants, because the same token
/// has to mean two things: ink on ivory in the light, and ink on slate in the
/// dark. A constant cannot answer "which one is this?".
///
/// Read a token with [AppColors.of]:
/// ```dart
/// Text('Hello', style: TextStyle(color: AppColors.of(context).label))
/// ```
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceRaised,
    required this.label,
    required this.secondaryLabel,
    required this.separator,
    required this.primary,
    required this.onPrimary,
    required this.action,
    required this.onAction,
    required this.pending,
    required this.active,
    required this.danger,
    required this.pendingTint,
    required this.activeTint,
    required this.dangerTint,
  });

  /// The page behind everything.
  final Color background;

  /// A card or panel sitting on the page.
  final Color surface;

  /// A well inside a card: a field fill, a track.
  final Color surfaceSunken;

  /// A control that sits above a card.
  final Color surfaceRaised;

  /// Primary text.
  final Color label;

  /// Supporting text: the quiet half of the hierarchy.
  final Color secondaryLabel;

  /// Hairline separators.
  final Color separator;

  /// The brand colour: sage green.
  final Color primary;

  /// Text on a sage green fill.
  final Color onPrimary;

  /// The colour that asks something of the patient: muted terracotta.
  final Color action;

  /// Text on a terracotta fill.
  final Color onAction;

  /// Waiting. A deep amber, dark enough to read on ivory.
  final Color pending;

  /// Live. A deep green, distinct from the brand sage.
  final Color active;

  /// Error.
  final Color danger;

  /// Tonal washes behind a signal, so the chip reads without shouting.
  final Color pendingTint;
  final Color activeTint;
  final Color dangerTint;

  /// The colours of the light mood: a cool near-white ground.
  ///
  /// The neutrals are blue-grey rather than cream. A warm ivory reads as
  /// yellow once it is a whole screen, and a patient who finds it
  /// unpleasant finds it on every page.
  ///
  /// Measured against [background] and [surface]:
  ///   label            16.2:1 page   17.6:1 card
  ///   secondaryLabel    5.7:1 page    6.1:1 card
  ///   primary           6.8:1 page    7.3:1 card
  ///   action            5.0:1 page    5.4:1 card
  ///   pending           5.0:1 page    5.5:1 card
  ///   active            5.0:1 page    5.4:1 card
  ///   danger            6.0:1 page    6.5:1 card
  /// and each signal stays above 4.7:1 inside its own tinted chip.
  static const AppColors light = AppColors(
    background: Color(0xFFFBF9F5),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF1EDE4),
    surfaceRaised: Color(0xFFF7F4EE),
    label: Color(0xFF1A2420),
    secondaryLabel: Color(0xFF5C6661),
    separator: Color(0xFFE3DED4),
    primary: Color(0xFF3B5D50),
    onPrimary: Color(0xFFFFFFFF),
    action: Color(0xFF9F563E),
    onAction: Color(0xFFFFFFFF),
    pending: Color(0xFF995B00),
    active: Color(0xFF2D784C),
    danger: Color(0xFFB3261E),
    pendingTint: Color(0x1A995B00),
    activeTint: Color(0x1A2D784C),
    dangerTint: Color(0x1AB3261E),
  );

  /// The colours of the dark mood, for the evening and the bedside.
  ///
  /// The accents are the light palette lifted and softened so they hold
  /// against a dark ground: the same sage, the same terracotta, the same
  /// three signals, each readable at the same ratios.
  static const AppColors dark = AppColors(
    background: Color(0xFF14171A),
    surface: Color(0xFF1E2226),
    surfaceSunken: Color(0xFF0F1214),
    surfaceRaised: Color(0xFF282D32),
    label: Color(0xFFF2F5F3),
    secondaryLabel: Color(0xFFA8B3AD),
    separator: Color(0xFF2E3439),
    primary: Color(0xFF8FBFA8),
    onPrimary: Color(0xFF0F2A21),
    action: Color(0xFFE0A188),
    onAction: Color(0xFF3B1509),
    pending: Color(0xFFE5A23C),
    active: Color(0xFF6BC98A),
    danger: Color(0xFFE8837A),
    pendingTint: Color(0x26E5A23C),
    activeTint: Color(0x266BC98A),
    dangerTint: Color(0x26E8837A),
  );

  /// The colours of the mood [context] is currently in.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppColors &&
        other.background == background &&
        other.surface == surface &&
        other.surfaceSunken == surfaceSunken &&
        other.surfaceRaised == surfaceRaised &&
        other.label == label &&
        other.secondaryLabel == secondaryLabel &&
        other.separator == separator &&
        other.primary == primary &&
        other.onPrimary == onPrimary &&
        other.action == action &&
        other.onAction == onAction &&
        other.pending == pending &&
        other.active == active &&
        other.danger == danger &&
        other.pendingTint == pendingTint &&
        other.activeTint == activeTint &&
        other.dangerTint == dangerTint;
  }

  @override
  int get hashCode => Object.hash(
        background,
        surface,
        surfaceSunken,
        surfaceRaised,
        label,
        secondaryLabel,
        separator,
        primary,
        onPrimary,
        action,
        onAction,
        pending,
        active,
        danger,
        pendingTint,
        activeTint,
        dangerTint,
      );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSunken,
    Color? surfaceRaised,
    Color? label,
    Color? secondaryLabel,
    Color? separator,
    Color? primary,
    Color? onPrimary,
    Color? action,
    Color? onAction,
    Color? pending,
    Color? active,
    Color? danger,
    Color? pendingTint,
    Color? activeTint,
    Color? dangerTint,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      label: label ?? this.label,
      secondaryLabel: secondaryLabel ?? this.secondaryLabel,
      separator: separator ?? this.separator,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      action: action ?? this.action,
      onAction: onAction ?? this.onAction,
      pending: pending ?? this.pending,
      active: active ?? this.active,
      danger: danger ?? this.danger,
      pendingTint: pendingTint ?? this.pendingTint,
      activeTint: activeTint ?? this.activeTint,
      dangerTint: dangerTint ?? this.dangerTint,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      label: Color.lerp(label, other.label, t)!,
      secondaryLabel: Color.lerp(secondaryLabel, other.secondaryLabel, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      action: Color.lerp(action, other.action, t)!,
      onAction: Color.lerp(onAction, other.onAction, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      active: Color.lerp(active, other.active, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      pendingTint: Color.lerp(pendingTint, other.pendingTint, t)!,
      activeTint: Color.lerp(activeTint, other.activeTint, t)!,
      dangerTint: Color.lerp(dangerTint, other.dangerTint, t)!,
    );
  }
}
