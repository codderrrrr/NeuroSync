import 'package:flutter/material.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/formatting/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../models/roster_models.dart';
import '../state/roster_controller.dart';

/// Patients waiting for this doctor to accept their link request.
///
/// Accepting is the whole job of this screen, so each row states who is
/// waiting and since when, and offers exactly one action.
class RequestsView extends StatefulWidget {
  const RequestsView({super.key});

  @override
  State<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<RequestsView> {
  String? _acceptingLinkId;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppScope.of(context).roster.loadDashboard();
      }
    });
  }

  Future<void> _accept(PendingRequest request) async {
    final RosterController roster = AppScope.of(context).roster;
    setState(() {
      _acceptingLinkId = '${request.linkId}';
      _feedback = null;
    });

    final bool accepted = await roster.accept(request);

    if (!mounted) {
      return;
    }
    setState(() {
      _acceptingLinkId = null;
      _feedback = accepted
          ? '${request.patientName} is now on your roster.'
          : roster.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final RosterController roster = AppScope.of(context).roster;
    return PortalPage(
      title: 'Requests',
      subtitle: 'Patients waiting for you to accept their link.',
      child: ListenableBuilder(
        listenable: roster,
        builder: (BuildContext context, Widget? child) {
          if (roster.errorMessage != null && roster.pending.isEmpty) {
            return Center(
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load requests',
                message: roster.errorMessage!,
                action: SecondaryButton(
                  label: 'Try again',
                  onPressed: roster.loadDashboard,
                ),
              ),
            );
          }
          if (!roster.hasLoaded) {
            return const TableSkeleton(rows: 3, height: 72);
          }

          final List<PendingRequest> pending = roster.pending;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_feedback != null) ...<Widget>[
                _Feedback(message: _feedback!),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: pending.isEmpty
                    ? const EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No open requests',
                        message:
                            'When a patient enters your link code, their request '
                            'will appear here for you to accept.',
                      )
                    : ListView.separated(
                        itemCount: pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final PendingRequest request = pending[index];
                          return _RequestRow(
                            request: request,
                            isAccepting:
                                _acceptingLinkId == '${request.linkId}',
                            // Any other row is inert while one is in flight, so
                            // a slow request cannot be fired twice.
                            enabled: _acceptingLinkId == null,
                            onAccept: () => _accept(request),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.isAccepting,
    required this.enabled,
    required this.onAccept,
  });

  final PendingRequest request;
  final bool isAccepting;
  final bool enabled;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget identity = Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.pendingTint,
                child: Text(
                  request.patientName.isEmpty
                      ? '?'
                      : request.patientName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.pending,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      request.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Requested ${formatMonthDayYear(request.requestedAt)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.darkSecondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final Widget action = PrimaryButton(
            label: 'Accept',
            isLoading: isAccepting,
            onPressed: enabled ? onAccept : null,
          );

          // The action sits below the identity once the row can no longer hold
          // both without truncating the name.
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                identity,
                const SizedBox(height: 14),
                action,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: identity),
              const SizedBox(width: 16),
              SizedBox(width: 132, child: action),
            ],
          );
        },
      ),
    );
  }
}

/// Immediate confirmation of what just happened, good or bad.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final bool failure = message.toLowerCase().contains('not found');
    final Color color = failure ? AppTheme.danger : AppTheme.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            failure ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
