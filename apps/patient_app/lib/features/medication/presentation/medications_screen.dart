import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../models/medication.dart';
import '../state/medication_controller.dart';
import 'add_medication_screen.dart';

/// The patient's own medication list.
///
/// A plain record of what they take, kept as free text. There is no editing of
/// doses, no reminders, and no advice: the app records the regimen and leaves
/// every clinical decision to the patient's care team.
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key, required this.controller});

  final MedicationController controller;

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.load();
      }
    });
  }

  Future<void> _addMedication() async {
    final bool? added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddMedicationScreen(controller: widget.controller),
      ),
    );
    if (added ?? false) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (BuildContext context, Widget? child) {
            final List<Medication> medications = widget.controller.medications;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              children: <Widget>[
                const LargeTitle('Medications'),
                const SizedBox(height: 6),
                const MutedText(
                  'Recorded exactly as you enter them. NeuroSync does not '
                  'check doses or suggest changes.',
                ),
                const SizedBox(height: 20),
                if (widget.controller.errorMessage != null) ...<Widget>[
                  ErrorText(widget.controller.errorMessage!),
                  const SizedBox(height: 12),
                ],
                if (widget.controller.isLoading && medications.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (medications.isEmpty)
                  AppCard(
                    child: MutedText(
                      widget.controller.hasLoaded
                          ? 'No medications recorded yet. Add one to attach '
                              'timing context to your monitoring sessions.'
                          : 'Could not load your medications.',
                    ),
                  )
                else
                  for (final Medication medication in medications)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MedicationRow(
                        medication: medication,
                        controller: widget.controller,
                      ),
                    ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Add medication',
                  onPressed: _addMedication,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({required this.medication, required this.controller});

  final Medication medication;
  final MedicationController controller;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  medication.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (medication.doseLabel != null ||
                    medication.frequencyLabel != null) ...<Widget>[
                  const SizedBox(height: 4),
                  MutedText(
                    <String?>[
                      medication.doseLabel,
                      medication.frequencyLabel,
                    ].whereType<String>().join(' · '),
                  ),
                ],
                if (!medication.isActive) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'NO LONGER CURRENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.of(context).secondaryLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => controller.setActive(
              medicationId: medication.id,
              isActive: !medication.isActive,
            ),
            child:
                Text(medication.isActive ? 'Mark as past' : 'Mark as current'),
          ),
        ],
      ),
    );
  }
}
