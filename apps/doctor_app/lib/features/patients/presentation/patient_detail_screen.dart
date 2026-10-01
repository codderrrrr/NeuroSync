import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../../core/widgets/back_label.dart';
import '../state/assignment_controller.dart';
import 'create_exercise_screen.dart';

/// One linked patient: identity, relationship status and their assigned
/// exercises. Monitoring results are a later phase and are not shown.
class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final int patientId;
  final String patientName;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      AppScope.of(context).assignments.loadAssignments(widget.patientId);
    });
  }

  Future<void> _createExercise() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreateExerciseScreen(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
    if (created ?? false) {
      // The list reloads inside the controller; nothing else to do here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AssignmentController assignments = AppScope.of(context).assignments;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: assignments,
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              children: <Widget>[
                const BackLabel(),
                const SizedBox(height: 8),
                LargeTitle(widget.patientName),
                const SizedBox(height: 20),
                AppCard(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Patient ID',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.patientId}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.activeTint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'LINKED · ACTIVE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.active,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Exercises'),
                _AssignmentsBody(
                  controller: assignments,
                  patientId: widget.patientId,
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Create exercise',
                  onPressed: _createExercise,
                ),
                const SizedBox(height: 16),
                const AppCard(
                  child: MutedText(
                    'Recording results and trends arrive in a later phase. '
                    'This screen only manages what the patient is asked to do.',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AssignmentsBody extends StatelessWidget {
  const _AssignmentsBody({required this.controller, required this.patientId});

  final AssignmentController controller;
  final int patientId;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ErrorText(controller.errorMessage!),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: FilledButton.tonal(
                onPressed: () => AppScope.of(context)
                    .assignments
                    .loadAssignments(patientId),
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      );
    }
    if (!controller.hasLoaded) {
      return const AppCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (controller.assignments.isEmpty) {
      return const AppCard(
        child: MutedText(
          'No exercises assigned yet. Create one and the patient will see it '
          'on their next check-in.',
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final assignment in controller.assignments)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.touch_app_outlined,
                    color: AppTheme.accentMint,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          assignment.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatDate(assignment.createdAt)} · '
                          '${_formatDuration(assignment.durationSeconds)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _formatDate(DateTime date) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

String _formatDuration(int seconds) {
  if (seconds < 60) {
    return '$seconds s';
  }
  final int minutes = seconds ~/ 60;
  final int rest = seconds % 60;
  return rest == 0 ? '$minutes min' : '$minutes min ${rest}s';
}
