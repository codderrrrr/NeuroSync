import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../auth/state/auth_controller.dart';

/// Patient home: profile summary and sign-out.
///
/// Doctor linking and check-ins each live on their own tab of the signed-in
/// shell, so this screen stays account-only.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _signOut() async {
    final AppScope scope = AppScope.of(context);
    scope.doctorLinks.clear();
    scope.checkIns.clear();
    await scope.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AuthController auth = scope.auth;
    final String name = auth.patient?.name ?? '';

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
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
                        children: <Widget>[
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const _SignedInPill(),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Sharing'),
                const AppCard(
                  child: MutedText(
                    'Your check-ins are shared only with doctors you link. '
                    'Find them under the Doctors tab.',
                  ),
                ),
                const SizedBox(height: 24),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
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
