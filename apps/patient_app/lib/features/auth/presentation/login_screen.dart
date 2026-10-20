import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/app_text_field.dart';
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
      body: IntroTextScale(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: auth,
            builder: (BuildContext context, Widget? child) => LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Centred while the whole form fits - the action stays on
                // screen without scrolling on a short phone - and scrollable
                // the moment the keyboard or a large text scale needs room.
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const LargeTitle('NeuroSync'),
                        const SizedBox(height: 8),
                        const MutedText('Sign in to continue to your care.'),
                        const SizedBox(height: 32),
                        // One autofill context per form, so the platform
                        // password manager can offer and save credentials.
                        AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: <Widget>[
                                AppTextField(
                                  label: 'Email',
                                  controller: _emailController,
                                  hintText: 'you@example.com',
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const <String>[
                                    AutofillHints.email
                                  ],
                                  enabled: !auth.isSubmitting,
                                  validator: _validateEmail,
                                ),
                                const SizedBox(height: 16),
                                AppTextField(
                                  label: 'Password',
                                  controller: _passwordController,
                                  hintText: 'Your password',
                                  obscureText: true,
                                  keyboardType: TextInputType.visiblePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const <String>[
                                    AutofillHints.password
                                  ],
                                  enabled: !auth.isSubmitting,
                                  validator: _validatePassword,
                                  onFieldSubmitted: (_) => _submit(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (auth.errorMessage != null) ...<Widget>[
                          const SizedBox(height: 18),
                          Semantics(
                            liveRegion: true,
                            child: ErrorText(auth.errorMessage!),
                          ),
                        ],
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: 'Sign in',
                          isLoading: auth.isSubmitting,
                          onPressed: _submit,
                          tactile: true,
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Create account',
                          onPressed:
                              auth.isSubmitting ? null : widget.onShowSignUp,
                          tactile: true,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
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
