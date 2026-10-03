import 'package:flutter/material.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../patients/models/assignment.dart';
import '../../patients/presentation/assignment_page.dart';
import '../../patients/state/assignment_controller.dart';

/// One linked patient: who they are, and the exercises assigned to them.
///
/// Only what the API actually returns is shown. Monitoring results and
/// check-ins are not available to this app yet, so they are not listed as
/// empty sections that would promise something that cannot be delivered.
class PatientDetailPage extends StatefulWidget {
  const PatientDetailPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final int patientId;
  final String patientName;

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppScope.of(context).assignments.loadAssignments(widget.patientId);
      }
    });
  }

  Future<void> _createExercise() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AssignmentPage(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AssignmentController assignments = AppScope.of(context).assignments;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: PortalPage(
          title: widget.patientName,
          subtitle: 'Patient #${widget.patientId} · linked and active',
          actions: <Widget>[
            SecondaryButton(
              label: 'Assign exercise',
              onPressed: _createExercise,
            ),
          ],
          child: ListenableBuilder(
            listenable: assignments,
            builder: (BuildContext context, Widget? child) =>
                _ExerciseList(controller: assignments),
          ),
        ),
      ),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  const _ExerciseList({required this.controller});

  final AssignmentController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load exercises',
          message: controller.errorMessage!,
        ),
      );
    }
    if (!controller.hasLoaded) {
      return const TableSkeleton(rows: 3, height: 60);
    }
    if (controller.assignments.isEmpty) {
      return const EmptyState(
        icon: Icons.touch_app_outlined,
        title: 'No exercises assigned yet',
        message:
            'Assign a finger-tapping exercise and it becomes the newest plan '
            'this patient sees on their next check-in.',
      );
    }

    final List<Assignment> items = controller.assignments;
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) =>
          _ExerciseRow(assignment: items[index]),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.touch_app_outlined,
              size: 19,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  assignment.title,
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
                  assignment.assessmentTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.darkSecondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatusTag(
            label: _formatDuration(assignment.durationSeconds),
            color: scheme.primary,
            tint: scheme.primary.withValues(alpha: 0.12),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds < 60) {
    return '$seconds s';
  }
  final int minutes = seconds ~/ 60;
  final int rest = seconds % 60;
  return rest == 0 ? '$minutes min' : '$minutes min ${rest}s';
}
