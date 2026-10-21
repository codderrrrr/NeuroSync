import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/soft_panel.dart';
import '../../auth/state/auth_controller.dart';
import '../../medication/state/medication_controller.dart';
import '../../monitoring/canvas/canvas_runner_screen.dart';
import '../../monitoring/finger_tapping/finger_tapping_runner_screen.dart';
import '../../monitoring/models/monitoring_plan.dart';
import '../../monitoring/models/monitoring_session.dart';
import '../../monitoring/models/session_result.dart';
import '../../monitoring/presentation/session_result_screen.dart';
import '../../monitoring/presentation/todays_assessment_card.dart';
import '../../monitoring/state/monitoring_controller.dart';

/// The patient's home: how they are doing, and the one thing to do next.
///
/// The account details that used to sit at the bottom of this screen have
/// their own destination now. What is left here is what a patient opens the
/// app to find: whether today's test is done, whether their medicine was
/// taken, and how the last few recordings went.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load the monitoring plan once the first frame is up so notifying
    // listeners never happens during this widget's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final AppScope scope = AppScope.of(context);
      scope.monitoring.loadPlan();
      scope.monitoring.loadHistory();
      scope.medications.load();
    });
  }

  /// Re-reads the plan, the history and the medication list for a
  /// pull-to-refresh.
  ///
  /// The same reads the shell performs on its timer; here the patient asked for
  /// them, so the spinner waits for them to finish.
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    await Future.wait<void>(<Future<void>>[
      scope.monitoring.loadPlan(),
      scope.monitoring.loadHistory(),
      scope.medications.load(),
    ]);
  }

  Future<void> _startAssessment(MonitoringController monitoring) async {
    final MonitoringPlanItem? next = monitoring.plan?.nextAvailableItem;
    if (monitoring.plan == null || next == null) {
      return;
    }
    // Guard mirrored from the backend: only assessments with a runner can be
    // launched, so an unsupported item can never open a broken flow.
    if (!next.assessment.isExecutable) {
      return;
    }

    final bool submitted = await monitoring.startSession(next);
    if (!mounted || !submitted) {
      return;
    }

    final MonitoringSession? completed = await Navigator.of(context)
        .push<MonitoringSession>(MaterialPageRoute<MonitoringSession>(
      builder: (_) => next.assessment.isCanvas
          // Tracing tests have no dose-timing step: there is no longitudinal
          // comparison for the timing to support yet.
          ? CanvasRunnerScreen(
              controller: monitoring,
              item: next,
              onCompleted: (MonitoringSession session) =>
                  Navigator.of(context).pop(session),
            )
          : FingerTappingRunnerScreen(
              controller: monitoring,
              medications: AppScope.of(context).medications,
              durationSeconds: next.effectiveDurationSeconds,
              assessmentTitle: next.assessment.title,
              instructions: next.assessment.instructions,
            ),
    ));

    if (completed == null) {
      // The runner was closed without finishing; refresh plan state anyway.
      await monitoring.loadPlan();
      return;
    }

    // Reload the plan so the card reflects today's completion, then show the
    // result the backend stored.
    await monitoring.loadPlan();
    if (!mounted) {
      return;
    }
    // SessionResultScreen is a complete screen with its own Scaffold and
    // SafeArea; wrapping it again doubled the system insets on this route.
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => SessionResultScreen(
        assessmentTitle: completed.assessment.title,
        completedAt: completed.completedAt,
        result: completed.result!,
        longitudinal: completed.longitudinal,
        onDone: () => Navigator.of(context).pop(),
      ),
    ));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AuthController auth = scope.auth;
    final MonitoringController monitoring = scope.monitoring;
    final MedicationController medications = scope.medications;

    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(
          <Listenable>[auth, monitoring, medications],
        ),
        builder: (BuildContext context, Widget? child) {
          // Pulling down is the patient asking to check again now, rather
          // than waiting for the shell's next refresh.
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.of(context).primary,
            backgroundColor: AppColors.of(context).surface,
            child: ListView(
              // Keeps the pull available even when the page is shorter than
              // the viewport, which is the usual case before any plan exists.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: <Widget>[
                LargeTitle('Hi, ${auth.patient?.firstName ?? 'there'}'),
                const SizedBox(height: 4),
                const MutedText('Here is where you are today.'),
                const SizedBox(height: 18),
                _TodayStats(
                  monitoring: monitoring,
                  medications: medications,
                ),
                const SizedBox(height: 20),
                const SectionHeader("Today's test"),
                const SizedBox(height: 10),
                TodaysAssessmentCard(
                  plan: monitoring.plan,
                  isLoading: monitoring.isLoading,
                  errorMessage: monitoring.errorMessage,
                  onStart: (_) => _startAssessment(monitoring),
                  onRetry: monitoring.loadPlan,
                ),
                const SizedBox(height: 20),
                const SectionHeader('Recent recordings'),
                const SizedBox(height: 10),
                _RecentRecordings(monitoring: monitoring),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The counts the patient opens the app to see.
///
/// All of them are about today or this week, because a number from six months
/// ago is not what a patient is asking about when they open the app.
class _TodayStats extends StatelessWidget {
  const _TodayStats({required this.monitoring, required this.medications});

  final MonitoringController monitoring;
  final MedicationController medications;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    final MonitoringPlanItem? next = monitoring.plan?.nextAvailableItem;
    final bool doneToday = next == null;
    final int todayCount = monitoring.plan?.completedTodayCount ?? 0;
    final int medicines = medications.activeMedications.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The three tiles read as one row of numbers, so they are the same
        // height. IntrinsicHeight is what makes that possible in a list,
        // where the row has no height of its own to divide up.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: StatTile(
                  value: doneToday ? 'Done' : 'To do',
                  caption: doneToday ? "today's test" : "today's test",
                  icon: doneToday
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  valueColor: doneToday ? colors.active : colors.label,
                  emphasis: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '$todayCount',
                  caption:
                      todayCount == 1 ? 'test done today' : 'tests done today',
                  icon: Icons.timelapse_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '$medicines',
                  caption: medicines == 1
                      ? 'medicine recorded'
                      : 'medicines recorded',
                  icon: Icons.medication_outlined,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The last few recordings, newest first.
///
/// A patient who wants the full history gets it from the Tests tab; what
/// belongs on the home screen is only enough to answer "is this going the
/// same way as last time?".
class _RecentRecordings extends StatelessWidget {
  const _RecentRecordings({required this.monitoring});

  final MonitoringController monitoring;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final List<MonitoringSession> history = monitoring.history;

    if (monitoring.isLoading && !monitoring.hasLoadedHistory) {
      return const SoftPanel(
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (history.isEmpty) {
      return const SoftPanel(
        child: MutedText('Your recordings will appear here.'),
      );
    }

    final List<MonitoringSession> recent = history.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final MonitoringSession session in recent) ...<Widget>[
          SoftPanel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: colors.label,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _when(session),
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
                if (session.result != null)
                  StatePill(
                    label: session.result!.quality.label.toUpperCase(),
                    color: _qualityColor(colors, session.result!.quality),
                    tint: _qualityColor(colors, session.result!.quality)
                        .withValues(alpha: 0.14),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  static String _when(MonitoringSession session) {
    final DateTime when = session.completedAt ?? session.startedAt;
    return '${when.day}/${when.month}';
  }

  static Color _qualityColor(AppColors colors, RecordingQuality quality) {
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
}
