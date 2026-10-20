import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/app_text_field.dart';
import '../state/auth_controller.dart';

/// Minimum password length, mirroring the API policy.
const int minimumPasswordLength = 12;

/// Account creation. Only name, email and password are collected.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.onShowSignIn});

  final VoidCallback onShowSignIn;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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
    await auth.signUp(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: auth.isSubmitting ? null : widget.onShowSignIn,
          tooltip: 'Back to sign in',
        ),
      ),
      body: IntroTextScale(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: auth,
            builder: (BuildContext context, Widget? child) => LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Four fields and two controls cannot all stay above a
                // keyboard, so this scrolls by design - but it stays centred
                // while it fits, and the focused field is always scrolled into
                // view rather than hidden behind the keyboard.
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const LargeTitle('Create account'),
                        const SizedBox(height: 8),
                        const MutedText(
                            'We only ask for what is needed to sign you in.'),
                        const SizedBox(height: 28),
                        // One autofill context per form, so the platform
                        // password manager can offer and save credentials.
                        AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: <Widget>[
                                AppTextField(
                                  label: 'Name',
                                  controller: _nameController,
                                  hintText: 'Your full name',
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  autofillHints: const <String>[
                                    AutofillHints.name
                                  ],
                                  enabled: !auth.isSubmitting,
                                  validator: _validateName,
                                ),
                                const SizedBox(height: 16),
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
                                  hintText:
                                      'At least $minimumPasswordLength characters',
                                  obscureText: true,
                                  keyboardType: TextInputType.visiblePassword,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const <String>[
                                    AutofillHints.newPassword
                                  ],
                                  enabled: !auth.isSubmitting,
                                  validator: _validatePassword,
                                ),
                                const SizedBox(height: 16),
                                AppTextField(
                                  label: 'Confirm password',
                                  controller: _confirmController,
                                  hintText: 'Repeat your password',
                                  obscureText: true,
                                  keyboardType: TextInputType.visiblePassword,
                                  textInputAction: TextInputAction.done,
                                  enabled: !auth.isSubmitting,
                                  validator: _validateConfirmation,
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
                          label: 'Create account',
                          isLoading: auth.isSubmitting,
                          onPressed: _submit,
                          tactile: true,
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'I already have an account',
                          onPressed:
                              auth.isSubmitting ? null : widget.onShowSignIn,
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

  String? _validateName(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'Enter your name';
    }
    return null;
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
    final String password = value ?? '';
    if (password.isEmpty) {
      return 'Choose a password';
    }
    if (password.length < minimumPasswordLength) {
      return 'Use at least $minimumPasswordLength characters';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if ((value ?? '').isEmpty) {
      return 'Repeat your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }
}
