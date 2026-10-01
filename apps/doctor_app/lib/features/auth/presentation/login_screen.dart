import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_texts.dart';
import '../state/auth_controller.dart';
import 'signup_screen.dart';

/// Doctor sign-in. A doctor without an account creates one first; the
/// generated link code is shown right after signup.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // A second tap while the first request is in flight would just duplicate
    // the login call; ignore it.
    if (_isSubmitting) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _isSubmitting = true);
    await AppScope.of(context)
        .auth
        .signIn(email: _email.text.trim(), password: _password.text);
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (BuildContext context, Widget? child) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'NeuroSync',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const LargeTitle('Doctor portal'),
                        const SizedBox(height: 6),
                        const MutedText(
                          'Sign in with your clinical account to manage your '
                          'patient roster.',
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (String? value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter your email.'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          autofillHints: const <String>[AutofillHints.password],
                          onFieldSubmitted: (String _) => _submit(),
                          decoration: const InputDecoration(
                            hintText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (String? value) =>
                              value == null || value.isEmpty
                                  ? 'Enter your password.'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        if (auth.errorMessage != null) ...<Widget>[
                          ErrorText(auth.errorMessage!),
                          const SizedBox(height: 14),
                        ],
                        PrimaryButton(
                          label: 'Sign in',
                          isLoading: auth.isSubmitting || _isSubmitting,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 14),
                        SecondaryButton(
                          label: 'Create a doctor account',
                          onPressed: () => _openSignUp(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSignUp() async {
    AppScope.of(context).auth.clearError();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SignupScreen()),
    );
  }
}
