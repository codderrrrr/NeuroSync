import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// iOS-style large title used at the top of a screen.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.15,
      ),
    );
  }
}

/// Small uppercase section header, as used in grouped iOS lists.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Muted supporting text.
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.35,
      ),
    );
  }
}

/// Inline destructive message used for API and validation errors.
class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.error_outline, size: 18, color: AppTheme.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
                fontSize: 15, color: AppTheme.danger, height: 1.3),
          ),
        ),
      ],
    );
  }
}
