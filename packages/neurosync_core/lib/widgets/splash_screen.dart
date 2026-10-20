import 'package:flutter/material.dart';

/// The screen shown while a stored session is being checked.
///
/// A spinner and the wordmark, and nothing else: the user cannot act until
/// the session is resolved, so this is the one screen in the app that must not
/// pretend to be interactive.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.title = 'NeuroSync'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
