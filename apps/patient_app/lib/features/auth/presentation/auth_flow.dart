import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'signup_screen.dart';

/// Moves between the login and signup screens.
class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key, this.initialShowSignUp = false});

  /// Whether to open directly on the signup form (used by the welcome screen).
  final bool initialShowSignUp;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  late bool _showSignUp = widget.initialShowSignUp;

  void _showSignIn() => setState(() => _showSignUp = false);

  void _showSignUpForm() => setState(() => _showSignUp = true);

  @override
  Widget build(BuildContext context) {
    if (_showSignUp) {
      return SignUpScreen(onShowSignIn: _showSignIn);
    }
    return LoginScreen(onShowSignUp: _showSignUpForm);
  }
}
