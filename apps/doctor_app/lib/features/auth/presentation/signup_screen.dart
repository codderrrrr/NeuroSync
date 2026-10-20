import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/back_label.dart';
import '../state/auth_controller.dart';

/// Doctor account creation.
///
/// On success the backend generates the doctor's personal link code; the
/// dashboard highlights it once so it can be shared with patients straight
/// away.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Guard against a second tap while the first request is in flight; it
    // would otherwise create a duplicate account and error on return.
    if (_isSubmitting) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _isSubmitting = true);
    // Resolve dependencies before awaiting so no build context is used after
    // the gap.
    final AuthController auth = AppScope.of(context).auth;
    final NavigatorState navigator = Navigator.of(context);
    final bool created = await auth.signUp(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isSubmitting = false);
    if (created) {
      // The root already swapped to the dashboard (the controller is signed
      // in); this screen must leave the navigation stack so the doctor
      // actually sees it. Everything between here and the root is auth UI.
      navigator.popUntil((Route<dynamic> route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
              children: <Widget>[
                const BackLabel(),
                const SizedBox(height: 8),
                const LargeTitle('Create your account'),
                const SizedBox(height: 6),
                const MutedText(
                  'Your account comes with a personal link code. Patients '
                  'enter it to request a link with you.',
                ),
                const SizedBox(height: 28),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'Full name (e.g. Dr. Amara Osei)',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (String? value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter your name.'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'Work email',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (String? value) {
                          final String trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'Enter your email.';
                          }
                          if (!trimmed.contains('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        onFieldSubmitted: (String _) => _submit(),
                        decoration: const InputDecoration(
                          hintText: 'Password (at least 12 characters)',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (String? value) =>
                            value == null || value.length < 12
                                ? 'Use at least 12 characters.'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      if (auth.errorMessage != null) ...<Widget>[
                        ErrorText(auth.errorMessage!),
                        const SizedBox(height: 14),
                      ],
                      PrimaryButton(
                        label: 'Create account',
                        isLoading: auth.isSubmitting || _isSubmitting,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
