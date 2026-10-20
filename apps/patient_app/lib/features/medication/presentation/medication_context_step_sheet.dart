import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../models/medication.dart';
import '../models/medication_context.dart';
import '../state/medication_controller.dart';

/// One step in the monitoring flow: did a dose happen before this recording?
///
/// Reached after the tapping recording and before the session is submitted, so
/// the timing the patient reports is the timing around the assessment they
/// just did. It is always skippable and never asks for more than the patient
/// actually knows: "not sure" and "continue without" are complete answers, and
/// the recording is submitted either way.
///
/// Pops the recorded dose event's id, or null when the patient chose to
/// continue without attaching any medication context.
class MedicationContextStepSheet extends StatefulWidget {
  const MedicationContextStepSheet({super.key, required this.controller});

  final MedicationController controller;

  /// Shows the sheet and returns the recorded dose event id, or null.
  static Future<int?> show(
    BuildContext context,
    MedicationController controller,
  ) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext sheetContext) =>
          MedicationContextStepSheet(controller: controller),
    );
  }

  @override
  State<MedicationContextStepSheet> createState() =>
      _MedicationContextStepSheetState();
}

class _MedicationContextStepSheetState
    extends State<MedicationContextStepSheet> {
  MedicationAdherence _adherence = MedicationAdherence.taken;
  DoseTimingChoice _timing = DoseTimingChoice.options[0];
  int? _selectedMedicationId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Preselect only when there is an obvious single answer. With no
    // medications at all the step simply has nothing to attach, which is a
    // perfectly normal state and must not look like an error.
    final List<Medication> active = widget.controller.activeMedications;
    if (active.length == 1) {
      _selectedMedicationId = active.first.id;
    }
  }

  Future<void> _submit() async {
    final int? medicationId = _selectedMedicationId;
    if (medicationId == null) {
      return;
    }
    setState(() => _isSaving = true);
    final MedicationEvent? event = await widget.controller.reportDose(
      medicationId: medicationId,
      adherence: _adherence,
      takenAt: _takenAt,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSaving = false);
    if (event == null) {
      // The report did not save. Attach nothing rather than guess: an
      // unrecorded dose must not become an invented one.
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(event.id);
  }

  /// Only a "taken" report carries a time. `notSure` deliberately sends no
  /// timestamp even when the patient also said they took it, because they
  /// told us they were unsure.
  DateTime? get _takenAt {
    if (_adherence != MedicationAdherence.taken || _timing.isUnknown) {
      return null;
    }
    return DateTime.now().subtract(Duration(minutes: _timing.minutesAgo!));
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final List<Medication> medications = widget.controller.activeMedications;
    final String? error = widget.controller.errorMessage;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const LargeTitle('Medication check'),
            const SizedBox(height: 6),
            const MutedText(
              'Optional. This helps your doctor read the recording in context. '
              'You can skip it, and "not sure" is a perfectly good answer.',
            ),
            const SizedBox(height: 20),
            const SectionHeader('Did you take your medication?'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final MedicationAdherence adherence
                    in MedicationAdherence.values)
                  _ChoiceChip(
                    label: adherence.label,
                    isSelected: _adherence == adherence,
                    onSelected: () => setState(() => _adherence = adherence),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_adherence == MedicationAdherence.taken) ...<Widget>[
              const SectionHeader('When?'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final DoseTimingChoice choice
                      in DoseTimingChoice.options)
                    _ChoiceChip(
                      label: choice.label,
                      isSelected: _timing == choice,
                      onSelected: () => setState(() => _timing = choice),
                    ),
                ],
              ),
            ],
            if (medications.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              const SectionHeader('Which one?'),
              const SizedBox(height: 8),
              for (final Medication medication in medications)
                _MedicationOption(
                  medication: medication,
                  isSelected: _selectedMedicationId == medication.id,
                  isEnabled: !_isSaving,
                  onSelected: () =>
                      setState(() => _selectedMedicationId = medication.id),
                ),
            ],
            if (medications.isEmpty) ...<Widget>[
              const SizedBox(height: 16),
              const _NoMedicationsNote(),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: 12),
              ErrorText(error),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: _isSaving ? 'Saving…' : 'Save and continue',
              isLoading: _isSaving,
              onPressed:
                  _selectedMedicationId == null || _isSaving ? null : _submit,
            ),
            const SizedBox(height: 10),
            // Always available: the recording is valid without medication
            // information, and a patient who does not want to answer must
            // never be trapped into guessing.
            SecondaryButton(
              label: 'Continue without',
              onPressed: _isSaving ? null : _close,
            ),
          ],
        ),
      ),
    );
  }
}

/// A small selectable pill. Local to this sheet so it cannot be mistaken for a
/// filter or a toggle that changes something.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? AppColors.of(context).primary.withValues(alpha: 0.16)
          : scheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onSelected,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? AppColors.of(context).primary
                  : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? AppColors.of(context).primary
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the patient has not recorded any medication yet.
class _NoMedicationsNote extends StatelessWidget {
  const _NoMedicationsNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const MutedText(
        'You have not added any medication yet. Add one from Home whenever '
        'you like — or just continue and this recording is saved without it.',
      ),
    );
  }
}

/// One selectable medication in the "which one?" list.
///
/// A hand-rolled row rather than a radio group: the selection has to look like
/// part of this sheet's flow, and a list of the patient's own medications is
/// short enough that a custom row reads no worse.
class _MedicationOption extends StatelessWidget {
  const _MedicationOption({
    required this.medication,
    required this.isSelected,
    required this.isEnabled,
    required this.onSelected,
  });

  final Medication medication;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? AppColors.of(context).primary.withValues(alpha: 0.12)
            : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isEnabled ? onSelected : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.of(context).primary
                    : scheme.outlineVariant,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected
                      ? AppColors.of(context).primary
                      : scheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    medication.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
