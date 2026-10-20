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

/// The table on wide viewports, the list on narrow ones.
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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 720) {
          return _PatientList(patients: patients, onOpen: onOpen);
        }
        return _PatientTable(
          patients: patients,
          total: total,
          onOpen: onOpen,
        );
      },
    );
  }
}

class _PatientTable extends StatelessWidget {
  const _PatientTable({
    required this.patients,
    required this.total,
    required this.onOpen,
  });

  final List<RosterPatient> patients;
  final int total;
  final void Function(RosterPatient patient) onOpen;

  static const double _nameColumn = 0.46;
  static const double _statusColumn = 0.2;
  static const double _dateColumn = 0.26;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: (_nameColumn * 100).round(),
              child: const _HeadCell('Patient'),
            ),
            Expanded(
              flex: (_statusColumn * 100).round(),
              child: const _HeadCell('Status'),
            ),
            Expanded(
              flex: (_dateColumn * 100).round(),
              child: const _HeadCell('Linked', align: TextAlign.end),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: patients.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (BuildContext context, int index) => _PatientRow(
              patient: patients[index],
              onOpen: () => onOpen(patients[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label, {this.align = TextAlign.start});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: AppColors.of(context).secondaryLabel,
        ),
      ),
    );
  }
}

/// A hoverable, focusable table row.
///
/// The whole row is the target and it says so: a hover wash, a visible focus
/// ring and a chevron that darkens. Only a hairline separates rows, so the
/// table stays flat and scannable.
class _PatientRow extends StatefulWidget {
  const _PatientRow({required this.patient, required this.onOpen});

  final RosterPatient patient;
  final VoidCallback onOpen;

  @override
  State<_PatientRow> createState() => _PatientRowState();
}

class _PatientRowState extends State<_PatientRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active = _hovered || _focused;
    final RosterPatient patient = widget.patient;

    return Semantics(
      button: true,
      label:
          '${patient.patientName}, active, linked ${formatMonthDayYear(patient.linkedAt)}',
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 58,
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary.withValues(alpha: 0.07)
                    : scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _focused ? scheme.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 46,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        patient.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 20,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusTag(
                          label: patient.status.toUpperCase(),
                          color: AppColors.of(context).active,
                          tint: AppColors.of(context).activeTint,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 26,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          // The date yields before the chevron does: the
                          // chevron is the affordance, the date is context.
                          Flexible(
                            child: Text(
                              formatMonthDayYear(patient.linkedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: active
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
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

/// The narrow-viewport roster: identity and status, nothing that needs a
/// column to be read.
class _PatientList extends StatelessWidget {
  const _PatientList({required this.patients, required this.onOpen});

  final List<RosterPatient> patients;
  final void Function(RosterPatient patient) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: patients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final RosterPatient patient = patients[index];
        return PortalNavItem(
          onTap: () => onOpen(patient),
          semanticLabel: 'Open ${patient.patientName}',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      patient.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  StatusTag(
                    label: patient.status.toUpperCase(),
                    color: AppColors.of(context).active,
                    tint: AppColors.of(context).activeTint,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Linked ${formatMonthDayYear(patient.linkedAt)}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.of(context).secondaryLabel,
                ),
              ),
            ],
          ),
        );
      },
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
