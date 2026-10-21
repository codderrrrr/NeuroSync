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

  static const double _height = 46;
  static const double _trackPadding = 4;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final int selected = options.indexWhere(
      (ThemeChoiceOption option) => option.mode == mode,
    );
    final int index = selected < 0 ? options.length - 1 : selected;

    return Container(
      height: _height,
      padding: const EdgeInsets.all(_trackPadding),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double portion = constraints.maxWidth / options.length;
          return Stack(
            children: <Widget>[
              // The thumb: a raised card that travels to the chosen mood.
              Positioned(
                left: portion * index,
                top: 0,
                bottom: 0,
                width: portion,
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 1 / options.length,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color:
                                const Color(0xFF0B1017).withValues(alpha: 0.10),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedScale(
                scale: selected ? 1.1 : 1,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                child: Icon(option.icon, size: 17, color: color),
              ),
              const SizedBox(width: 6),
              // The label fades rather than jumps, so the change reads as the
              // same control settling rather than as a new one appearing.
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  height: 1.2,
                  color: color,
                ),
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
