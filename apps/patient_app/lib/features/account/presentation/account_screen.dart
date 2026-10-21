import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/soft_panel.dart';
import '../../auth/models/patient.dart';
import '../../auth/state/auth_controller.dart';

/// The account screen: who is signed in, how the app looks, and the way out.
///
/// This used to sit at the bottom of the home screen, which made the home
/// screen two things at once. A patient opening the app to see how they are
/// doing had to scroll past their own name and a sign-out button to get to
/// it. It is its own destination now.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final AppScope scope = AppScope.of(context);
    scope.doctorLinks.clear();
    scope.checkIns.clear();
    scope.monitoring.clear();
    scope.medications.clear();
    await scope.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final AuthController auth = scope.auth;
    final ThemeController theme = scope.theme;
    final Patient? patient = auth.patient;

    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[auth, theme]),
        builder: (BuildContext context, Widget? child) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: <Widget>[
              // The sections arrive one after another, so the eye is led down
              // the page rather than handed everything at once.
              const Reveal(child: LargeTitle('Account')),
              Reveal(
                delay: const Duration(milliseconds: 60),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(height: 4),
                    MutedText('Your details and how the app looks.'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Reveal(
                delay: const Duration(milliseconds: 110),
                child: _ProfileCard(patient: patient),
              ),
              const SizedBox(height: 24),
              Reveal(
                delay: const Duration(milliseconds: 160),
                child: const SectionHeader('Appearance'),
              ),
              const SizedBox(height: 10),
              Reveal(
                delay: const Duration(milliseconds: 190),
                child: SoftPanel(
                  padding: const EdgeInsets.all(12),
                  // The mood is the patient's to choose: some use the app in
                  // the evening and in bed, where a bright page is hard.
                  child: ThemeChoiceBar(
                    mode: theme.value,
                    onChanged: theme.set,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Reveal(
                delay: const Duration(milliseconds: 240),
                child: const SectionHeader('Your data'),
              ),
              const SizedBox(height: 10),
              Reveal(
                delay: const Duration(milliseconds: 270),
                child: const SoftPanel(
                  child: MutedText(
                    'Your check-ins are shared only with doctors you link. '
                    'Find them under the Doctors tab.',
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // Signing out is destructive, so it is one quiet row at the
              // bottom rather than a button in its own section: it should be
              // findable and hard to hit by accident.
              Reveal(
                delay: const Duration(milliseconds: 320),
                child: _SignOutRow(onSignOut: () => _signOut(context)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Who is signed in.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.patient});

  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String name = patient?.name ?? 'Not signed in';

    return SoftPanel(
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              _initial(name),
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: colors.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  patient?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    height: 1.35,
                    color: colors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          StatePill(
            label: 'SIGNED IN',
            color: colors.active,
            tint: colors.activeTint,
          ),
        ],
      ),
    );
  }

  static String _initial(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed[0].toUpperCase();
  }
}

/// The way out, as one quiet row.
class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return SoftPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Semantics(
        button: true,
        label: 'Log out',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSignOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.logout_rounded,
                  size: 19,
                  color: colors.danger,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Log out',
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: colors.danger,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: colors.secondaryLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
