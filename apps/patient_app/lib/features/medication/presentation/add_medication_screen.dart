import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../core/widgets/app_text_field.dart';
import '../state/medication_controller.dart';

/// Records one medication the patient takes.
///
/// Dose and frequency are optional free text kept verbatim: the form offers no
/// picker, no unit, and no validation beyond "not empty", because the app has
/// no business second-guessing a prescribed regimen.
class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({super.key, required this.controller});

  final MedicationController controller;

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _dose = TextEditingController();
  final TextEditingController _frequency = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _frequency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bool added = await widget.controller.add(
      name: _name.text,
      doseLabel: _dose.text,
      frequencyLabel: _frequency.text,
    );
    if (!mounted) {
      return;
    }
    if (added) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Add medication'),
      ),
      body: SafeArea(
        // The controller reports validation and server errors through its own
        // listener, so the form has to rebuild against it: reading
        // `errorMessage` from a static build would never surface a failure.
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: <Widget>[
                const MutedText(
                  'Enter these exactly as they are written on your prescription '
                  'or label. Leave a field empty if you do not know it.',
                ),
                const SizedBox(height: 20),
                AppTextField(
                  label: 'Medication name',
                  controller: _name,
                  hintText: 'e.g. Levodopa',
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Dose (optional)',
                  controller: _dose,
                  hintText: 'e.g. 100mg',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'How often (optional)',
                  controller: _frequency,
                  hintText: 'e.g. 4 times daily',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (widget.controller.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 16),
                  ErrorText(widget.controller.errorMessage!),
                ],
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Save medication',
                  isLoading: widget.controller.isSubmitting,
                  onPressed: _save,
                  tactile: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
