import 'package:flutter/material.dart';

import 'app_colors.dart';

/// NeuroSync's design system: the shape of every control, and the two moods
/// the palette can take.
///
/// The controls are generous on purpose. The people using this app have
/// tremor and bradykinesia, so a target is tall enough to hit, a press
/// response is slow enough to see, and the type is large enough to read
/// without hunting for the glasses.
///
/// The two moods are one system rather than two. Warm ivory and sage in the
/// light, slate and lifted sage in the dark, so a patient who uses the app
/// in bed and the one who uses it at breakfast are looking at the same
/// product.
///
/// **Display** is Plus Jakarta Sans: geometric, humanist, a little warm.
/// **Body** is Inter: neutral and built for small sizes, which is what a
/// dense clinical table needs.
class AppTheme {
  const AppTheme._();

  /// The type used for headings and display text.
  static const String displayFont = 'Plus Jakarta Sans';

  /// The type used for body text and interface labels.
  static const String bodyFont = 'Inter';

  /// The corner radius of a card. Generous, so a card reads as a soft panel
  /// rather than a rectangle.
  static const double cardRadius = 24;

  /// The corner radius of a field or a chip.
  static const double fieldRadius = 16;

  /// The height of a primary control: the one a patient is asked to press.
  static const double controlHeight = 72;

  /// The height of a secondary control.
  static const double secondaryControlHeight = 56;

  /// The line height of body text. Long enough that a line of text is a row
  /// of shapes rather than a smear.
  static const double bodyLineHeight = 1.5;

  // ----------------------------------------------------------------- light

  /// The light mood: warm ivory, sage, terracotta.
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  // ------------------------------------------------------------------ dark

  /// The dark mood: slate, lifted sage, lifted terracotta.
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
    ).copyWith(
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.action,
      onSecondary: colors.onAction,
      surface: colors.surface,
      onSurface: colors.label,
      onSurfaceVariant: colors.secondaryLabel,
      surfaceContainerLowest: colors.surfaceSunken,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surfaceRaised,
      surfaceContainerHigh: colors.surfaceRaised,
      surfaceContainerHighest: colors.surfaceRaised,
      outline: colors.separator,
      outlineVariant: colors.separator,
      error: colors.danger,
      onError: brightness == Brightness.light ? Colors.white : colors.label,
      inverseSurface: colors.label,
      onInverseSurface: colors.background,
      inversePrimary: colors.primary,
    );

    final TextTheme text = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      extensions: <ThemeExtension<dynamic>>[colors],
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: colors.label,
        titleTextStyle: text.titleLarge,
      ),
      dividerTheme: DividerThemeData(
        color: colors.separator,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSunken,
        hintStyle:
            TextStyle(color: colors.secondaryLabel, fontFamily: bodyFont),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.surfaceSunken,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.label,
        contentTextStyle: TextStyle(
          color: colors.background,
          fontFamily: bodyFont,
          fontSize: 15,
          height: bodyLineHeight,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.secondaryLabel,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.surfaceSunken,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceSunken,
        circularTrackColor: colors.surfaceSunken,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.label,
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
        textStyle: TextStyle(color: colors.background, fontFamily: bodyFont),
      ),
    );
  }

  /// The type scale, in both families.
  ///
  /// Body text never goes below 15pt and never has a line height under 1.5:
  /// the reading load of a tremor or a tired eye is real, and this is the
  /// cheapest place to reduce it.
  static TextTheme _textTheme(AppColors colors) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: -0.8,
        color: colors.label,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: -0.5,
        color: colors.label,
      ),
      displaySmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.3,
        color: colors.label,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 26,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.3,
        color: colors.label,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      headlineSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      titleLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      titleMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.45,
        color: colors.label,
      ),
      titleSmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.45,
        color: colors.label,
      ),
      bodyLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: bodyLineHeight,
        color: colors.label,
      ),
      bodyMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: bodyLineHeight,
        color: colors.label,
      ),
      bodySmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: colors.secondaryLabel,
      ),
      labelLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      labelMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: colors.label,
      ),
      labelSmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: colors.secondaryLabel,
      ),
    );
  }
}
