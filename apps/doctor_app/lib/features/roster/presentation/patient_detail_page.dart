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

  Future<void> _editExercise(Assignment assignment) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AssignmentPage(
          patientId: widget.patientId,
          patientName: widget.patientName,
          existing: assignment,
        ),
      ),
    );
  }

  Future<void> _removeExercise(Assignment assignment) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppTheme.darkBackground,
        title: const Text('Remove this exercise?'),
        content: Text(
          '${assignment.assessmentTitle} will no longer appear for '
          '${widget.patientName}. Anything they have already recorded is '
          'kept.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppTheme.darkSecondaryLabel,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await AppScope.of(context).assignments.removeAssignment(
          patientId: widget.patientId,
          assignmentId: assignment.id,
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
            builder: (BuildContext context, Widget? child) => _ExerciseList(
              controller: assignments,
              onEdit: _editExercise,
              onRemove: _removeExercise,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  const _ExerciseList({
    required this.controller,
    required this.onEdit,
    required this.onRemove,
  });

  final AssignmentController controller;
  final ValueChanged<Assignment> onEdit;
  final ValueChanged<Assignment> onRemove;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null && !controller.hasLoaded) {
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
        message: 'Assign a motor exercise and it becomes the newest plan '
            'this patient sees on their next check-in.',
      );
    }

    final List<Assignment> items = controller.assignments;
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) => _ExerciseRow(
        assignment: items[index],
        controller: controller,
        onEdit: () => onEdit(items[index]),
        onRemove: () => onRemove(items[index]),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.assignment,
    required this.controller,
    required this.onEdit,
    required this.onRemove,
  });

  final Assignment assignment;
  final AssignmentController controller;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 15, 12, 15),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(assignment),
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
              if (assignment.isRemoved)
                const StatusTag(
                  label: 'REMOVED',
                  color: AppTheme.darkSecondaryLabel,
                  tint: Color(0x22000000),
                )
              else
                StatusTag(
                  label: _formatDuration(assignment.durationSeconds),
                  color: scheme.primary,
                  tint: scheme.primary.withValues(alpha: 0.12),
                ),
            ],
          ),
          if (assignment.parameters.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _SettingsSummary(parameters: assignment.parameters),
          ],
          if (!assignment.isRemoved) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _RowAction(
                  icon: Icons.tune_outlined,
                  label: 'Edit',
                  onPressed: controller.isSubmitting ? null : onEdit,
                ),
                const SizedBox(width: 4),
                _RowAction(
                  icon: Icons.delete_outline,
                  label: 'Remove',
                  danger: true,
                  onPressed: controller.isSubmitting ? null : onRemove,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(Assignment assignment) {
    switch (assignment.assessmentSlug) {
      case 'spiral_drawing':
        return Icons.grain_outlined;
      case 'line_tracing':
        return Icons.horizontal_rule_outlined;
      case 'handwriting':
        return Icons.draw_outlined;
      default:
        return Icons.touch_app_outlined;
    }
  }
}

/// What the doctor chose, in one quiet line.
///
/// Shows the stored values verbatim rather than re-labelling them: the doctor
/// needs to see what the patient will actually be asked to do, and the app has
/// no business paraphrasing it.
class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({required this.parameters});

  final Map<String, Object> parameters;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = parameters.entries
        .map((MapEntry<String, Object> entry) =>
            '${_label(entry.key)}: ${entry.value}')
        .toList(growable: false);
    return Text(
      parts.join(' · '),
      style: const TextStyle(
        fontSize: 12,
        height: 1.4,
        color: AppTheme.darkSecondaryLabel,
      ),
    );
  }

  static String _label(String key) {
    switch (key) {
      case 'pacing':
        return 'Speed';
      case 'hand':
        return 'Hand';
      case 'finger':
        return 'Finger';
      case 'repetitions':
        return 'Repetitions';
      case 'turns':
        return 'Turns';
      case 'phrase':
        return 'Phrase';
      case 'size_percent':
        return 'Size';
      case 'line_length_percent':
        return 'Length';
      default:
        return key.replaceAll('_', ' ');
    }
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? AppTheme.danger : AppTheme.darkSecondaryLabel;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
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
