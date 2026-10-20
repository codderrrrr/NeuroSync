import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../auth/state/auth_controller.dart';
import '../../medication/presentation/medications_screen.dart';
import '../../medication/state/medication_controller.dart';
import '../../monitoring/canvas/canvas_runner_screen.dart';
import '../../monitoring/finger_tapping/finger_tapping_runner_screen.dart';
import '../../monitoring/models/monitoring_plan.dart';
import '../../monitoring/models/monitoring_session.dart';
import '../../monitoring/presentation/session_result_screen.dart';
import '../../monitoring/presentation/todays_assessment_card.dart';
import '../../monitoring/state/monitoring_controller.dart';

/// Patient home: today's monitoring, profile summary and sign-out.
///
/// Doctor linking and check-ins each live on their own tab of the signed-in
/// shell, so this screen stays account + monitoring only.
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
      AppScope.of(context).monitoring.loadPlan();
    });
  }

  /// Re-reads the plan and the medication list for a pull-to-refresh.
  ///
  /// The same reads the shell performs on its timer; here the patient asked for
  /// them, so the spinner waits for them to finish.
  Future<void> _refresh() async {
    final AppScope scope = AppScope.of(context);
    await Future.wait<void>(<Future<void>>[
      scope.monitoring.loadPlan(),
      scope.medications.load(),
    ]);
  }

  Future<void> _signOut() async {
    final AppScope scope = AppScope.of(context);
    scope.doctorLinks.clear();
    scope.checkIns.clear();
    scope.monitoring.clear();
    scope.medications.clear();
    await scope.auth.signOut();
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

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable:
              Listenable.merge(<Listenable>[auth, monitoring, medications]),
          builder: (BuildContext context, Widget? child) {
            // Pulling down is the patient asking to check again now, rather
            // than waiting for the shell's next refresh.
            return RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.accentMint,
              backgroundColor: AppTheme.darkSurface,
              child: ListView(
                // Keeps the pull available even when the page is shorter than
                // the viewport, which is the usual case before any plan exists.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
                children: <Widget>[
                  LargeTitle('Hi, ${auth.patient?.firstName ?? 'there'}'),
                  const SizedBox(height: 6),
                  const MutedText('You are signed in to NeuroSync.'),
                  const SizedBox(height: 24),
                  const SectionHeader('Monitoring'),
                  TodaysAssessmentCard(
                    plan: monitoring.plan,
                    isLoading: monitoring.isLoading,
                    errorMessage: monitoring.errorMessage,
                    onStart: (_) => _startAssessment(monitoring),
                    onRetry: monitoring.loadPlan,
                  ),
                  const SizedBox(height: 26),
                  const SectionHeader('Medications'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MedicationsScreen(controller: medications),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Medication list',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                medications.medications.isEmpty
                                    ? 'Add what you take so recordings can carry '
                                        'timing context'
                                    : '${medications.activeMedications.length} '
                                        'current · used as context on results',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppTheme.darkSecondaryLabel,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const SectionHeader('Account'),
                  // One quiet line rather than a card of label/value rows: the
                  // patient already knows their own name, and this screen is for
                  // today's monitoring, not for settings.
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                auth.patient?.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                auth.patient?.email ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const _SignedInDot(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const MutedText(
                    'Your check-ins are shared only with doctors you link. '
                    'Find them under the Doctors tab.',
                  ),
                  const SizedBox(height: 24),
                  SecondaryButton(
                    label: 'Log out',
                    color: AppTheme.danger,
                    onPressed: _signOut,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SignedInDot extends StatelessWidget {
  const _SignedInDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppTheme.active,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'Signed in',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
