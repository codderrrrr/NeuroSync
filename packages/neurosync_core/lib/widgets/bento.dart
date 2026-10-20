import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A grid of soft panels, each carrying one thing.
///
/// The cells are not a table with borders. They are separate panels on a
/// shared ground, so a clinician can take in one block of information at a
/// time rather than reading across a row of columns.
///
/// A cell may span more than one column, which is how a headline panel sits
/// above a row of smaller ones.
class BentoGrid extends StatelessWidget {
  const BentoGrid({
    super.key,
    required this.cells,
    this.columns = 2,
    this.spacing = 14,
    this.runSpacing = 14,
  });

  /// The cells, in reading order.
  final List<Widget> cells;

  /// How many columns the grid has at its widest.
  final int columns;

  /// The gap between cells.
  final double spacing;

  /// The gap between rows.
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Below the width a cell needs, the grid becomes one column rather
        // than a set of unreadably narrow panels.
        final int count = constraints.maxWidth < 400 ? 1 : columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: <Widget>[
            for (final Widget cell in cells)
              SizedBox(
                width: count == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - spacing * (count - 1)) / count,
                child: cell,
              ),
          ],
        );
      },
    );
  }
}

/// One panel in a [BentoGrid].
class BentoCell extends StatelessWidget {
  const BentoCell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// A colour to mark the cell with, such as the colour of a clinical signal.
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
        border: accent == null
            ? null
            : Border.all(color: accent!.withValues(alpha: 0.35), width: 1.5),
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

/// The small label that names what a bento cell holds.
class BentoLabel extends StatelessWidget {
  const BentoLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: AppColors.of(context).secondaryLabel,
      ),
    );
  }
}

/// A value with a caption under it, the shape most bento cells take.
class BentoStat extends StatelessWidget {
  const BentoStat({
    super.key,
    required this.value,
    required this.caption,
    this.valueColor,
    this.valueSize = 26,
  });

  /// The number or short phrase.
  final String value;

  /// What the number means.
  final String caption;

  /// The colour of the number, when it carries a signal.
  final Color? valueColor;

  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontSize: valueSize,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: valueColor ?? colors.label,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 14,
            height: 1.45,
            color: colors.secondaryLabel,
          ),
        ),
      ],
    );
  }
}
