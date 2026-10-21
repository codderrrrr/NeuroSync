import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// A panel: the surface the patient's information sits on.
///
/// Soft corners, a hairline rather than a shadow, and no border on the page
/// it sits on. The panel separates one thing from the next without drawing
/// attention to itself, which is what a screen with four of them needs.
class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// A colour to mark the panel with, for a clinical signal.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Widget panel = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: accent ?? colors.separator,
          width: accent == null ? 1 : 1.5,
        ),
      ),
      child: child,
    );

    if (onTap == null) {
      return panel;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: onTap,
        child: panel,
      ),
    );
  }
}

/// A number, or a short phrase, with a caption under it.
///
/// The number is the loudest thing in the panel and the caption says what it
/// means, because "3" on its own tells a patient nothing.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.caption,
    this.icon,
    this.valueColor,
    this.onTap,
    this.emphasis = false,
  });

  /// The number, or a short phrase such as "None yet".
  final String value;

  /// What the number means.
  final String caption;

  /// A small mark beside the caption.
  final IconData? icon;

  /// The colour of the number, when it carries a signal.
  final Color? valueColor;

  final VoidCallback? onTap;

  /// Whether this is the one number the screen is about.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return SoftPanel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontSize: emphasis ? 26 : 22,
              fontWeight: FontWeight.w600,
              height: 1.15,
              letterSpacing: -0.4,
              color: valueColor ?? colors.label,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 13, color: colors.secondaryLabel),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    height: 1.35,
                    color: colors.secondaryLabel,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short mark of a state, in a tinted capsule.
class StatePill extends StatelessWidget {
  const StatePill({
    super.key,
    required this.label,
    required this.color,
    required this.tint,
  });

  final String label;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}

/// A two-way choice, drawn as a sliding thumb rather than a Material switch.
///
/// The patient is choosing between two things they can both read, so both are
/// always visible. A switch hides one of them behind a position, which is a
/// question the patient has to answer by remembering what the switch means.
class SegmentedToggle extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  /// The choices, in reading order.
  final List<String> labels;

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double itemWidth = constraints.maxWidth / labels.length;
          return Stack(
            children: <Widget>[
              Positioned(
                left: itemWidth * selectedIndex,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int index = 0; index < labels.length; index++)
                    SizedBox(
                      width: itemWidth,
                      child: _ToggleItem(
                        label: labels[index],
                        selected: index == selectedIndex,
                        onTap: () => onChanged(index),
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

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1.2,
              color: selected ? colors.label : colors.secondaryLabel,
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}
