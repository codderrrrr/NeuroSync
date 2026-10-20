import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// A row in the rail, the compact bar or the account slot.
///
/// Handles hover, focus and press explicitly. A web interface is used with a
/// mouse and a keyboard, so the visible states are not optional polish: without
/// a focus ring there is no way to know where Tab currently is.
class PortalNavItem extends StatefulWidget {
  const PortalNavItem({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final Widget child;
  final VoidCallback onTap;

  /// Announced by screen readers in place of the icon and label.
  final String semanticLabel;

  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  State<PortalNavItem> createState() => _PortalNavItemState();
}

class _PortalNavItemState extends State<PortalNavItem> {
  bool _hovered = false;
  bool _focused = false;

  bool get _active => _hovered || _focused;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      // One announcement per control: without this a screen reader reads the
      // icon and the label as separate nodes around the button.
      container: true,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: FocusableActionDetector(
            enabled: true,
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
                  widget.onTap();
                  return null;
                },
              ),
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: _active
                    ? scheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                // The focus ring is drawn inside the row so it never changes
                // the layout and never gets clipped by the rail.
                border: Border.all(
                  color: _focused ? scheme.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.selected)
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 9),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  Flexible(child: widget.child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The content frame every portal view sits in.
///
/// A max width keeps line lengths and table columns readable on a wide monitor
/// instead of letting them stretch to the edge of the display.
class PortalPage extends StatelessWidget {
  const PortalPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.maxWidth = 1180,
  });

  /// The page's primary heading.
  final String title;

  /// One line of context under the title, when the screen needs one.
  final String? subtitle;

  final Widget child;

  /// Contextual actions that belong to this page only.
  final List<Widget> actions;

  final double maxWidth;

  static const double gutter = 28;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                gutter,
                26,
                gutter,
                0,
              ),
              child: _PageHeader(
                title: title,
                subtitle: subtitle,
                actions: actions,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(gutter, 22, gutter, 28),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.15,
            color: scheme.onSurface,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
        ],
      ],
    );

    if (actions.isEmpty) {
      return heading;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The action sits beside the heading when both fit, and drops below it
        // when they do not, rather than being squeezed or clipped.
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              heading,
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: 16),
            ...actions,
          ],
        );
      },
    );
  }
}

/// Placeholder rows shown while a table loads.
///
/// Contextual rather than a full-page spinner: the page keeps its header and
/// shape, so nothing jumps when the data lands.
class TableSkeleton extends StatelessWidget {
  const TableSkeleton({super.key, this.rows = 5, this.height = 52});

  final int rows;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < rows; i++)
          Container(
            height: height,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
      ],
    );
  }
}
