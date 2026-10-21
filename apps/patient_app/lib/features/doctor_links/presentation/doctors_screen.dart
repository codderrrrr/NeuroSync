import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../state/doctor_link_controller.dart';
import 'add_doctor_screen.dart';
import 'doctor_link_list.dart';

/// The care-team tab: the patient's doctor links and the way to request more.
///
/// Doctor linking lives entirely on this screen, decoupled from the home and
/// check-ins tabs, so sharing information with a doctor is one dedicated place.
class DoctorsScreen extends StatefulWidget {
  const DoctorsScreen({super.key});

  @override
  State<DoctorsScreen> createState() => _DoctorsScreenState();
}

class _DoctorsScreenState extends State<DoctorsScreen> {
  @override
  void initState() {
    super.initState();
    // Load links once the first frame is up so notifying listeners never
    // happens during this widget's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      AppScope.of(context).doctorLinks.load();
    });
  }

  Future<void> _openAddDoctor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AddDoctorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DoctorLinkController links = AppScope.of(context).doctorLinks;

    return ListenableBuilder(
      listenable: links,
      builder: (BuildContext context, Widget? child) {
        // A doctor accepting a request changes this list from their side,
        // so the patient can pull to check without restarting the app.
        return RefreshIndicator(
          onRefresh: links.load,
          color: AppColors.of(context).primary,
          backgroundColor: AppColors.of(context).surface,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
            children: <Widget>[
              const LargeTitle('Care team'),
              const SizedBox(height: 6),
              const MutedText(
                'Link a doctor with the code they gave you so they can '
                'follow your check-ins.',
              ),
              const SizedBox(height: 28),
              if (links.errorMessage != null) ...<Widget>[
                ErrorText(links.errorMessage!),
                const SizedBox(height: 12),
              ],
              DoctorLinkList(controller: links),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Add your doctor',
                onPressed: _openAddDoctor,
                tactile: true,
              ),
            ],
          ),
        );
      },
    );
  }
}
