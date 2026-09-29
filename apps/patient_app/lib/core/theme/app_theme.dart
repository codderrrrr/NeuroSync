import 'package:flutter/material.dart';

/// NeuroSync's colour system: Apple Dark Mode, one brightness.
///
/// Depth comes from lightness, not warmth and not shadow. The canvas is a
/// neutral dark grey, cards sit one step lighter, and a single cool accent
/// carries the brand. Accent colours are the saturated system colours Apple
/// uses in Dark Mode so they hold against a dark ground without vibrating.
///
/// Deliberately avoided:
/// - a warm charcoal or honey tint on the neutrals,
/// - pure black cards on a grey page (they look broken off OLED),
/// - saturated green at small sizes, which fringes on a dark ground.
///
/// Contrast of the key pairs, measured against [darkBackground] #1C1C1E and
/// the card [darkSurface] #2C2C2E:
///   darkLabel          #FFFFFF   17.0:1 page   13.9:1 card
///   accentMint         #64D2FF    9.9:1 page    8.1:1 card
///   darkSecondaryLabel composited 5.9:1 page    5.3:1 card
///   pending            #FF9F0A    8.3:1 page    6.8:1 card
///   active             #30D158    8.4:1 page    6.9:1 card
///   danger             #FF6961    6.0:1 page    4.9:1 card
/// On the accent fill the dark teal label is 7.6:1, and each signal stays above
/// 5.3:1 inside its own tinted chip, so every pair clears WCAG AA.
///
/// [danger] is the lighter red rather than System Red #FF453A: on a card
/// #FF453A measures only 4.1:1, which fails AA for error text.
class AppTheme {
  const AppTheme._();

  /// System background. Not #000, so the page has a surface rather than a hole,
  /// and not warm, so it reads as a screen rather than a lamp-lit room.
  static const Color darkBackground = Color(0xFF1C1C1E);

  /// Elevated surface (cards): one measured step up from the page. In Dark Mode
  /// lightness is the elevation.
  static const Color darkSurface = Color(0xFF2C2C2E);

  /// Secondary surface (input fills, chips): the next step up, for controls
  /// that sit on a card.
  static const Color darkSurfaceSecondary = Color(0xFF3A3A3C);

  /// Primary text. Full white, the Apple Dark Mode label.
  static const Color darkLabel = Color(0xFFFFFFFF);

  /// Secondary text: Apple's secondary label, white at 60%, so hierarchy comes
  /// from opacity rather than a grey ink.
  static const Color darkSecondaryLabel = Color(0x99EBEBF5);

  /// Hairline separators: a neutral step, so grouping stays quiet.
  static const Color darkSeparator = Color(0xFF38383A);

  /// The one brand accent: System Teal. Used for the primary action, the
  /// focused field, and the mark. Cool, clinical, and quiet at night.
  static const Color accentMint = Color(0xFF64D2FF);

  /// No longer a honey highlight. The name stays so existing call sites keep
  /// compiling, and it now resolves to the same cool accent.
  static const Color warmHighlight = accentMint;

  /// Clinical signals, using Apple's semantic colours rather than a warm family.
  /// Waiting is orange, live is green, error is red.
  static const Color pending = Color(0xFFFF9F0A);
  static const Color active = Color(0xFF30D158);
  static const Color danger = Color(0xFFFF6961);

  static const Color pendingTint = Color(0x1FFF9F0A);
  static const Color activeTint = Color(0x1F30D158);

  /// The accent when a control is unavailable: the brand hue, translucent
  /// enough to recede without turning into a grey pill.
  static const Color disabledAccent = Color(0x6664D2FF);

  /// Tonal washes, for containers, chips and snackbars.
  static const Color _accentWash = Color(0xFF0A3344);
  static const Color _onAccentWash = Color(0xFFB6E8FF);
  static const Color _surfaceSunken = Color(0xFF000000);
  static const Color _surfaceRaised = Color(0xFF3A3A3C);

  static const double cardRadius = 18;
  static const double fieldRadius = 14;
  static const double controlHeight = 52;

  /// The only theme. Dark by design: this is an app patients open in the
  /// evening, often in bed, and it holds one palette rather than two.
  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accentMint,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accentMint,
      onPrimary: const Color(0xFF003548),
      primaryContainer: _accentWash,
      onPrimaryContainer: _onAccentWash,
      surface: darkSurface,
      onSurface: darkLabel,
      onSurfaceVariant: darkSecondaryLabel,
      surfaceContainerLowest: _surfaceSunken,
      surfaceContainerLow: darkSurface,
      surfaceContainer: darkSurfaceSecondary,
      surfaceContainerHigh: _surfaceRaised,
      surfaceContainerHighest: _surfaceRaised,
      outline: darkSeparator,
      outlineVariant: darkSeparator,
      error: danger,
      onError: darkLabel,
      inverseSurface: darkLabel,
      onInverseSurface: darkBackground,
      inversePrimary: accentMint,
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
