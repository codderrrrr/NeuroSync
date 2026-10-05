import 'package:flutter/material.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../models/assessment_option.dart';
import '../models/assignment.dart';
import '../state/assignment_controller.dart';

/// Matches the backend's `CreateAssignmentRequest` bounds so the slider can
/// never offer a duration the API will reject.
const int _kMinDuration = 10;
const int _kMaxDuration = 300;
const int _kSliderStep = 5;

const List<int> _kQuickDurations = <int>[30, 60, 90, 120, 180];

/// Configure and hand over one exercise.
///
/// Doubles as the edit page: pass [existing] to change an exercise that is
/// already assigned. The test itself cannot be swapped when editing, because a
/// patient's recordings belong to the test they were taken for — removing and
/// reassigning keeps that history unambiguous.
///
/// The settings below the recording length are rendered from the catalog, so a
/// test that gains a new setting gains an editor for it with no change here.
class AssignmentPage extends StatefulWidget {
  const AssignmentPage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.existing,
  });

  final int patientId;
  final String patientName;

  /// The exercise being changed, or null when assigning a new one.
  final Assignment? existing;

  @override
  State<AssignmentPage> createState() => _AssignmentPageState();
}

class _AssignmentPageState extends State<AssignmentPage> {
  final TextEditingController _title = TextEditingController();
  String? _slug;
  int? _duration;
  Map<String, Object> _parameters = <String, Object>{};
  bool _submitting = false;

  bool get _isEditing => widget.existing != null;

  AssignmentController get _assignments => AppScope.of(context).assignments;

  AssessmentOption? get _selected {
    final AssignmentController assignments = _assignments;
    final String? slug = _slug;
    return slug == null ? null : assignments.assessmentFor(slug);
  }

  @override
  void initState() {
    super.initState();
    final Assignment? existing = widget.existing;
    _slug = existing?.assessmentSlug;
    _duration = existing?.durationSeconds;
    if (existing != null) {
      // Every field opens on what is stored, the title included. A blank title
      // box would be submitted as an empty title, so changing only the speed
      // would silently erase the name the doctor gave this exercise.
      _title.text = existing.title;
      _parameters = Map<String, Object>.of(existing.parameters);
    }
    // The catalogue drives the editor, so it has to be in hand before the first
    // build that renders a settings field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_assignments.hasLoadedCatalog) {
        _assignments.loadCatalog();
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// Seed every field from one test, so switching tests cannot leave a setting
  /// from the previous one behind.
  void _select(AssessmentOption option) {
    setState(() {
      _slug = option.slug;
      _duration ??= _isEditing
          ? widget.existing!.durationSeconds
          : option.defaultDurationSeconds;
      _parameters = _isEditing
          ? option.valuesFrom(widget.existing!.parameters)
          : option.defaultValues;
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final option = _selected;
    if (option == null) {
      return;
    }
    setState(() => _submitting = true);

    final AssignmentController assignments = _assignments;
    final bool saved = _isEditing
        ? await assignments.updateAssignment(
            patientId: widget.patientId,
            assignmentId: widget.existing!.id,
            title: _title.text.trim(),
            durationSeconds: _duration,
            parameters: _parameters,
          )
        : await assignments.createAssignment(
            patientId: widget.patientId,
            title: _title.text,
            assessmentSlug: option.slug,
            durationSeconds: _duration ?? option.defaultDurationSeconds,
            parameters: _parameters,
          );

    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final AssignmentController assignments = _assignments;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: PortalPage(
          title: _isEditing ? 'Edit exercise' : 'Assign exercise',
          subtitle: _isEditing
              ? 'For ${widget.patientName}. Changes apply from their next '
                  'check-in.'
              : 'For ${widget.patientName}. They see the newest exercise '
                  'on their next check-in.',
          // Everything below is read inside the builder, not above it. The
          // catalogue arrives after the first frame, and only this builder
          // re-runs when it does: resolving the test out here would pin it to
          // whatever the catalogue held at build time, which on the edit page
          // (where the test cannot be re-picked) is nothing at all.
          child: ListenableBuilder(
            listenable: assignments,
            builder: (BuildContext context, Widget? child) {
              final AssessmentOption? option = _selected;
              // A test held back after this exercise was assigned cannot be
              // changed: the backend refuses the edit, and the patient's plan
              // has stopped offering the exercise. Removing it is the way out,
              // so the doctor is told that instead of being offered a save
              // that can only fail.
              final bool heldBack = option != null && !option.isSupported;
              final int duration =
                  _duration ?? option?.defaultDurationSeconds ?? 60;
              return ListView(
                children: <Widget>[
                  const _SectionLabel('Test'),
                  _AssessmentPicker(
                    controller: assignments,
                    selectedSlug: _slug,
                    locked: _isEditing,
                    onSelected: _select,
                  ),
                  const SizedBox(height: 26),
                  const _SectionLabel('Recording length'),
                  _DurationField(
                    duration: duration,
                    onChanged: (int value) => setState(() => _duration = value),
                  ),
                  if (option != null &&
                      option.parameters.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 26),
                    _SectionLabel('How the patient does it'),
                    for (final AssessmentParameter parameter
                        in option.parameters)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ParameterField(
                          parameter: parameter,
                          value: _parameters[parameter.key] ??
                              parameter.defaultValue,
                          onChanged: (Object value) => setState(
                            () => _parameters[parameter.key] = value,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  const _SectionLabel('Title'),
                  TextField(
                    controller: _title,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: option?.title ?? 'Finger Tapping',
                      counterText: '',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Optional. Defaults to the test name.',
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
                  if (heldBack) ...<Widget>[
                    const SizedBox(height: 18),
                    const _HeldBackNote(),
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
                          label: _isEditing ? 'Save changes' : 'Assign',
                          isLoading: _submitting,
                          onPressed:
                              option == null || heldBack ? null : _submit,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
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

/// The tests this doctor can assign, one card each.
///
/// Built from the API catalogue rather than a hard-coded list, so the app can
/// never offer a test the backend would refuse.
class _AssessmentPicker extends StatelessWidget {
  const _AssessmentPicker({
    required this.controller,
    required this.selectedSlug,
    required this.locked,
    required this.onSelected,
  });

  final AssignmentController controller;
  final String? selectedSlug;
  final bool locked;
  final ValueChanged<AssessmentOption> onSelected;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasLoadedCatalog) {
      return const TableSkeleton(rows: 2, height: 62);
    }

    final List<AssessmentOption> options = controller.assessments;
    if (options.isEmpty) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load tests',
        message: 'Try again once you are back online.',
      );
    }

    return Column(
      children: <Widget>[
        for (final AssessmentOption option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AssessmentCard(
              option: option,
              selected: option.slug == selectedSlug,
              // Editing keeps the test fixed: their recordings belong to it.
              enabled: option.isSupported && !locked,
              onTap: () => onSelected(option),
            ),
          ),
      ],
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AssessmentOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  IconData get _icon {
    switch (option.slug) {
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

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: option.title,
      child: Material(
        color:
            selected ? scheme.primary.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: option.isSupported
                        ? scheme.primary.withValues(alpha: 0.14)
                        : AppTheme.darkSecondaryLabel.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    _icon,
                    color: option.isSupported
                        ? scheme.primary
                        : AppTheme.darkSecondaryLabel,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        option.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.isSupported
                            ? option.description
                            : 'Coming soon — this test is not ready to hand '
                                'out yet.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: option.isSupported
                              ? AppTheme.darkSecondaryLabel
                              : AppTheme.pending,
                        ),
                      ),
                      // A tag as well as the sentence, so a doctor scanning the
                      // list sees which tests they cannot pick without reading
                      // each description.
                      if (!option.isSupported) ...<Widget>[
                        const SizedBox(height: 8),
                        const StatusTag(
                          label: 'COMING SOON',
                          color: AppTheme.pending,
                          tint: AppTheme.pendingTint,
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 20, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One doctor-settable value, rendered from its catalog spec.
class _ParameterField extends StatelessWidget {
  const _ParameterField({
    required this.parameter,
    required this.value,
    required this.onChanged,
  });

  final AssessmentParameter parameter;
  final Object value;
  final ValueChanged<Object> onChanged;

  @override
  Widget build(BuildContext context) {
    if (parameter.isChoice) {
      return _ChoiceField(
          parameter: parameter, value: value, onChanged: onChanged);
    }
    if (parameter.isInteger) {
      return _IntegerField(
          parameter: parameter, value: value, onChanged: onChanged);
    }
    return _TextField(parameter: parameter, value: value, onChanged: onChanged);
  }
}

class _ParameterShell extends StatelessWidget {
  const _ParameterShell({
    required this.parameter,
    required this.child,
    this.trailing,
  });

  final AssessmentParameter parameter;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  parameter.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkLabel,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            parameter.helpText,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.parameter,
    required this.value,
    required this.onChanged,
  });

  final AssessmentParameter parameter;
  final Object value;
  final ValueChanged<Object> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ParameterShell(
      parameter: parameter,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final String option in parameter.choices)
            _QuickChip(
              label: AssessmentParameter.labelForChoice(option),
              selected: option == value,
              onSelected: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}

class _IntegerField extends StatelessWidget {
  const _IntegerField({
    required this.parameter,
    required this.value,
    required this.onChanged,
  });

  final AssessmentParameter parameter;
  final Object value;
  final ValueChanged<Object> onChanged;

  int get _current => value is int ? value as int : parameter.minimum ?? 1;

  int get _minimum => parameter.minimum ?? 1;
  int get _maximum => parameter.maximum ?? _minimum + 10;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return _ParameterShell(
      parameter: parameter,
      trailing: Text(
        '$_current',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: scheme.primary,
        ),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: scheme.primary,
          inactiveTrackColor: scheme.outline,
          thumbColor: scheme.primary,
          overlayColor: scheme.primary.withValues(alpha: 0.12),
        ),
        child: Slider(
          value: _current.clamp(_minimum, _maximum).toDouble(),
          min: _minimum.toDouble(),
          max: _maximum.toDouble(),
          divisions: _maximum - _minimum,
          label: '$_current',
          onChanged: (double next) => onChanged(next.round()),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.parameter,
    required this.value,
    required this.onChanged,
  });

  final AssessmentParameter parameter;
  final Object value;
  final ValueChanged<Object> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController(
      text: value is String ? value as String : '',
    );
    return _ParameterShell(
      parameter: parameter,
      child: TextField(
        controller: controller,
        maxLength: parameter.maxLength,
        style: const TextStyle(fontSize: 15),
        decoration: const InputDecoration(counterText: ''),
        onChanged: onChanged,
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
              value: duration.toDouble().clamp(
                    _kMinDuration.toDouble(),
                    _kMaxDuration.toDouble(),
                  ),
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
                  label: '${seconds}s',
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
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
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
              label,
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

/// Why an exercise built on a held-back test cannot be edited.
///
/// Deliberately not styled as an error: nothing has gone wrong, the test is
/// simply not being handed out yet, and the doctor's next step is a different
/// action rather than a retry.
class _HeldBackNote extends StatelessWidget {
  const _HeldBackNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.pendingTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.pending.withValues(alpha: 0.4)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.schedule_outlined, size: 18, color: AppTheme.pending),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This test is not ready to hand out yet, so this exercise can no '
              'longer be changed. Remove it from the patient to take it off '
              'their list.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: AppTheme.pending,
              ),
            ),
          ),
        ],
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
