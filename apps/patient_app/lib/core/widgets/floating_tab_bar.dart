import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// One destination in the [FloatingTabBar].
class TabDestination {
  const TabDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// A navigation bar that floats above the bottom of the screen.
///
/// The stock bar sits flush against the edge and fills the width. This one is
/// a rounded panel that sits clear of the edge on a soft shadow, so the content
/// behind it stays visible and the bar reads as a layer above the page rather
/// than as part of it.
///
/// Every destination keeps its label, stacked under its icon. Five icons
/// without words would be a puzzle for the person using this app, and a
/// Parkinson's patient is the last person who should have to work out what a
/// symbol means. The chosen one is marked by a filled capsule behind it and
/// by its label taking the accent colour.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<TabDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _barHeight = 64;
  static const double _horizontalMargin = 16;
  static const double _bottomMargin = 10;

  void _select(int index) {
    if (index == selectedIndex) {
      return;
    }
    HapticFeedback.selectionClick();
    onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalMargin,
        0,
        _horizontalMargin,
        _bottomMargin,
      ),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Container(
          height: _barHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colors.separator, width: 1),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF0B1017).withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double itemWidth =
                  constraints.maxWidth / destinations.length;
              return Stack(
                children: <Widget>[
                  // The capsule that marks where the patient is.
                  Positioned(
                    left: itemWidth * selectedIndex,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      for (int index = 0; index < destinations.length; index++)
                        SizedBox(
                          width: itemWidth,
                          child: _TabItem(
                            destination: destinations[index],
                            selected: index == selectedIndex,
                            onTap: () => _select(index),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final TabDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color color = selected ? colors.primary : colors.secondaryLabel;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      // The item carries its own Material, so the ink of a press is printed
      // above the capsule rather than under it. The capsule covers the
      // chosen destination, and a press on it should still leave a mark.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedScale(
                  scale: selected ? 1.1 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                // The label is always there. A short one that will not fit is
                // shortened rather than allowed to overflow its column.
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 9.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.1,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
