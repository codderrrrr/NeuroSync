import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../auth/state/auth_controller.dart';
import '../../patients/presentation/patient_detail_screen.dart';
import '../models/roster_models.dart';
import '../state/roster_controller.dart';
import 'profile_sheet.dart';

/// The doctor's dashboard: pending link requests and the active roster.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load once the first frame is up so notifying listeners never happens
    // during this widget's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      AppScope.of(context).roster.loadDashboard();
    });
  }

  Future<void> _openPatient(RosterPatient patient) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PatientDetailScreen(
          patientId: patient.patientId,
          patientName: patient.patientName,
        ),
      ),
    );
    if (mounted) {
      // Assignments may have changed; refresh the dashboard counts.
      AppScope.of(context).roster.loadDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final RosterController roster = AppScope.of(context).roster;
    final AuthController auth = AppScope.of(context).auth;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[roster, auth]),
          builder: (BuildContext context, Widget? child) {
            return RefreshIndicator(
              onRefresh: roster.loadDashboard,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: <Widget>[
                  _Header(doctorName: auth.doctor?.name ?? ''),
                  const SizedBox(height: 20),
                  _SummaryRow(
                    pendingCount: roster.pending.length,
                    patientCount: roster.patients.length,
                  ),
                  const SizedBox(height: 28),
                  const SectionHeader('Pending requests'),
                  _PendingSection(
                    controller: roster,
                    onOpenPatient: _openPatient,
                  ),
                  const SizedBox(height: 28),
                  const SectionHeader('Patients'),
                  _PatientsSection(
                    controller: roster,
                    onOpenPatient: _openPatient,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Greeting and the profile affordance that holds the doctor's link code.
class _Header extends StatelessWidget {
  const _Header({required this.doctorName});

  final String doctorName;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String firstName = doctorName.trim().split(' ').first;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Hi, $firstName',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your practice at a glance.',
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const _ProfileButton(),
      ],
    );
  }
}

/// The avatar-style entry point to the profile sheet (name, email and the
/// doctor's link code).
class _ProfileButton extends StatelessWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context) {
    final AuthController auth = AppScope.of(context).auth;
    final String initial = auth.doctor?.firstName.isNotEmpty == true
        ? auth.doctor!.firstName[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: InkResponse(
        onTap: () => showProfileSheet(context),
        radius: 28,
        child: CircleAvatar(
          radius: 22,
          backgroundColor: AppTheme.accentMint.withValues(alpha: 0.16),
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentMint,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.pendingCount, required this.patientCount});

  final int pendingCount;
  final int patientCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _SummaryCard(
            value: pendingCount,
            label: 'Pending requests',
            color: AppTheme.pending,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _SummaryCard(
            value: patientCount,
            label: 'Active patients',
            color: AppTheme.active,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingSection extends StatelessWidget {
  const _PendingSection({required this.controller, required this.onOpenPatient});

  final RosterController controller;
  final void Function(RosterPatient patient) onOpenPatient;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null) {
      return _ErrorCard(message: controller.errorMessage!, onRetry: controller.loadDashboard);
    }
    if (!controller.hasLoaded) {
      return const _LoadingCard();
    }
    if (controller.pending.isEmpty) {
      return const _EmptyCard(
        message: 'No pending requests. Share your link code with patients '
            'from your profile.',
      );
    }
    return Column(
      children: <Widget>[
        for (final PendingRequest request in controller.pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PendingCard(
              request: request,
              isBusy: controller.isAccepting,
              onAccept: () => controller.accept(request),
            ),
          ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.request,
    required this.isBusy,
    required this.onAccept,
  });

  final PendingRequest request;
  final bool isBusy;
  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  request.patientName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Requested ${_formatDate(request.requestedAt)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: isBusy ? null : () => onAccept(),
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            isBusy ? '…' : 'Accept',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
      ),
    );
  }
}

class _PatientsSection extends StatelessWidget {
  const _PatientsSection({required this.controller, required this.onOpenPatient});

  final RosterController controller;
  final void Function(RosterPatient patient) onOpenPatient;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null) {
      return const SizedBox.shrink();
    }
    if (!controller.hasLoaded) {
      return const _LoadingCard();
    }
    if (controller.patients.isEmpty) {
      return const _EmptyCard(
        message: 'No active patients yet. Accept a pending request to add '
            'someone to your roster.',
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          for (final RosterPatient patient in controller.patients)
            _PatientRow(
              patient: patient,
              onOpen: () => onOpenPatient(patient),
            ),
        ],
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({required this.patient, required this.onOpen});

  final RosterPatient patient;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                patient.patientName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.activeTint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.active,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatDate(patient.linkedAt),
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: MutedText(message),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ErrorText(message),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: FilledButton.tonal(
              onPressed: () => onRetry(),
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}
