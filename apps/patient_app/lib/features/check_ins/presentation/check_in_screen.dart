import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/formatting/date_format.dart';
import '../../monitoring/presentation/monitoring_history_section.dart';
import '../models/check_in.dart';
import '../state/check_in_controller.dart';
import '../../monitoring/state/monitoring_controller.dart';
import 'new_check_in_screen.dart';
import '../../../core/widgets/empty_card.dart';

/// The check-ins tab: record a new check-in and browse past ones.
class CheckInsScreen extends StatefulWidget {
  const CheckInsScreen({super.key});

  @override
  State<CheckInsScreen> createState() => _CheckInsScreenState();
}

class _CheckInsScreenState extends State<CheckInsScreen> {
  @override
  void initState() {
    super.initState();
    // Load history once the first frame is up so notifying listeners never
    // happens during this widget's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      AppScope.of(context).checkIns.load();
      AppScope.of(context).monitoring.loadHistory();
    });
  }

  Future<void> _openNewCheckIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const NewCheckInScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CheckInController controller = AppScope.of(context).checkIns;
    final MonitoringController monitoring = AppScope.of(context).monitoring;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[controller, monitoring]),
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              children: <Widget>[
                const LargeTitle('Check-ins'),
                const SizedBox(height: 6),
                const MutedText(
                  'What you notice, recorded as you feel it. Doctors you link '
                  'see these exactly as written.',
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Record a check-in',
                  onPressed: _openNewCheckIn,
                ),
                const SizedBox(height: 24),
                if (controller.errorMessage != null) ...<Widget>[
                  ErrorText(controller.errorMessage!),
                  const SizedBox(height: 12),
                ],
                MonitoringHistorySection(controller: monitoring),
                const SizedBox(height: 12),
                ..._history(controller),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _history(CheckInController controller) {
    if (controller.isLoading && !controller.hasLoaded) {
      return <Widget>[
        const AppCard(
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    if (controller.checkIns.isEmpty) {
      return const <Widget>[
        EmptyCard(
          title: 'No check-ins yet',
          message: 'Record how you feel right now to start your history.',
        ),
      ];
    }
    return <Widget>[
      const SectionHeader('History'),
      for (final CheckIn checkIn in controller.checkIns) ...<Widget>[
        _CheckInCard(checkIn: checkIn),
        const SizedBox(height: 12),
      ],
    ];
  }
}

/// One stored check-in: when it was recorded, the four ratings and the note.
class _CheckInCard extends StatelessWidget {
  const _CheckInCard({required this.checkIn});

  final CheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                formatShortDateTime(checkIn.recordedAt),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                'Check-in #${checkIn.id}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _RatingBadge(label: 'Tremor', value: checkIn.tremor),
              _RatingBadge(label: 'Stiffness', value: checkIn.stiffness),
              _RatingBadge(label: 'Slowness', value: checkIn.slowness),
              _RatingBadge(label: 'Balance', value: checkIn.balance),
            ],
          ),
          if (checkIn.note != null) ...<Widget>[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              checkIn.note!,
              style: TextStyle(
                fontSize: 15,
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One rating as a value circle over its label, in a quarter of the row.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: <Widget>[
          Container(
            height: 34,
            width: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
