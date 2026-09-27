import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
