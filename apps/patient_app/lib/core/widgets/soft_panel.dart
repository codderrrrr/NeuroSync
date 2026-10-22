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
    final double radius = AppTheme.cardRadius;

    // A panel is a surface, so it is a Material. That is not only how the
    // colour is painted: an ink splash needs a Material above it, and a
    // control inside the panel would otherwise have nowhere to print.
    final Widget panel = Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: accent ?? colors.separator,
          width: accent == null ? 1 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: padding,
        // The InkWell is inside the Material, so a press on the panel leaves
        // its mark on the panel rather than behind it.
        child: onTap == null
            ? child
            : InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: child,
              ),
      ),
    );

    return panel;
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
    // The track is a Material, so the ink of a press is printed on the track
    // the patient is pressing rather than behind it.
    return Material(
      color: colors.surfaceSunken,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
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
      // The item carries its own Material, so the ink of a press is printed
      // above the sliding capsule rather than under it. The capsule covers
      // the chosen side, and a press on the chosen side should still leave
      // a mark.
      child: Material(
        color: Colors.transparent,
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
      ),
    );
  }
}
