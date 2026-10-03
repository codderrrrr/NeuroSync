import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../auth/state/auth_controller.dart';

/// Shows the doctor's identity and, prominently, the personal link code that
/// patients enter to request a link.
Future<void> showProfileSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext sheetContext) => const _ProfileSheet(),
  );
}

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet();

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? code = auth.doctor?.code;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.accentMint.withValues(alpha: 0.16),
                  child: Text(
                    _initial(auth),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentMint,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        auth.doctor?.name ?? '',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        auth.doctor?.email ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader('Your link code'),
            _CodeCard(code: code),
            const SizedBox(height: 8),
            const MutedText(
              'Patients enter this code in the patient app to request a link '
              'with you. It works like a classroom join code.',
            ),
            const SizedBox(height: 24),
            SecondaryButton(
              label: 'Sign out',
              color: AppTheme.danger,
              onPressed: () => _signOut(context),
            ),
          ],
        ),
      ),
    );
  }

  String _initial(AuthController auth) {
    final String name = auth.doctor?.firstName ?? '';
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  Future<void> _signOut(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    await AppScope.of(context).auth.signOut();
    navigator.pop();
  }
}

/// The code itself, large and copyable: this is the screen's reason to exist.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String? code;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: code == null
          ? const MutedText(
              'No link code has been issued for this account yet.',
            )
          : Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    code!,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentMint,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code!));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text('Link code copied.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded,
                      color: AppTheme.accentMint),
                ),
              ],
            ),
    );
  }
}
