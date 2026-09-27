import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../auth/state/auth_controller.dart';
import '../../doctor_links/presentation/add_doctor_screen.dart';
import '../../doctor_links/presentation/doctor_link_list.dart';
import '../../doctor_links/state/doctor_link_controller.dart';

/// Patient home: profile summary, doctor links and sign-out.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  Future<void> _signOut() async {
    final AppScope scope = AppScope.of(context);
    scope.doctorLinks.clear();
    await scope.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AuthController auth = scope.auth;
    final DoctorLinkController links = scope.doctorLinks;
    final String name = auth.patient?.name ?? '';

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[auth, links]),
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              children: <Widget>[
                LargeTitle('Hi, ${auth.patient?.firstName ?? 'there'}'),
                const SizedBox(height: 6),
                const MutedText('You are signed in to NeuroSync.'),
                const SizedBox(height: 28),
                const SectionHeader('Account'),
                AppCard(
                  child: Column(
                    children: <Widget>[
                      _DetailRow(label: 'Name', value: name),
                      const Divider(height: 26),
                      _DetailRow(
                          label: 'Email', value: auth.patient?.email ?? ''),
                      const Divider(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const <Widget>[
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.secondaryLabel,
                            ),
                          ),
                          _SignedInPill(),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Care team'),
                if (links.errorMessage != null) ...<Widget>[
                  ErrorText(links.errorMessage!),
                  const SizedBox(height: 12),
                ],
                DoctorLinkList(controller: links),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Add your doctor',
                  onPressed: _openAddDoctor,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Log out',
                  color: AppTheme.danger,
                  onPressed: _signOut,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 72,
          child: Text(
            label,
            style:
                const TextStyle(fontSize: 15, color: AppTheme.secondaryLabel),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.label,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignedInPill extends StatelessWidget {
  const _SignedInPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.activeTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'SIGNED IN',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.active,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
