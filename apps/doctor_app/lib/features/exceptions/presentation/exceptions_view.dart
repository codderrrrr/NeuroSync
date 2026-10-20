import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/formatting/date_format.dart';
import '../models/review_exception.dart';
import '../state/exception_controller.dart';
import 'exception_detail_page.dart';
import 'queue_widgets.dart';

/// The specialist review queue.
///
/// A list of observations the monitoring pipeline routed, not findings and not
/// alerts. Every row says why it was routed; what a clinician makes of it is
/// their own conclusion, recorded on the detail page.
class ExceptionsView extends StatefulWidget {
  const ExceptionsView({super.key});

  @override
  State<ExceptionsView> createState() => _ExceptionsViewState();
}

class _ExceptionsViewState extends State<ExceptionsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppScope.of(context).exceptions.load();
      }
    });
  }

  Future<void> _open(ReviewExceptionSummary item) async {
    final ExceptionController controller = AppScope.of(context).exceptions;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExceptionDetailPage(
          exceptionId: item.id,
          patientName: item.patientName,
        ),
      ),
    );
    // A review closes the entry, so the queue behind it is no longer accurate.
    if (mounted) {
      await controller.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExceptionController controller = AppScope.of(context).exceptions;
    return PortalPage(
      title: 'Review queue',
      subtitle:
          'Recordings the monitoring pipeline routed for a specialist to look at.',
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? child) {
          if (controller.errorMessage != null && !controller.hasLoaded) {
            return Center(
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load the queue',
                message: controller.errorMessage!,
                action: SecondaryButton(
                  label: 'Try again',
                  onPressed: controller.load,
                ),
              ),
            );
          }
          if (!controller.hasLoaded && controller.isLoading) {
            return const TableSkeleton();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _FilterBar(
                selected: controller.filter,
                onChanged: controller.applyFilter,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: controller.items.isEmpty
                    ? EmptyState(
                        icon: _emptyIcon(controller.filter),
                        title: _emptyTitle(controller.filter),
                        message: _emptyMessage(controller.filter),
                        action: controller.filter == ExceptionFilter.all
                            ? null
                            : SecondaryButton(
                                label: 'Show all',
                                onPressed: () => controller.applyFilter(
                                  ExceptionFilter.all,
                                ),
                              ),
                      )
                    : _QueueBody(
                        items: controller.items,
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

/// Wide viewports get a table, because the useful comparison here is across
/// rows; narrow ones get the same information as a list, where a table would
/// push the patient's name behind a horizontal scroll.
class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.items, required this.onOpen});

  final List<ReviewExceptionSummary> items;
  final void Function(ReviewExceptionSummary item) onOpen;

  static const double _tableBreakpoint = 780;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _tableBreakpoint) {
          return _QueueList(items: items, onOpen: onOpen);
        }
        return _QueueTable(items: items, onOpen: onOpen);
      },
    );
  }
}

class _QueueTable extends StatelessWidget {
  const _QueueTable({required this.items, required this.onOpen});

  final List<ReviewExceptionSummary> items;
  final void Function(ReviewExceptionSummary item) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _HeadRow(),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (BuildContext context, int index) => _QueueRow(
              item: items[index],
              onOpen: () => onOpen(items[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeadRow extends StatelessWidget {
  const _HeadRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Expanded(flex: 30, child: _HeadCell('Patient')),
        Expanded(flex: 32, child: _HeadCell('Reason')),
        Expanded(flex: 22, child: _HeadCell('Evidence')),
        Expanded(flex: 18, child: _HeadCell('Status')),
      ],
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: AppTheme.darkSecondaryLabel,
        ),
      ),
    );
  }
}

/// One queue row: a hoverable, focusable target carrying the reason.
class _QueueRow extends StatefulWidget {
  const _QueueRow({required this.item, required this.onOpen});

  final ReviewExceptionSummary item;
  final VoidCallback onOpen;

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active = _hovered || _focused;
    final ReviewExceptionSummary item = widget.item;

    return Semantics(
      button: true,
      label: '${item.patientName}, ${exceptionTypeLabel(item.exceptionType)}, '
          '${item.status}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: FocusableActionDetector(
            onShowHoverHighlight: (bool value) {
              if (value != _hovered) {
                setState(() => _hovered = value);
              }
            },
            onShowFocusHighlight: (bool value) {
              if (value != _focused) {
                setState(() => _focused = value);
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
              height: 62,
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
                    flex: 30,
                    child: _Cell(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _Clipped(
                            text: item.patientName,
                            size: 15,
                            weight: FontWeight.w500,
                          ),
                          const SizedBox(height: 2),
                          _Clipped(
                            text: item.assessmentTitle,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 32,
                    child: _Cell(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _Clipped(
                            text: exceptionTypeLabel(item.exceptionType),
                            size: 14,
                          ),
                          const SizedBox(height: 2),
                          _Clipped(
                            text: formatQueueDate(item.createdAt),
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 22,
                    child: _Cell(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: EvidenceTag(item.evidenceStrength),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 18,
                    child: Row(
                      children: <Widget>[
                        StatusTagForException(item.status),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color:
                              active ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ],
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

class _Cell extends StatelessWidget {
  const _Cell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

class _Clipped extends StatelessWidget {
  const _Clipped({
    required this.text,
    required this.size,
    this.weight = FontWeight.w400,
    this.color,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// The narrow-viewport queue: who, why, and whether anyone has looked.
class _QueueList extends StatelessWidget {
  const _QueueList({required this.items, required this.onOpen});

  final List<ReviewExceptionSummary> items;
  final void Function(ReviewExceptionSummary item) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final ReviewExceptionSummary item = items[index];
        return PortalNavItem(
          onTap: () => onOpen(item),
          semanticLabel: 'Open review for ${item.patientName}',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Clipped(
                      text: item.patientName,
                      size: 15,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusTagForException(item.status),
                ],
              ),
              const SizedBox(height: 4),
              _Clipped(
                text: exceptionTypeLabel(item.exceptionType),
                size: 13,
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  EvidenceTag(item.evidenceStrength),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Clipped(
                      text: formatQueueDate(item.createdAt),
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Which slice of the queue is on screen.
///
/// Segmented rather than a dropdown: four short labels, always visible, and
/// triage is a thing a clinician does by switching between states constantly.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});

  final ExceptionFilter selected;
  final ValueChanged<ExceptionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final ExceptionFilter option in ExceptionFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PortalNavItem(
                selected: option == selected,
                onTap: () => onChanged(option),
                semanticLabel: 'Show ${option.label.toLowerCase()} exceptions',
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: option == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: option == selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData _emptyIcon(ExceptionFilter filter) {
  switch (filter) {
    case ExceptionFilter.open:
      return Icons.inbox_outlined;
    case ExceptionFilter.reviewed:
      return Icons.task_alt_outlined;
    case ExceptionFilter.dismissed:
      return Icons.archive_outlined;
    case ExceptionFilter.all:
      return Icons.inbox_outlined;
  }
}

String _emptyTitle(ExceptionFilter filter) {
  switch (filter) {
    case ExceptionFilter.open:
      return 'Nothing waiting';
    case ExceptionFilter.reviewed:
      return 'Nothing reviewed yet';
    case ExceptionFilter.dismissed:
      return 'Nothing dismissed';
    case ExceptionFilter.all:
      return 'The queue is empty';
  }
}

String _emptyMessage(ExceptionFilter filter) {
  switch (filter) {
    case ExceptionFilter.open:
      return 'You have looked at everything your patients have sent.';
    case ExceptionFilter.reviewed:
      return 'Exceptions you have reviewed will be listed here.';
    case ExceptionFilter.dismissed:
      return 'Exceptions you judged as needing no action will be listed here.';
    case ExceptionFilter.all:
      return 'Nothing has been routed for review. Recordings only arrive here '
          'when they meet a routing rule worth a specialist\'s time.';
  }
}
