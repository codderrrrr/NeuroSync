import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Chapter 4 - Trust: an organic boundary drawn around "your information",
/// with a single route leading out to the care team.
///
/// The boundary is not decoration: tapping it opens the boundary on that one
/// route and lets a single token through, then the caption says exactly what
/// was shared. Sharing here is something the patient does, in one gesture,
/// rather than a claim in a paragraph.
class PrivacyBoundaryVisual extends StatefulWidget {
  const PrivacyBoundaryVisual({super.key});

  /// Direction of the route to the care team, in radians (down-right).
  static const double routeAngle = 0.62;

  @override
  State<PrivacyBoundaryVisual> createState() => _PrivacyBoundaryVisualState();
}

class _PrivacyBoundaryVisualState extends State<PrivacyBoundaryVisual>
    with TickerProviderStateMixin {
  /// Draws the boundary in, from the opening round to the far side.
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  /// Opens the route, sends one token, and settles the boundary again.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  bool _open = false;

  @override
  void dispose() {
    _entry.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _reveal.forward();
    } else {
      _reveal.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: _open
          ? 'Hide what is shared with your care team'
          : 'Show what is shared with your care team',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Column(
          children: <Widget>[
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_entry, _reveal]),
                builder: (BuildContext context, Widget? child) => CustomPaint(
                  painter: _BoundaryPainter(
                    entry: Curves.easeOutCubic.transform(_entry.value),
                    reveal: Curves.easeInOutCubic.transform(_reveal.value),
                    lineColor: scheme.onSurfaceVariant,
                    accentColor: scheme.primary,
                  ),
                  child: child,
                ),
                child: Stack(
                  children: <Widget>[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FractionallySizedBox(
                          widthFactor: 0.62,
                          child: Text(
                            'YOUR INFORMATION',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.8,
                              color: scheme.onSurface.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        'CARE TEAM',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.8,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.55 + 0.35 * _reveal.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Fixed height: the square above must not resize when the caption
            // changes length.
            SizedBox(
              height: 40,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    _open
                        ? 'Assessment result and medication timing, shared with '
                            'your care team.'
                        : 'Tap to see what is shared.',
                    key: ValueKey<bool>(_open),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: scheme.onSurfaceVariant
                          .withValues(alpha: _open ? 0.9 : 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoundaryPainter extends CustomPainter {
  const _BoundaryPainter({
    required this.entry,
    required this.reveal,
    required this.lineColor,
    required this.accentColor,
  });

  /// How much of the boundary has been drawn (0 to 1).
  final double entry;

  /// How far through the sharing gesture we are (0 to 1).
  final double reveal;

  final Color lineColor;
  final Color accentColor;

  /// The widest the opening ever gets, half-angle in radians: a narrow door,
  /// never a missing wall.
  static const double _gapHalf = 0.34;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || entry <= 0) {
      return;
    }

    final Offset center = Offset(size.width / 2, size.height / 2);
    // The boundary follows the shape of the space rather than staying a
    // circle, so it fills a tall phone screen without a letterboxed void.
    final double rx = size.width * 0.37;
    final double ry = size.height * 0.38;

    _paintBoundary(canvas, center, rx, ry);
    _paintInterior(canvas, center, rx, ry);
    _paintRoute(canvas, center, rx, ry);
  }

  /// The boundary itself, open exactly as far as the route needs.
  void _paintBoundary(Canvas canvas, Offset center, double rx, double ry) {
    final double gapHalf = _gapHalf * reveal;
    final double start = PrivacyBoundaryVisual.routeAngle + gapHalf;
    final double sweep = 2 * math.pi - 2 * gapHalf;

    final Paint paint = Paint()
      ..color = Color.lerp(
        lineColor.withValues(alpha: 0.5),
        accentColor.withValues(alpha: 0.75),
        reveal * 0.5,
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true;

    final ui.Path path = ui.Path();
    const int steps = 180;
    // Only the first `entry` of the sweep is drawn: the boundary traces
    // itself in from the opening round to the far side.
    final int drawn = (steps * entry).round();
    for (int i = 0; i <= drawn; i++) {
      final double angle = start + sweep * i / steps;
      final Offset point = _boundaryPoint(center, rx, ry, angle);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  /// Two quiet internal contours: depth without imagery.
  void _paintInterior(Canvas canvas, Offset center, double rx, double ry) {
    final Paint paint = Paint()
      ..color = lineColor.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    for (final double scale in <double>[0.72, 0.44]) {
      final ui.Path path = ui.Path();
      const int steps = 96;
      for (int i = 0; i <= steps; i++) {
        final double angle = 2 * math.pi * i / steps;
        final Offset point =
            _boundaryPoint(center, rx * scale, ry * scale, angle);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  /// The one route out: a hairline to the care team, with the token that has
  /// just left resting at the end of it.
  void _paintRoute(Canvas canvas, Offset center, double rx, double ry) {
    if (reveal <= 0) {
      return;
    }

    final Offset direction = Offset(math.cos(PrivacyBoundaryVisual.routeAngle),
        math.sin(PrivacyBoundaryVisual.routeAngle));
    final Offset target = center + Offset(direction.dx * rx, direction.dy * ry);

    // The route is drawn as the opening widens, from the centre outward.
    final double growth = ((reveal - 0.05) / 0.35).clamp(0.0, 1.0);
    if (growth > 0) {
      final Paint route = Paint()
        ..color = accentColor.withValues(alpha: 0.35 * growth)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, center + (target - center) * growth, route);
    }

    // The token leaves the centre, passes through the opening and fades just
    // beyond the boundary - where the care team's copy of it would be.
    final double travel = ((reveal - 0.25) / 0.6).clamp(0.0, 1.0);
    if (travel <= 0) {
      return;
    }
    final Offset token = center +
        (target - center) *
            (0.2 + 1.15 * Curves.easeOutCubic.transform(travel));
    final double opacity = travel > 0.8 ? (1 - (travel - 0.8) / 0.2) : 1.0;
    if (opacity <= 0) {
      return;
    }
    final Paint glow = Paint()
      ..shader = ui.Gradient.radial(
        token,
        14,
        <Color>[
          accentColor.withValues(alpha: 0.20 * opacity),
          accentColor.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(token, 14, glow);
    final Paint dot = Paint()
      ..color = accentColor.withValues(alpha: opacity)
      ..isAntiAlias = true;
    canvas.drawCircle(token, 3, dot);
  }

  /// A point on the boundary, gently irregular so it reads as drawn by hand
  /// rather than generated by a device.
  Offset _boundaryPoint(Offset center, double rx, double ry, double angle) {
    final double wobble = 1 +
        0.030 * math.sin(3 * angle + 0.8) +
        0.018 * math.cos(5 * angle - 0.4);
    return center +
        Offset(math.cos(angle) * rx * wobble, math.sin(angle) * ry * wobble);
  }

  @override
  bool shouldRepaint(_BoundaryPainter oldDelegate) =>
      oldDelegate.entry != entry ||
      oldDelegate.reveal != reveal ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor;
}
