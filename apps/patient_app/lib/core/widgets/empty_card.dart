import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// A card that says why a list is empty.
///
/// The phone layout is card-based and left-aligned, so this is the patient's
/// counterpart to the portal's centred empty state.
class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          MutedText(message),
        ],
      ),
    );
  }
}
