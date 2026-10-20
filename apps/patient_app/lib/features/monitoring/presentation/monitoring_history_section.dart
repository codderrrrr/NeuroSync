import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../core/formatting/date_format.dart';
import '../models/longitudinal_summary.dart';
import '../models/monitoring_session.dart';
import '../state/monitoring_controller.dart';

/// The Check-ins tab's monitoring section: completed motor-test sessions.
///
/// Shows the status the backend derived for each recording. Like the symptom
/// check-in history below it, the section describes what happened and never
/// interprets it.
class MonitoringHistorySection extends StatelessWidget {
  const MonitoringHistorySection({super.key, required this.controller});

  final MonitoringController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading && !controller.hasLoadedHistory) {
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

    if (controller.history.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader('Monitoring sessions'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: <Widget>[
              for (int index = 0;
                  index < controller.history.length;
                  index++) ...<Widget>[
                if (index > 0)
                  const Divider(height: 1, indent: 18, endIndent: 18),
                _SessionRow(session: controller.history[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final MonitoringSession session;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.assessment.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.completedAt != null
                      ? formatShortDateTime(session.completedAt!)
                      : formatShortDateTime(session.startedAt),
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (session.longitudinal != null)
                _LongitudinalChip(state: session.longitudinal!.state),
              const SizedBox(height: 4),
              _QualityChip(label: session.result?.quality.label ?? 'Completed'),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// The longitudinal state for one history row.
///
/// Tinted rather than plain so the longitudinal signal reads first while the
/// recording quality stays visible underneath it.
class _LongitudinalChip extends StatelessWidget {
  const _LongitudinalChip({required this.state});

  final LongitudinalState state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color;
    switch (state) {
      case LongitudinalState.withinBaseline:
        color = AppTheme.active;
      case LongitudinalState.changed:
        color = AppTheme.pending;
      case LongitudinalState.insufficientData:
      case LongitudinalState.unreliable:
        color = scheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state.shortLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
