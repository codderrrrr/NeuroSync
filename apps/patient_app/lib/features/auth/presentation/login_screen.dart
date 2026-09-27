import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_texts.dart';
import '../state/auth_controller.dart';

/// Email and password sign-in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onShowSignUp});

  final VoidCallback onShowSignUp;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    // Resolve dependencies before awaiting so no context is used afterwards.
    final AuthController auth = AppScope.of(context).auth;
    FocusScope.of(context).unfocus();
    await auth.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (BuildContext context, Widget? child) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const LargeTitle('NeuroSync'),
                  const SizedBox(height: 8),
                  const MutedText('Sign in to continue to your care.'),
                  const SizedBox(height: 32),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: <Widget>[
                        AppTextField(
                          label: 'Email',
                          controller: _emailController,
                          hintText: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const <String>[AutofillHints.email],
                          enabled: !auth.isSubmitting,
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          label: 'Password',
                          controller: _passwordController,
                          hintText: 'Your password',
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const <String>[AutofillHints.password],
                          enabled: !auth.isSubmitting,
                          validator: _validatePassword,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],
                    ),
                  ),
                  if (auth.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 18),
                    ErrorText(auth.errorMessage!),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Sign in',
                    isLoading: auth.isSubmitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label: 'Create account',
                    onPressed: auth.isSubmitting ? null : widget.onShowSignUp,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  final String email = (value ?? '').trim();
  if (email.isEmpty) {
    return 'Enter your email address';
  }
  if (!email.contains('@') || !email.contains('.')) {
    return 'Enter a valid email address';
  }
  return null;
}

String? _validatePassword(String? value) {
  if ((value ?? '').isEmpty) {
    return 'Enter your password';
  }
  return null;
}
