import 'package:flutter/material.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../models/doctor_link.dart';
import '../state/doctor_link_controller.dart';
import 'status_chip.dart';

/// Shows the patient's doctor links, or an explanation when there are none.
class DoctorLinkList extends StatelessWidget {
  const DoctorLinkList({super.key, required this.controller});

  final DoctorLinkController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading && !controller.hasLoaded) {
      return const AppCard(
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (controller.links.isEmpty) {
      return const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'No doctors linked yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.label,
              ),
            ),
            SizedBox(height: 6),
            MutedText('Enter the code your doctor gave you to request a link.'),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          for (int index = 0;
              index < controller.links.length;
              index++) ...<Widget>[
            if (index > 0) const Divider(height: 1, indent: 18, endIndent: 18),
            _DoctorLinkRow(link: controller.links[index]),
          ],
        ],
      ),
    );
  }
}

class _DoctorLinkRow extends StatelessWidget {
  const _DoctorLinkRow({required this.link});

  final DoctorLink link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Doctor #${link.doctorId}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Requested ${formatShortDate(link.createdAt)}',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.secondaryLabel),
                ),
              ],
            ),
          ),
          StatusChip(status: link.status),
        ],
      ),
    );
  }
}
