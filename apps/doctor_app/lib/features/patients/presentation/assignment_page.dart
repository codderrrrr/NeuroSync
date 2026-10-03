import 'package:flutter/material.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../state/assignment_controller.dart';

/// The one assessment this phase can assign.
const String _kFingerTappingSlug = 'finger_tapping';

/// Matches the backend's `CreateAssignmentRequest` bounds so the slider can
/// never offer a duration the API will reject.
const int _kMinDuration = 10;
const int _kMaxDuration = 300;
const int _kDefaultDuration = 60;
const int _kSliderStep = 5;

const List<int> _kQuickDurations = <int>[30, 60, 90, 120, 180];

/// Assign an exercise to one patient.
///
/// A page rather than a dialog, because the doctor needs to see the plan they
/// are about to hand over: which assessment, how long, and under what title.
class AssignmentPage extends StatefulWidget {
  const AssignmentPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final int patientId;
  final String patientName;

  @override
  State<AssignmentPage> createState() => _AssignmentPageState();
}

class _AssignmentPageState extends State<AssignmentPage> {
  final TextEditingController _title = TextEditingController();
  int _duration = _kDefaultDuration;
  bool _submitting = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);

    final bool created =
        await AppScope.of(context).assignments.createAssignment(
              patientId: widget.patientId,
              title: _title.text,
              assessmentSlug: _kFingerTappingSlug,
              durationSeconds: _duration,
            );

    if (!mounted) {
      return;
    }
    if (created) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final AssignmentController assignments = AppScope.of(context).assignments;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: PortalPage(
          title: 'Assign exercise',
          subtitle: 'For ${widget.patientName}. They see the newest exercise '
              'on their next check-in.',
          child: ListenableBuilder(
            listenable: assignments,
            builder: (BuildContext context, Widget? child) => ListView(
              children: <Widget>[
                const _SectionLabel('Assessment'),
                const _AssessmentCard(),
                const SizedBox(height: 26),
                const _SectionLabel('Recording length'),
                _DurationField(
                  duration: _duration,
                  onChanged: (int value) => setState(() => _duration = value),
                ),
                const SizedBox(height: 26),
                const _SectionLabel('Title'),
                TextField(
                  controller: _title,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Finger Tapping',
                    counterText: '',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Optional. Defaults to the assessment name.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.darkSecondaryLabel,
                    ),
                  ),
                ),
                if (assignments.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 18),
                  _ErrorBanner(message: assignments.errorMessage!),
                ],
                const SizedBox(height: 28),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Assign',
                        isLoading: _submitting,
                        onPressed: _assign,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: AppTheme.darkSecondaryLabel,
        ),
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.touch_app_outlined,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Finger Tapping',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap the pad at a steady pace',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.darkSecondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, size: 20, color: scheme.primary),
        ],
      ),
    );
  }
}

class _DurationField extends StatelessWidget {
  const _DurationField({required this.duration, required this.onChanged});

  final int duration;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '$duration',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  letterSpacing: -0.5,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'seconds',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.darkSecondaryLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.outline,
              thumbColor: scheme.primary,
              overlayColor: scheme.primary.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: duration.toDouble(),
              min: _kMinDuration.toDouble(),
              max: _kMaxDuration.toDouble(),
              divisions: (_kMaxDuration - _kMinDuration) ~/ _kSliderStep,
              label: '$duration s',
              onChanged: (double value) => onChanged(value.round()),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int seconds in _kQuickDurations)
                _QuickChip(
                  seconds: seconds,
                  selected: seconds == duration,
                  onSelected: () => onChanged(seconds),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.seconds,
    required this.selected,
    required this.onSelected,
  });

  final int seconds;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$seconds seconds',
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outline,
              ),
            ),
            child: Text(
              '${seconds}s',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, size: 18, color: AppTheme.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 14, color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }
}
