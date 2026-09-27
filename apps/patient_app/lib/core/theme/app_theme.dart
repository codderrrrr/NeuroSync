import 'package:flutter/material.dart';

/// Apple Health inspired palette: grouped background, white cards, calm accent.
///
/// [light] is the general application theme. [dark] powers the first-time
/// experience (splash, onboarding, welcome) and the authentication screens.
class AppTheme {
  const AppTheme._();

  // ---- Light palette -------------------------------------------------
  static const Color background = Color(0xFFF2F2F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF0A84FF);
  static const Color label = Color(0xFF1C1C1E);
  static const Color secondaryLabel = Color(0xFF8E8E93);
  static const Color separator = Color(0xFFE5E5EA);

  // ---- Dark palette --------------------------------------------------
  /// Deep near-black base for the dark experience.
  static const Color darkBackground = Color(0xFF0B0C0E);

  /// Elevated surface (cards, controls).
  static const Color darkSurface = Color(0xFF121417);

  /// Secondary surface (input fills, chips).
  static const Color darkSurfaceSecondary = Color(0xFF181B1F);

  /// Near-white primary text.
  static const Color darkLabel = Color(0xFFF4F5F7);

  /// Muted cool gray secondary text.
  static const Color darkSecondaryLabel = Color(0xFF8C929B);

  /// Hairline separators on dark.
  static const Color darkSeparator = Color(0xFF24272C);

  /// The single NeuroSync accent: a restrained clinical mint.
  static const Color accentMint = Color(0xFF63D6AC);

  static const Color pending = Color(0xFFFF9F0A);
  static const Color active = Color(0xFF34C759);
  static const Color danger = Color(0xFFFF3B30);
  static const Color pendingTint = Color(0x1FFF9F0A);
  static const Color activeTint = Color(0x1F34C759);
  static const Color disabledAccent = Color(0x800A84FF);

  static const double cardRadius = 18;
  static const double fieldRadius = 14;
  static const double controlHeight = 52;

  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: accent).copyWith(
      surface: surface,
      error: danger,
      primary: accent,
      onPrimary: Colors.white,
      onSurface: label,
      onSurfaceVariant: secondaryLabel,
      outline: separator,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: label,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: label,
        ),
      ),
      dividerTheme:
          const DividerThemeData(color: separator, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: secondaryLabel),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
    );
  }

  /// Dark-first theme for the splash, onboarding and authentication screens.
  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accentMint,
      brightness: Brightness.dark,
    ).copyWith(
      surface: darkSurface,
      onSurface: darkLabel,
      onSurfaceVariant: darkSecondaryLabel,
      outline: darkSeparator,
      primary: accentMint,
      onPrimary: darkBackground,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: darkLabel,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: darkLabel,
        ),
      ),
      dividerTheme:
          const DividerThemeData(color: darkSeparator, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceSecondary,
        hintStyle: const TextStyle(color: darkSecondaryLabel),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          borderSide: const BorderSide(color: accentMint, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
    );
  }
}
