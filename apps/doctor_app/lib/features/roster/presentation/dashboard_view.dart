import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/formatting/date_format.dart';
import '../models/roster_models.dart';
import '../state/roster_controller.dart';

/// The overview a doctor lands on.
///
/// It answers three workflow questions and nothing else: is anything waiting
/// for me, how many people am I caring for, and who needs an exercise next.
/// Counts are only shown where they lead somewhere.
class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    required this.onOpenPatients,
    required this.onOpenRequests,
  });

  final VoidCallback onOpenPatients;
  final VoidCallback onOpenRequests;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppScope.of(context).roster.loadDashboard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final RosterController roster = AppScope.of(context).roster;
    return PortalPage(
      title: 'Overview',
      child: ListenableBuilder(
        listenable: roster,
        builder: (BuildContext context, Widget? child) {
          if (roster.errorMessage != null && !roster.hasLoaded) {
            return Center(
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your workspace',
                message: roster.errorMessage!,
                action: SecondaryButton(
                  label: 'Try again',
                  onPressed: roster.loadDashboard,
                ),
              ),
            );
          }
          if (!roster.hasLoaded) {
            return const TableSkeleton(rows: 4, height: 76);
          }

          return RefreshIndicator(
            onRefresh: roster.loadDashboard,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                if (roster.pending.isNotEmpty)
                  _AttentionCard(
                    request: roster.pending.first,
                    remaining: roster.pending.length - 1,
                    onReview: widget.onOpenRequests,
                  )
                else
                  const _AllClearCard(),
                const SizedBox(height: 22),
                _RosterSummary(
                  patientCount: roster.patients.length,
                  onOpenPatients: widget.onOpenPatients,
                ),
                const SizedBox(height: 26),
                const Text(
                  'RECENTLY LINKED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: AppTheme.darkSecondaryLabel,
                  ),
                ),
                const SizedBox(height: 12),
                if (roster.patients.isEmpty)
                  _NoPatients(onBrowse: widget.onOpenPatients)
                else
                  for (final RosterPatient patient in roster.patients.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecentlyLinked(patient: patient),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The one thing that needs a decision, stated as such.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.request,
    required this.remaining,
    required this.onReview,
  });

  final PendingRequest request;
  final int remaining;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.pending.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.inbox_outlined,
                size: 18,
                color: AppTheme.pending,
              ),
              const SizedBox(width: 9),
              Text(
                remaining == 0
                    ? '1 REQUEST WAITING'
                    : '${remaining + 1} REQUESTS WAITING',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: AppTheme.pending,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.patientName,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            remaining == 0
                ? 'Wants to link with you. Accepted patients can see the '
                    'exercises you assign them.'
                : 'And $remaining other ${remaining == 1 ? 'patient' : 'patients'} want to link with you.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Review requests', onPressed: onReview),
        ],
      ),
    );
  }
}

class _AllClearCard extends StatelessWidget {
  const _AllClearCard();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Nothing needs your attention',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'No link requests are waiting. Share your code to grow '
                  'your roster.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppTheme.darkSecondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterSummary extends StatelessWidget {
  const _RosterSummary({
    required this.patientCount,
    required this.onOpenPatients,
  });

  final int patientCount;
  final VoidCallback onOpenPatients;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget count = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$patientCount',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.05,
            letterSpacing: -1,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          patientCount == 1 ? 'active patient' : 'active patients',
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.darkSecondaryLabel,
          ),
        ),
      ],
    );
    final Widget action = SecondaryButton(
      label: 'View roster',
      onPressed: onOpenPatients,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      // A Wrap rather than a row with a width threshold: the count and the
      // button share a line when they fit and stack when they do not, without
      // a magic breakpoint that a longer name or a larger text scale defeats.
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: <Widget>[count, action],
      ),
    );
  }
}

class _RecentlyLinked extends StatelessWidget {
  const _RecentlyLinked({required this.patient});

  final RosterPatient patient;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              patient.patientName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
          Text(
            'Linked ${formatMonthDay(patient.linkedAt)}',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPatients extends StatelessWidget {
  const _NoPatients({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Nobody on your roster yet',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          const Text(
            'Patients appear here once you accept their link request.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
          const SizedBox(height: 14),
          SecondaryButton(label: 'Go to requests', onPressed: onBrowse),
        ],
      ),
    );
  }
}
