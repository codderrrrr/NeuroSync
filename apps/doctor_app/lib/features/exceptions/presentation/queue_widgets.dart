import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../models/review_exception.dart';

/// Presentation that both queue pages share.
///
/// It lives here rather than in either page so the list can navigate to the
/// detail and the detail can render a queue row without importing the list
/// back: an import cycle between two screens is a design smell, not a
/// convenience.

/// The queue's status marker.
///
/// Open is the only state that needs attention colour; a closed one is quiet,
/// because a finished item should stop pulling the eye down the page.
class StatusTagForException extends StatelessWidget {
  const StatusTagForException(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final bool isOpen = status == 'open';
    return StatusTag(
      label: status.toUpperCase(),
      color:
          isOpen ? AppColors.of(context).pending : AppColors.of(context).active,
      tint: isOpen
          ? AppColors.of(context).pendingTint
          : AppColors.of(context).activeTint,
    );
  }
}

/// How much was recorded behind a routing decision.
///
/// Quiet on purpose: a level is context for the reason beside it, not a warning,
/// so it never competes with the status marker for attention. The word is always
/// spelled out, so the level never depends on colour alone.
class EvidenceTag extends StatelessWidget {
  const EvidenceTag(this.strength, {super.key});

  final String strength;

  @override
  Widget build(BuildContext context) {
    return StatusTag(
      label: evidenceLabel(strength).toUpperCase(),
      color: AppColors.of(context).secondaryLabel,
      tint: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
    );
  }
}
