import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/app_text_field.dart';
import '../state/check_in_controller.dart';

/// Records one symptom check-in: four severity ratings and an optional note.
///
/// The ratings are the patient's own observations and are sent to the server
/// exactly as chosen; nothing here is scored, graded or interpreted.
class NewCheckInScreen extends StatefulWidget {
  const NewCheckInScreen({super.key});

  @override
  State<NewCheckInScreen> createState() => _NewCheckInScreenState();
}

class _NewCheckInScreenState extends State<NewCheckInScreen> {
  final TextEditingController _noteController = TextEditingController();

  int _tremor = 0;
  int _stiffness = 0;
  int _slowness = 0;
  int _balance = 0;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final CheckInController controller = AppScope.of(context).checkIns;
    FocusScope.of(context).unfocus();
    final bool succeeded = await controller.create(
      tremor: _tremor,
      stiffness: _stiffness,
      slowness: _slowness,
      balance: _balance,
      note: _noteController.text,
    );
    if (!mounted || !succeeded) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final CheckInController controller = AppScope.of(context).checkIns;

    return Scaffold(
      appBar: AppBar(title: const Text('New check-in')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: <Widget>[
                const AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Rate what you notice right now.',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6),
                      MutedText(
                        'These are your own observations, saved exactly as you '
                        'report them. Nothing here is scored or interpreted.',
                      ),
                      SizedBox(height: 14),
                      MutedText('0 = not present   ·   4 = severe'),
                    ],
                  ),
                ),
                if (controller.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 16),
                  ErrorText(controller.errorMessage!),
                ],
                const SizedBox(height: 16),
                _SeverityField(
                  label: 'Tremor',
                  value: _tremor,
                  onChanged: (int value) => setState(() => _tremor = value),
                ),
                const SizedBox(height: 12),
                _SeverityField(
                  label: 'Stiffness',
                  value: _stiffness,
                  onChanged: (int value) => setState(() => _stiffness = value),
                ),
                const SizedBox(height: 12),
                _SeverityField(
                  label: 'Slowness',
                  value: _slowness,
                  onChanged: (int value) => setState(() => _slowness = value),
                ),
                const SizedBox(height: 12),
                _SeverityField(
                  label: 'Balance',
                  value: _balance,
                  onChanged: (int value) => setState(() => _balance = value),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Note (optional)',
                  controller: _noteController,
                  hintText: 'Anything else you noticed today',
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enabled: !controller.isSubmitting,
                  validator: _validateNote,
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Save check-in',
                  isLoading: controller.isSubmitting,
                  onPressed: _save,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String? _validateNote(String? value) {
    if ((value ?? '').trim().length > 500) {
      return 'Keep the note to 500 characters or fewer';
    }
    return null;
  }
}

/// One labelled row of selectable 0-4 ratings.
class _SeverityField extends StatelessWidget {
  const _SeverityField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (int rating = 0; rating <= 4; rating++)
                _SeverityDot(
                  value: rating,
                  selected: rating == value,
                  onTap: () => onChanged(rating),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single circular rating button.
class _SeverityDot extends StatelessWidget {
  const _SeverityDot({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$value of 4',
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outline,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            width: 40,
            child: Center(
              child: Text(
                '$value',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
