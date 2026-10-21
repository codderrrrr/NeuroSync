import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/widgets/empty_card.dart';
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
        child: Center(child: CalmLoader(size: 22)),
      );
    }

    if (controller.links.isEmpty) {
      return const EmptyCard(
        title: 'No doctors linked yet',
        message: 'Enter the code your doctor gave you to request a link.',
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Requested ${formatShortDate(link.createdAt)}',
                  style:
                      TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
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
