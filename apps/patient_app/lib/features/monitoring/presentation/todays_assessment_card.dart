import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../core/widgets/soft_panel.dart';
import '../models/monitoring_plan.dart';

/// Today's monitoring, and the one thing to do about it.
///
/// The card leads with the assessment the patient is about to do, because that
/// is what they opened the app for. Everything else on it - the plan's name,
/// whether the test is ready - is the detail around that one fact.
class TodaysAssessmentCard extends StatelessWidget {
  const TodaysAssessmentCard({
    super.key,
    required this.plan,
    required this.isLoading,
    required this.errorMessage,
    required this.onStart,
    required this.onRetry,
  });

  final MonitoringPlan? plan;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<MonitoringPlanItem> onStart;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading && plan == null) {
      return const SoftPanel(
        child: Center(child: CalmLoader(size: 22)),
      );
    }

    if (errorMessage != null && plan == null) {
      return SoftPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ErrorText(errorMessage!),
            const SizedBox(height: 12),
            SecondaryButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      );
    }

    final MonitoringPlan? activePlan = plan;
    if (activePlan == null) {
      return const SoftPanel(
        child: EmptyNote(
          icon: Icons.event_available_outlined,
          title: 'No monitoring plan yet',
          message: 'When your doctor sets up a monitoring plan, your next '
              'motor test will appear here.',
        ),
      );
    }

    return _PlanCard(plan: activePlan, onStart: onStart);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onStart});

  final MonitoringPlan plan;
  final ValueChanged<MonitoringPlanItem> onStart;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final MonitoringPlanItem? next = plan.nextAvailableItem;

    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The plan's name is the quiet line at the top: the patient knows
          // what it is called, and the test underneath is what matters today.
          Text(
            plan.title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 12),
          if (next == null)
            const _AllDoneToday()
          else ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconFor(next),
                    size: 20,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        next.assessment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          letterSpacing: -0.2,
                          color: colors.label,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        next.assessment.description,
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 14,
                          height: 1.45,
                          color: colors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (next.assessment.isSupported)
              PrimaryButton(
                label: next.isDoneToday ? 'Do it again' : 'Begin test',
                onPressed: () => onStart(next),
                tactile: true,
              )
            else ...<Widget>[
              const _NotAvailableChip(),
              const SizedBox(height: 8),
              const Text(
                'This test is being built. It will appear here once it is '
                'available.',
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(MonitoringPlanItem item) {
    switch (item.assessment.slug) {
      case 'spiral_drawing':
        return Icons.grain_outlined;
      case 'line_tracing':
        return Icons.horizontal_rule_rounded;
      case 'handwriting':
        return Icons.draw_outlined;
      default:
        return Icons.touch_app_outlined;
    }
  }
}

/// Chip for catalog assessments that exist but have no runner yet.
class _NotAvailableChip extends StatelessWidget {
  const _NotAvailableChip();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: StatePill(
        label: 'NOT AVAILABLE YET',
        color: colors.pending,
        tint: colors.pendingTint,
      ),
    );
  }
}

class _AllDoneToday extends StatelessWidget {
  const _AllDoneToday();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.active.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 20,
                color: colors.active,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'All done for today',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: colors.label,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'You have finished today\u2019s motor check-in. Come back tomorrow.',
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
