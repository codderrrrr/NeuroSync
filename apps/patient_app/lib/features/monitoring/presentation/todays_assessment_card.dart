import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../models/monitoring_plan.dart';
import '../../../core/widgets/empty_card.dart';

/// The Home screen's monitoring card.
///
/// Shows the plan the backend assigned and the next assessment to perform.
/// The card never decides which tests exist: it renders [plan] as returned by
/// the API, and unsupported assessments appear as "Not available yet".
class TodaysAssessmentCard extends StatelessWidget {
  const TodaysAssessmentCard({
    super.key,
    required this.plan,
    required this.isLoading,
    this.errorMessage,
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
      return const AppCard(
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (errorMessage != null && plan == null) {
      return AppCard(
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
      return const EmptyCard(
        title: 'No monitoring plan yet',
        message: 'When your doctor sets up a monitoring plan, your next motor '
            'test will appear here.',
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
    final MonitoringPlanItem? next = plan.nextAvailableItem;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                plan.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (next == null)
            const _AllDoneToday()
          else ...<Widget>[
            Text(
              next.assessment.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            MutedText(next.assessment.description),
            const SizedBox(height: 14),
            if (next.assessment.isSupported)
              PrimaryButton(
                label: next.isDoneToday ? 'Do it again' : 'Begin test',
                onPressed: () => onStart(next),
              )
            else ...<Widget>[
              const _NotAvailableChip(),
              const SizedBox(height: 6),
              const MutedText(
                'This test is being built. It will appear here once it is '
                'available.',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Chip for catalog assessments that exist but have no runner yet.
class _NotAvailableChip extends StatelessWidget {
  const _NotAvailableChip();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.pendingTint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'NOT AVAILABLE YET',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.pending,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _AllDoneToday extends StatelessWidget {
  const _AllDoneToday();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.check_circle_outline,
                size: 20, color: AppTheme.active),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'All done for today',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const MutedText(
          'You have finished today\u2019s motor check-in. Come back tomorrow.',
        ),
      ],
    );
  }
}
