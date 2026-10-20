import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../models/doctor_link.dart';

/// Capsule that shows the link state with a matching tint.
///
/// PENDING and ACTIVE are deliberately visually distinct.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final DoctorLinkStatus status;

  @override
  Widget build(BuildContext context) {
    final bool isActive = status == DoctorLinkStatus.active;
    final Color color = isActive ? AppTheme.active : AppTheme.pending;
    final Color tint = isActive ? AppTheme.activeTint : AppTheme.pendingTint;

    return StatusTag(label: status.label, color: color, tint: tint);
  }
}
