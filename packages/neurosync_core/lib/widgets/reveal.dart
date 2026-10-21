import 'package:flutter/material.dart';

/// Something that arrives rather than appearing.
///
/// A screen that swaps one block of content for another with no transition
/// makes the patient re-read everything, because they cannot tell what
/// changed. This fades the content in and lifts it a little, so the eye is
/// drawn to what is new.
///
/// The [delay] staggers a row of them, which is what stops a list from
/// arriving all at once.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 10,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;

  /// How long after the screen opens this appears.
  final Duration delay;

  /// How far below its place it starts.
  final double offset;

  final Duration duration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - curve.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
