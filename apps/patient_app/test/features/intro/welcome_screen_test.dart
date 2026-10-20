import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/intro/welcome_screen.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrapWelcome(
    {required VoidCallback onCreateAccount, required VoidCallback onSignIn}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: WelcomeScreen(onCreateAccount: onCreateAccount, onSignIn: onSignIn),
  );
}

void main() {
  testWidgets('welcome presents both authentication actions',
      (WidgetTester tester) async {
    int create = 0;
    int signIn = 0;
    await tester.pumpWidget(
      wrapWelcome(onCreateAccount: () => create++, onSignIn: () => signIn++),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to NeuroSync.'), findsOneWidget);
    expect(find.text('Your care journey, connected.'), findsOneWidget);
    expect(find.text('Your information is protected.'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(create, 1);
    expect(signIn, 0);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(signIn, 1);
  });
}
