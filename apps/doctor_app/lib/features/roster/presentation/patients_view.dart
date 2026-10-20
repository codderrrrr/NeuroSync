import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/formatting/date_format.dart';
import '../models/roster_models.dart';
import '../state/roster_controller.dart';
import 'patient_detail_page.dart';

/// The doctor's active roster.
///
/// Wide viewports get a real table, because the useful comparison here is
/// across rows. Narrow ones get the same information as a list, because a table
/// that scrolls sideways hides the patient name behind the scroll.
class PatientsView extends StatefulWidget {
  const PatientsView({super.key});

  @override
  State<PatientsView> createState() => _PatientsViewState();
}

class _PatientsViewState extends State<PatientsView> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppScope.of(context).roster.loadDashboard();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Matches on the patient name, case-insensitively.
  List<RosterPatient> _visible(RosterController roster) {
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) {
      return roster.patients;
    }
    return roster.patients
        .where(
            (RosterPatient p) => p.patientName.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  Future<void> _open(RosterPatient patient) async {
    final RosterController roster = AppScope.of(context).roster;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PatientDetailPage(
          patientId: patient.patientId,
          patientName: patient.patientName,
        ),
      ),
    );
    // The roster is stale as soon as the doctor changes anything on the page.
    if (mounted) {
      await roster.loadDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final RosterController roster = AppScope.of(context).roster;
    return PortalPage(
      title: 'Patients',
      subtitle: 'People who have linked with you.',
      child: ListenableBuilder(
        listenable: roster,
        builder: (BuildContext context, Widget? child) {
          if (roster.errorMessage != null) {
            return _RosterError(
              message: roster.errorMessage!,
              onRetry: roster.loadDashboard,
            );
          }
          if (!roster.hasLoaded) {
            return const TableSkeleton();
          }

          final List<RosterPatient> visible = _visible(roster);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SearchField(
                controller: _search,
                onChanged: (String value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: _query.isEmpty
                            ? Icons.people_outline
                            : Icons.search_off_outlined,
                        title:
                            _query.isEmpty ? 'No patients yet' : 'No matches',
                        message: _query.isEmpty
                            ? 'Patients appear here once you accept their link request.'
                            : 'No patient on your roster is named "$_query".',
                        action: _query.isEmpty
                            ? null
                            : SecondaryButton(
                                label: 'Clear search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      )
                    : _RosterBody(
                        patients: visible,
                        total: roster.patients.length,
                        onOpen: _open,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The roster as a grid of soft panels, one per patient.
///
/// A table asks a clinician to read across a row of columns and hold the
/// columns in their head. A grid of panels lets them take in one patient at a
/// time, which is how a clinician actually works: one person, then the next.
class _RosterBody extends StatelessWidget {
  const _RosterBody({
    required this.patients,
    required this.total,
    required this.onOpen,
  });

  final List<RosterPatient> patients;
  final int total;
  final void Function(RosterPatient patient) onOpen;

  @override
  Widget build(BuildContext context) {
    if (patients.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.people_outline,
          title: 'No patients yet',
          message: 'Patients appear here once they accept a link request.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        BentoGrid(
          columns: 2,
          cells: <Widget>[
            for (final RosterPatient patient in patients)
              _PatientCard(patient: patient, onOpen: () => onOpen(patient)),
          ],
        ),
      ],
    );
  }
}

/// One patient, as a panel.
///
/// What is on it is what the portal actually knows: who they are, when they
/// linked, and how many exercises they have been given. It does not claim to
/// know how they are doing, because the portal cannot see that.
class _PatientCard extends StatefulWidget {
  const _PatientCard({required this.patient, required this.onOpen});

  final RosterPatient patient;
  final VoidCallback onOpen;

  @override
  State<_PatientCard> createState() => _PatientCardState();
}

class _PatientCardState extends State<_PatientCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppColors colors = AppColors.of(context);
    final bool active = _hovered || _focused;
    final RosterPatient patient = widget.patient;

    return Semantics(
      button: true,
      label:
          '${patient.patientName}, ${patient.status}, linked ${formatMonthDayYear(patient.linkedAt)}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: FocusableActionDetector(
            onShowHoverHighlight: (bool v) {
              if (v != _hovered) {
                setState(() => _hovered = v);
              }
            },
            onShowFocusHighlight: (bool v) {
              if (v != _focused) {
                setState(() => _focused = v);
              }
            },
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onOpen();
                  return null;
                },
              ),
            },
            child: BentoCell(
              onTap: widget.onOpen,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          patient.patientName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusTag(
                        label: patient.status.toUpperCase(),
                        color: colors.active,
                        tint: colors.activeTint,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.link,
                        size: 16,
                        color: colors.secondaryLabel,
                      ),
                      const SizedBox(width: 6),
                      // The date yields before the chevron does: the chevron
                      // is the affordance, the date is context.
                      Expanded(
                        child: Text(
                          'Linked ${formatMonthDayYear(patient.linkedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.secondaryLabel,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: active ? colors.primary : colors.secondaryLabel,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Search patients by name',
          prefixIcon: Icon(
            Icons.search,
            size: 19,
            color: AppColors.of(context).secondaryLabel,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: AppColors.of(context).separator),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _RosterError extends StatelessWidget {
  const _RosterError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your roster',
        message: message,
        action: SecondaryButton(label: 'Try again', onPressed: onRetry),
      ),
    );
  }
}
