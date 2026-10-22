import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One of the moods the application can be in.
class ThemeChoiceOption {
  const ThemeChoiceOption({
    required this.mode,
    required this.icon,
    required this.label,
  });

  final ThemeMode mode;
  final IconData icon;
  final String label;
}

/// A bar of moods, with a thumb that slides between them.
///
/// Three stacked buttons is three targets to hit and three things to read
/// before the patient has read anything else. A bar is one control: the
/// choices sit side by side, the chosen one is marked by a thumb that slides
/// to it, and the whole thing answers a tap with a tick.
///
/// The thumb travels with a spring rather than a straight line, so the change
/// is felt as movement rather than seen as a jump.
class ThemeChoiceBar extends StatelessWidget {
  const ThemeChoiceBar({
    super.key,
    required this.mode,
    required this.onChanged,
    this.options = defaultOptions,
  });

  /// The mood currently in use.
  final ThemeMode mode;

  /// Called with the mood the patient chose.
  final ValueChanged<ThemeMode> onChanged;

  /// The moods on the bar.
  final List<ThemeChoiceOption> options;

  /// Light, dark, and whatever the system says.
  static const List<ThemeChoiceOption> defaultOptions = <ThemeChoiceOption>[
    ThemeChoiceOption(
      mode: ThemeMode.light,
      icon: Icons.light_mode_outlined,
      label: 'Light',
    ),
    ThemeChoiceOption(
      mode: ThemeMode.dark,
      icon: Icons.dark_mode_outlined,
      label: 'Dark',
    ),
    ThemeChoiceOption(
      mode: ThemeMode.system,
      icon: Icons.brightness_auto_outlined,
      label: 'Auto',
    ),
  ];

  static const double _height = 52;
  static const double _trackPadding = 4;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final int selected = options.indexWhere(
      (ThemeChoiceOption option) => option.mode == mode,
    );
    final int index = selected < 0 ? options.length - 1 : selected;

    return Material(
      color: colors.surfaceSunken,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: _height,
        padding: const EdgeInsets.all(_trackPadding),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double portion = constraints.maxWidth / options.length;
            return Stack(
              children: <Widget>[
                // The thumb: a raised card that travels to the chosen mood and
                // fills the whole of that portion, so the chosen mood is the one
                // the patient is looking at rather than a sliver of it.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  left: portion * index,
                  top: 0,
                  bottom: 0,
                  width: portion,
                  child: Padding(
                    // A hairline of space either side, so the thumb reads as a
                    // card sitting on the track rather than as the track itself.
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color:
                                const Color(0xFF0B1017).withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    for (final ThemeChoiceOption option in options)
                      SizedBox(
                        width: portion,
                        child: _Choice(
                          option: option,
                          selected: option.mode == mode,
                          onTap: () {
                            if (option.mode == mode) {
                              return;
                            }
                            HapticFeedback.selectionClick();
                            onChanged(option.mode);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ThemeChoiceOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color color = selected ? colors.primary : colors.secondaryLabel;

    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label} appearance',
      // The choice carries its own Material, so the ink of a press is printed
      // above the raised card rather than under it. The card covers the
      // chosen mood, and a press on it should still leave a mark.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            // The mark sits above the word rather than beside it, so the word
            // is centred in its portion and the raised card that marks the
            // choice encloses both of them.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutBack,
                  // The mark changes colour with the thumb rather than at the
                  // moment the choice is made, so the two travel together.
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                      begin: selected ? colors.secondaryLabel : colors.primary,
                      end: color,
                    ),
                    duration: const Duration(milliseconds: 240),
                    builder: (BuildContext context, Color? animated, _) {
                      return Icon(option.icon, size: 16, color: animated);
                    },
                  ),
                ),
                const SizedBox(height: 2),
                // The label fades rather than jumps, so the change reads as the
                // same control settling rather than as a new one appearing.
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.15,
                    color: color,
                  ),
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
