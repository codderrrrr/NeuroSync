import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A control for choosing the mood: light, dark, or whatever the system says.
///
/// The three are one row rather than a switch, because "follow the system"
/// is a different answer from "light" and "dark", and a two-state switch
/// cannot express it.
class ThemeChoice extends StatelessWidget {
  const ThemeChoice({
    super.key,
    required this.mode,
    required this.onChanged,
    this.dense = false,
  });

  /// The mood currently in use.
  final ThemeMode mode;

  /// Called with the mood the patient chose.
  final ValueChanged<ThemeMode> onChanged;

  /// Whether to lay the choices out in a row rather than a column.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    const Map<ThemeMode, ({IconData icon, String label})> choices =
        <ThemeMode, ({IconData icon, String label})>{
      ThemeMode.light: (icon: Icons.light_mode_outlined, label: 'Light'),
      ThemeMode.dark: (icon: Icons.dark_mode_outlined, label: 'Dark'),
      ThemeMode.system: (icon: Icons.brightness_auto_outlined, label: 'Auto'),
    };

    final List<Widget> buttons = <Widget>[
      for (final ThemeMode choice in ThemeMode.values)
        _ThemeButton(
          icon: choices[choice]!.icon,
          label: choices[choice]!.label,
          selected: mode == choice,
          onPressed: () => onChanged(choice),
        ),
    ];

    if (dense) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int index = 0; index < buttons.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: 6),
            buttons[index],
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int index = 0; index < buttons.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 6),
          buttons[index],
        ],
      ],
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label appearance',
      child: Material(
        color: selected ? colors.primary : colors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 19,
                  color: selected ? colors.onPrimary : colors.secondaryLabel,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: selected ? colors.onPrimary : colors.label,
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
