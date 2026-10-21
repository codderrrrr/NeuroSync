import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import 'soft_panel.dart';

/// One number in a [StatStrip].
class StatEntry {
  const StatEntry({
    required this.value,
    required this.caption,
    this.icon,
    this.valueColor,
    this.emphasis = false,
  });

  /// The number, or a short phrase such as "Done".
  final String value;

  /// What the number means. Short: a caption that wraps to three lines in a
  /// narrow column stops being a caption.
  final String caption;

  /// A small mark above the number.
  final IconData? icon;

  /// The colour of the number, when it carries a signal.
  final Color? valueColor;

  /// Whether this is the one number the screen is about.
  final bool emphasis;
}

/// The numbers at the top of a screen, in one panel.
///
/// Three separate cards is three boxes to look at before the patient has read
/// anything, and on a narrow phone each box ends up too small for the words
/// in it. One panel with a hairline between each column reads as a single
/// fact - the state of today - and gives every column the same room.
///
/// The mark sits above the number rather than beside the caption, so the
/// caption gets the whole width of its column.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.stats});

  final List<StatEntry> stats;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return SoftPanel(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      // The strip is inside a list, so the row has no height of its own to
      // divide up. IntrinsicHeight gives it one, which is what lets the
      // columns and the hairline between them be the same height.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int index = 0; index < stats.length; index++) ...<Widget>[
              if (index > 0)
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: colors.separator,
                ),
              Expanded(
                child: _StatColumn(
                  entry: stats[index],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.entry});

  final StatEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        // The columns start at the same line, not the same distance from the
        // middle. A caption that wraps to two lines would otherwise push its
        // own number up and out of line with the numbers beside it.
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          if (entry.icon != null) ...<Widget>[
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (entry.valueColor ?? colors.secondaryLabel)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                entry.icon,
                size: 13,
                color: entry.valueColor ?? colors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 7),
          ],
          // The number changes when the data behind it does, and a number that
          // changes in place is a number the patient has to notice. Swapping it
          // out draws the eye to the change.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.35),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              entry.value,
              key: ValueKey<String>(entry.value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontSize: entry.emphasis ? 21 : 19,
                fontWeight: FontWeight.w600,
                height: 1.1,
                letterSpacing: -0.3,
                color: entry.valueColor ?? colors.label,
              ),
            ),
          ),
          const SizedBox(height: 3),
          // Two lines of room for every caption, so the columns below the
          // numbers stay the same height whether a caption wraps or not.
          SizedBox(
            height: 28,
            child: Text(
              entry.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 11,
                height: 1.25,
                color: colors.secondaryLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
