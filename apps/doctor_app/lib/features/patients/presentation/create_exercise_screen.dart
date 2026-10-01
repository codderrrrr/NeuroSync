import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../../core/widgets/back_label.dart';
import '../state/assignment_controller.dart';

/// The one test available in this phase; the catalog grows later.
const String _kFingerTappingSlug = 'finger_tapping';

/// Quick-pick durations (seconds) alongside the free slider.
const List<int> _kQuickDurations = <int>[30, 60, 90, 120, 180];

const int _kMinDurationSeconds = 10;
const int _kMaxDurationSeconds = 300;

/// Assign a finger-tapping exercise to one patient, with a doctor-controlled
/// recording length.
class CreateExerciseScreen extends StatefulWidget {
  const CreateExerciseScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final int patientId;
  final String patientName;

  @override
  State<CreateExerciseScreen> createState() => _CreateExerciseScreenState();
}

class _CreateExerciseScreenState extends State<CreateExerciseScreen> {
  final TextEditingController _title = TextEditingController();
  int _durationSeconds = 60;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    final bool created =
        await AppScope.of(context).assignments.createAssignment(
              patientId: widget.patientId,
              title: _title.text,
              assessmentSlug: _kFingerTappingSlug,
              durationSeconds: _durationSeconds,
            );
    if (!mounted) {
      return;
    }
    if (created) {
      Navigator.of(context).pop(true);
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
                LargeTitle('Create exercise'),
                const SizedBox(height: 6),
                MutedText('For ${widget.patientName}. They see the newest '
                    'exercise on their next check-in.'),
                const SizedBox(height: 24),
                const SectionHeader('Exercise'),
                _TestCard(
                  selected: true,
                  durationSeconds: _durationSeconds,
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: MutedText(
                    'More assessments are coming in a later phase.',
                  ),
                ),
                const SizedBox(height: 24),
                const SectionHeader('Recording length'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Text(
                            '$_durationSeconds',
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentMint,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'seconds',
                            style: TextStyle(
                              fontSize: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _durationSeconds.toDouble(),
                        min: _kMinDurationSeconds.toDouble(),
                        max: _kMaxDurationSeconds.toDouble(),
                        divisions:
                            (_kMaxDurationSeconds - _kMinDurationSeconds) ~/ 5,
                        label: '$_durationSeconds s',
                        onChanged: (double value) =>
                            setState(() => _durationSeconds = value.round()),
                      ),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _kQuickDurations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (BuildContext context, int index) {
                            final int seconds = _kQuickDurations[index];
                            final bool selected =
                                seconds == _durationSeconds;
                            return ChoiceChip(
                              label: Text('${seconds}s'),
                              selected: selected,
                              onSelected: (bool _) => setState(
                                  () => _durationSeconds = seconds),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      const MutedText(
                        'Between 10 seconds and 5 minutes. The patient stops '
                        'automatically when time is up.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionHeader('Title (optional)'),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText: 'Finger Tapping',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),
                if (assignments.errorMessage != null) ...<Widget>[
                  ErrorText(assignments.errorMessage!),
                  const SizedBox(height: 14),
                ],
                PrimaryButton(
                  label: 'Assign exercise',
                  isLoading: assignments.isSubmitting,
                  onPressed: _assign,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.selected, required this.durationSeconds});

  final bool selected;
  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.accentMint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.touch_app_outlined,
              color: AppTheme.accentMint,
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
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap the pad at a steady pace',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle, color: AppTheme.active),
        ],
      ),
    );
  }
}
