import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_metrics.dart';

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

  /// The line height of body text. Long enough that a line of text is a row
  /// of shapes rather than a smear.
  static const double bodyLineHeight = 1.5;

  // ----------------------------------------------------------------- light

  /// The light mood: a cool near-white ground, sage and terracotta.
  static ThemeData light({AppMetrics metrics = AppMetrics.comfortable}) =>
      _build(AppColors.light, Brightness.light, metrics);

  // ------------------------------------------------------------------ dark

  /// The dark mood: slate, lifted sage, lifted terracotta.
  static ThemeData dark({AppMetrics metrics = AppMetrics.comfortable}) =>
      _build(AppColors.dark, Brightness.dark, metrics);

  static ThemeData _build(
    AppColors colors,
    Brightness brightness,
    AppMetrics metrics,
  ) {
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

    final TextTheme text = _textTheme(colors, metrics.textScale);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      extensions: <ThemeExtension<dynamic>>[colors, metrics],
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
  /// Body text is never below 13pt and never has a line height under 1.5:
  /// the reading load of a tremor or a tired eye is real, and this is the
  /// cheapest place to reduce it.
  ///
  /// [scale] shrinks the headings only. The body is left alone, because the
  /// complaint about a screen being too large is about the space the titles
  /// take up, not about the words: a patient who has to lean in to read a
  /// paragraph has been given a screen they cannot use.
  static TextTheme _textTheme(AppColors colors, double scale) {
    double size(double base) => (base * scale).roundToDouble();

    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: size(34),
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: -0.6,
        color: colors.label,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: size(28),
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: -0.4,
        color: colors.label,
      ),
      displaySmall: TextStyle(
        fontFamily: displayFont,
        fontSize: size(24),
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.2,
        color: colors.label,
      ),
      headlineLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: size(22),
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.2,
        color: colors.label,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFont,
        fontSize: size(19),
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      headlineSmall: TextStyle(
        fontFamily: displayFont,
        fontSize: size(17),
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      titleLarge: TextStyle(
        fontFamily: displayFont,
        fontSize: size(17),
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      titleMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.45,
        color: colors.label,
      ),
      titleSmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.45,
        color: colors.label,
      ),
      bodyLarge: TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
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
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: colors.label,
      ),
      labelMedium: TextStyle(
        fontFamily: bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: colors.label,
      ),
      labelSmall: TextStyle(
        fontFamily: bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: colors.secondaryLabel,
      ),
    );
  }
}
