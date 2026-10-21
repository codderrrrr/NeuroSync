import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/formatting/date_format.dart';
import '../../../core/widgets/soft_panel.dart';
import '../../../core/widgets/stat_strip.dart';
import '../../check_ins/models/check_in.dart';
import '../../check_ins/presentation/new_check_in_screen.dart';
import '../../check_ins/state/check_in_controller.dart';
import '../../monitoring/models/longitudinal_summary.dart';
import '../../monitoring/models/monitoring_session.dart';
import '../../monitoring/models/session_result.dart';
import '../../monitoring/state/monitoring_controller.dart';

/// The tests screen: what the patient has recorded, and how it went.
///
/// Two things live here, because they are two halves of the same question.
/// **Tests** are the motor recordings and what the backend made of them.
/// **Check-ins** are what the patient noticed about themselves. The patient
/// recorded both on the same day, and reading them apart in two places means
/// one of them gets forgotten.
class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  bool _showingTests = true;

  @override
  void initState() {
    super.initState();
    // Load once the first frame is up so notifying listeners never happens
    // during this widget's build.
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
    final CheckInController checkIns = AppScope.of(context).checkIns;
    final MonitoringController monitoring = AppScope.of(context).monitoring;

    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[checkIns, monitoring]),
        builder: (BuildContext context, Widget? child) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: <Widget>[
              const Reveal(child: LargeTitle('Tests')),
              Reveal(
                delay: const Duration(milliseconds: 60),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(height: 4),
                    MutedText(
                      'Your recordings, and what you noticed about yourself.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Reveal(
                delay: const Duration(milliseconds: 110),
                child: SegmentedToggle(
                  labels: const <String>['Tests', 'Check-ins'],
                  selectedIndex: _showingTests ? 0 : 1,
                  onChanged: (int index) {
                    HapticFeedback.selectionClick();
                    setState(() => _showingTests = index == 0);
                  },
                ),
              ),
              const SizedBox(height: 18),
              if (_showingTests)
                ..._tests(monitoring)
              else
                ..._checkIns(checkIns),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _tests(MonitoringController monitoring) {
    final List<MonitoringSession> history = monitoring.history;

    if (monitoring.isLoading && !monitoring.hasLoadedHistory) {
      return <Widget>[const _LoadingPanel()];
    }

    if (history.isEmpty) {
      return const <Widget>[
        SoftPanel(
          child: EmptyNote(
            icon: Icons.insights_outlined,
            title: 'No recordings yet',
            message: 'Your first test will appear here once you have done one.',
          ),
        ),
      ];
    }

    return <Widget>[
      _TestSummary(history: history),
      const SizedBox(height: 16),
      for (final MonitoringSession session in history) ...<Widget>[
        _TestRow(session: session),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _checkIns(CheckInController controller) {
    return <Widget>[
      PrimaryButton(
        label: 'Record a check-in',
        onPressed: _openNewCheckIn,
        tactile: true,
      ),
      const SizedBox(height: 16),
      if (controller.errorMessage != null) ...<Widget>[
        ErrorText(controller.errorMessage!),
        const SizedBox(height: 12),
      ],
      if (controller.isLoading && !controller.hasLoaded)
        const _LoadingPanel()
      else if (controller.checkIns.isEmpty)
        const SoftPanel(
          child: EmptyNote(
            icon: Icons.fact_check_outlined,
            title: 'No check-ins yet',
            message: 'Record one to start a history of how you have been '
                'feeling.',
          ),
        )
      else
        for (final CheckIn checkIn in controller.checkIns) ...<Widget>[
          _CheckInRow(checkIn: checkIn),
          const SizedBox(height: 10),
        ],
    ];
  }
}

/// The counts at the top of the tests list.
///
/// These are the patient's own numbers, counting their own recordings. Nothing
/// here compares them with anyone else.
class _TestSummary extends StatelessWidget {
  const _TestSummary({required this.history});

  final List<MonitoringSession> history;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    final int usable = history
        .where(
          (MonitoringSession session) =>
              session.result?.quality == RecordingQuality.valid ||
              session.result?.quality == RecordingQuality.borderline,
        )
        .length;
    final int changed = history
        .where(
          (MonitoringSession session) =>
              session.longitudinal?.state == LongitudinalState.changed,
        )
        .length;

    final DateTime now = DateTime.now();
    final DateTime weekAgo = now.subtract(const Duration(days: 7));
    final int thisWeek = history
        .where(
          (MonitoringSession session) =>
              (session.completedAt ?? session.startedAt).isAfter(weekAgo),
        )
        .length;

    return StatStrip(
      stats: <StatEntry>[
        StatEntry(
          value: '$thisWeek',
          caption: 'this week',
          icon: Icons.calendar_today_outlined,
          emphasis: true,
        ),
        StatEntry(
          value: '$usable',
          caption: 'usable',
          icon: Icons.check_circle_outline,
        ),
        StatEntry(
          value: '$changed',
          caption: 'differing',
          icon: Icons.trending_up,
          valueColor: changed == 0 ? null : colors.pending,
        ),
      ],
    );
  }
}

/// One recording, with what the backend made of it.
class _TestRow extends StatelessWidget {
  const _TestRow({required this.session});

  final MonitoringSession session;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final SessionResult? result = session.result;
    final LongitudinalSummary? longitudinal = session.longitudinal;
    final DateTime when = session.completedAt ?? session.startedAt;

    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      session.assessment.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: colors.label,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatShortDateTime(when),
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12,
                        height: 1.35,
                        color: colors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (result != null)
                StatePill(
                  label: _qualityLabel(result.quality).toUpperCase(),
                  color: _qualityColor(context, result.quality),
                  tint: _qualityColor(context, result.quality)
                      .withValues(alpha: 0.14),
                ),
            ],
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 10),
            // The numbers of the recording itself, plainly labelled.
            Row(
              children: <Widget>[
                _Measure(
                  value: '${result.movementCount}',
                  label: result.movementLabel,
                ),
                const SizedBox(width: 16),
                _Measure(
                  value: _seconds(result.durationMs),
                  label: 'long',
                ),
                const SizedBox(width: 16),
                _Measure(
                  value: _seconds(result.longestPauseMs),
                  label: 'longest gap',
                ),
              ],
            ),
          ],
          if (longitudinal != null) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                StatePill(
                  label: longitudinal.state.shortLabel.toUpperCase(),
                  color: _longitudinalColor(context, longitudinal.state),
                  tint: _longitudinalColor(context, longitudinal.state)
                      .withValues(alpha: 0.14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              longitudinal.state.explanation,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                height: 1.4,
                color: colors.secondaryLabel,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _qualityLabel(RecordingQuality quality) => quality.label;

  static Color _qualityColor(BuildContext context, RecordingQuality quality) {
    final AppColors colors = AppColors.of(context);
    switch (quality) {
      case RecordingQuality.valid:
        return colors.active;
      case RecordingQuality.borderline:
        return colors.pending;
      case RecordingQuality.invalid:
      case RecordingQuality.incomplete:
        return colors.danger;
    }
  }

  static Color _longitudinalColor(
    BuildContext context,
    LongitudinalState state,
  ) {
    final AppColors colors = AppColors.of(context);
    switch (state) {
      case LongitudinalState.withinBaseline:
        return colors.active;
      case LongitudinalState.changed:
        return colors.pending;
      case LongitudinalState.insufficientData:
      case LongitudinalState.unreliable:
        return colors.secondaryLabel;
    }
  }

  static String _seconds(int ms) =>
      ms >= 1000 ? '${(ms / 1000).round()}s' : '${ms}ms';
}

/// One number with its label, in a row of measurements.
class _Measure extends StatelessWidget {
  const _Measure({required this.value, required this.label});

  final String value;
  final String label;

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
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: colors.label,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 11,
            height: 1.3,
            color: colors.secondaryLabel,
          ),
        ),
      ],
    );
  }
}

/// One symptom check-in.
class _CheckInRow extends StatelessWidget {
  const _CheckInRow({required this.checkIn});

  final CheckIn checkIn;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final DateTime when = checkIn.recordedAt;

    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            formatShortDateTime(when),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 12,
              height: 1.35,
              color: colors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _Symptom(label: 'Tremor', level: checkIn.tremor),
              _Symptom(label: 'Stiffness', level: checkIn.stiffness),
              _Symptom(label: 'Slowness', level: checkIn.slowness),
              _Symptom(label: 'Balance', level: checkIn.balance),
            ],
          ),
          if (checkIn.note != null && checkIn.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              checkIn.note!,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                height: 1.4,
                color: colors.label,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One symptom, as the patient rated it: 0 is none, 4 is the worst.
class _Symptom extends StatelessWidget {
  const _Symptom({required this.label, required this.level});

  final String label;
  final int level;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color color = level == 0
        ? colors.secondaryLabel
        : level <= 2
            ? colors.pending
            : colors.danger;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 10,
              height: 1.2,
              color: colors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 4),
          // A row of bars rather than a number: the patient rated a feeling,
          // not a measurement, and a bar reads at a glance.
          Row(
            children: <Widget>[
              for (int step = 0; step < 4; step++) ...<Widget>[
                if (step > 0) const SizedBox(width: 2),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: step < level ? color : colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const SoftPanel(
      child: Center(child: CalmLoader(size: 20)),
    );
  }
}
