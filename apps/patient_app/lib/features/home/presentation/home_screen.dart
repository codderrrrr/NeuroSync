import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../auth/state/auth_controller.dart';
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

  Future<void> _signOut() async {
    final AppScope scope = AppScope.of(context);
    scope.doctorLinks.clear();
    scope.checkIns.clear();
    scope.monitoring.clear();
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
      builder: (_) => FingerTappingRunnerScreen(
        controller: monitoring,
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
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: SafeArea(
          child: SessionResultScreen(
            assessmentTitle: completed.assessment.title,
            completedAt: completed.completedAt,
            result: completed.result!,
            onDone: () => Navigator.of(context).pop(),
          ),
        ),
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

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[auth, monitoring]),
          builder: (BuildContext context, Widget? child) {
            return ListView(
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
                const SizedBox(height: 28),
                const SectionHeader('Account'),
                AppCard(
                  child: Column(
                    children: <Widget>[
                      _DetailRow(
                        label: 'Name',
                        value: auth.patient?.name ?? '',
                      ),
                      const Divider(height: 26),
                      _DetailRow(
                          label: 'Email', value: auth.patient?.email ?? ''),
                      const Divider(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const _SignedInPill(),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Sharing'),
                const AppCard(
                  child: MutedText(
                    'Your check-ins are shared only with doctors you link. '
                    'Find them under the Doctors tab.',
                  ),
                ),
                const SizedBox(height: 24),
                SecondaryButton(
                  label: 'Log out',
                  color: AppTheme.danger,
                  onPressed: _signOut,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignedInPill extends StatelessWidget {
  const _SignedInPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.activeTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'SIGNED IN',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.active,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
