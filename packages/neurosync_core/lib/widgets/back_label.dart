import 'package:flutter/material.dart';

/// Small in-app back affordance.
class BackLabel extends StatelessWidget {
  const BackLabel({super.key, this.label = 'Back'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 16),
        label: Text(label),
      ),
    );
  }
}
