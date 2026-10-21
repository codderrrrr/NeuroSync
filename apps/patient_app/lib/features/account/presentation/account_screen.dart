import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/soft_panel.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/models/patient.dart';

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
    final AppColors colors = AppColors.of(context);
    final Patient? patient = auth.patient;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[auth, theme]),
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              children: <Widget>[
                const LargeTitle('Account'),
                const SizedBox(height: 4),
                const MutedText('Your details and how the app looks.'),
                const SizedBox(height: 20),
                SoftPanel(
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _initial(patient?.name ?? ''),
                          style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontSize: 19,
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
                              patient?.name ?? 'Not signed in',
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
                      StatePill(
                        label: 'SIGNED IN',
                        color: colors.active,
                        tint: colors.activeTint,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const SectionHeader('Appearance'),
                const SizedBox(height: 10),
                // The mood is the patient's to choose: some use the app in the
                // evening and in bed, where a bright page is hard.
                SoftPanel(
                  padding: const EdgeInsets.all(12),
                  child: ThemeChoice(
                    mode: theme.value,
                    onChanged: theme.set,
                  ),
                ),
                const SizedBox(height: 22),
                const SectionHeader('Sign out'),
                const SizedBox(height: 10),
                SoftPanel(
                  padding: const EdgeInsets.all(12),
                  child: SecondaryButton(
                    label: 'Log out',
                    color: colors.danger,
                    onPressed: () => _signOut(context),
                  ),
                ),
                const SizedBox(height: 16),
                const MutedText(
                  'Your check-ins are shared only with doctors you link. '
                  'Find them under the Doctors tab.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _initial(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed[0].toUpperCase();
  }
}
