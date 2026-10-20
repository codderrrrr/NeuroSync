import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../features/exceptions/presentation/exceptions_view.dart';
import '../features/roster/presentation/dashboard_view.dart';
import '../features/roster/presentation/patients_view.dart';
import '../features/roster/presentation/requests_view.dart';
import 'portal_widgets.dart';

/// The doctor portal's destinations, in the order they appear in navigation.
enum PortalSection {
  overview('Overview', Icons.dashboard_outlined, Icons.dashboard),
  exceptions('Review', Icons.fact_check_outlined, Icons.fact_check),
  patients('Patients', Icons.people_outline, Icons.people),
  requests('Requests', Icons.inbox_outlined, Icons.inbox);

  const PortalSection(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Where the sidebar gives way to a compact bar.
///
/// Below this the portal is being used in a narrow window or on a phone, so a
/// fixed sidebar would take more room than the content it labels.
const double kRailBreakpoint = 900;

/// The portal shell: persistent navigation beside the content.
///
/// The rail and the top bar are the same widget in two sizes, so the current
/// destination never moves as content changes and switching sections cannot
/// reflow the page around it.
class PortalShell extends StatefulWidget {
  const PortalShell({
    super.key,
    required this.doctorName,
    required this.onOpenProfile,
    required this.onSignOut,
  });

  final String doctorName;
  final VoidCallback onOpenProfile;
  final VoidCallback onSignOut;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  PortalSection _section = PortalSection.overview;

  void _select(PortalSection section) {
    if (section == _section) {
      return;
    }
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= kRailBreakpoint;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (wide)
                  _Sidebar(
                    section: _section,
                    doctorName: widget.doctorName,
                    onSelect: _select,
                    onOpenProfile: widget.onOpenProfile,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!wide)
                        _CompactBar(
                          section: _section,
                          doctorName: widget.doctorName,
                          onSelect: _select,
                          onOpenProfile: widget.onOpenProfile,
                        ),
                      Expanded(
                        child: KeyedSubtree(
                          // Remounting per section is what lets each view load
                          // its own data once, instead of every section
                          // fetching behind the one you are looking at.
                          key: ValueKey<PortalSection>(_section),
                          child: switch (_section) {
                            PortalSection.overview => DashboardView(
                                onOpenPatients: () =>
                                    _select(PortalSection.patients),
                                onOpenRequests: () =>
                                    _select(PortalSection.requests),
                              ),
                            PortalSection.exceptions => const ExceptionsView(),
                            PortalSection.patients => const PatientsView(),
                            PortalSection.requests => const RequestsView(),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fixed sidebar: identity, the destinations that exist, and the account.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.doctorName,
    required this.onSelect,
    required this.onOpenProfile,
  });

  final PortalSection section;
  final String doctorName;
  final ValueChanged<PortalSection> onSelect;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(right: BorderSide(color: AppTheme.darkSeparator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: _Wordmark(),
          ),
          for (final PortalSection item in PortalSection.values)
            _SidebarItem(
              section: item,
              selected: item == section,
              onTap: () => onSelect(item),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _AccountButton(
              doctorName: doctorName,
              onTap: onOpenProfile,
            ),
          ),
        ],
      ),
    );
  }
}

/// The narrow-viewport equivalent of the sidebar.
class _CompactBar extends StatelessWidget {
  const _CompactBar({
    required this.section,
    required this.doctorName,
    required this.onSelect,
    required this.onOpenProfile,
  });

  final PortalSection section;
  final String doctorName;
  final ValueChanged<PortalSection> onSelect;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Below this the destinations and the account button are what matter;
        // the wordmark is the first thing that can give up its text.
        final bool showWordmarkText = constraints.maxWidth >= 420;
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.darkSurface,
            border: Border(bottom: BorderSide(color: AppTheme.darkSeparator)),
          ),
          child: Row(
            children: <Widget>[
              // Flexible as well as the threshold: the wordmark gives up width
              // before the destinations or the account button are pushed out,
              // whatever the label happens to measure.
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      showWordmarkText ? 16 : 10, 10, 6, 10),
                  child: _Wordmark(showText: showWordmarkText),
                ),
              ),
              const Spacer(),
              for (final PortalSection item in PortalSection.values)
                _CompactItem(
                  section: item,
                  selected: item == section,
                  onTap: () => onSelect(item),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 4),
                child: IconButton(
                  tooltip: 'Profile',
                  onPressed: onOpenProfile,
                  icon: const Icon(Icons.account_circle_outlined),
                  color: AppTheme.darkSecondaryLabel,
                  iconSize: 21,
                  padding: const EdgeInsets.all(10),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.showText = true});

  final bool showText;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _Mark(),
        if (showText) ...<Widget>[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'NeuroSync',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The product mark: the same movement trace the patient app draws, reduced to
/// three strokes so it holds at 20px in a rail.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _MarkPainter(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final double w = size.width;
    final double h = size.height;
    // A sharp rise, a short plateau, a longer fall: the movement signature.
    final Path path = Path()
      ..moveTo(w * 0.08, h * 0.78)
      ..lineTo(w * 0.36, h * 0.16)
      ..lineTo(w * 0.56, h * 0.52)
      ..lineTo(w * 0.72, h * 0.52)
      ..lineTo(w * 0.92, h * 0.9);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.color != color;
}

/// A destination row. Selection is carried by an accent bar and the label, not
/// by a filled pill, so the rail reads as a list rather than a stack of chips.
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final PortalSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PortalNavItem(
      selected: selected,
      onTap: onTap,
      semanticLabel: section.label,
      child: Row(
        children: <Widget>[
          Icon(
            selected ? section.selectedIcon : section.icon,
            size: 20,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : AppTheme.darkSecondaryLabel,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              section.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : AppTheme.darkSecondaryLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactItem extends StatelessWidget {
  const _CompactItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final PortalSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PortalNavItem(
      selected: selected,
      onTap: onTap,
      semanticLabel: section.label,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Icon(
        selected ? section.selectedIcon : section.icon,
        size: 20,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : AppTheme.darkSecondaryLabel,
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.doctorName, required this.onTap});

  final String doctorName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PortalNavItem(
      onTap: onTap,
      semanticLabel: 'Open profile',
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.accentMint.withValues(alpha: 0.16),
            child: Text(
              _initial,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentMint,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  doctorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.darkSecondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _initial {
    final String name = doctorName.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }
}
