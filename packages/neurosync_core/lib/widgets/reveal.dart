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
///
/// The delay is part of the animation rather than a timer, so the content is
/// on screen from the first frame and there is never a moment where the
/// screen is empty because something has not been told to appear yet.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 10,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;

  /// How long after the screen opens this starts to arrive.
  final Duration delay;

  /// How far below its place it starts.
  final double offset;

  /// How long the arrival takes.
  final Duration duration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        // The arrival is the part of the animation after the delay.
        final double elapsed = _controller.value *
            (widget.delay + widget.duration).inMicroseconds /
            1000000;
        final double arrived =
            ((elapsed - widget.delay.inMicroseconds / 1000000) /
                    (widget.duration.inMicroseconds / 1000000))
                .clamp(0.0, 1.0);
        final double eased = Curves.easeOutCubic.transform(arrived);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - eased)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
