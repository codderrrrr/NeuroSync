import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A quiet press response for the dark experience: the control sinks slightly
/// while it is held and reports a selection tick.
///
/// The scale is applied to the control layer only, never to content. Motion is
/// dropped when the system asks for reduced animation; the haptic is left to
/// the platform, which ignores it when the patient has turned touch feedback
/// off.
class TactileButton extends StatefulWidget {
  const TactileButton({
    super.key,
    required this.enabled,
    required this.child,
    this.onHaptic = HapticFeedback.selectionClick,
  });

  final bool enabled;
  final Widget child;

  /// Overridable so tests can count feedback without a device.
  final Future<void> Function() onHaptic;

  static const double _pressedScale = 0.985;
  static const Duration _duration = Duration(milliseconds: 110);

  @override
  State<TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<TactileButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
    // A control that cannot be used does not answer when it is touched.
    if (value && widget.enabled) {
      _tick();
    }
  }

  void _tick() {
    // The platform already drops haptics when the patient has turned touch
    // feedback off, so this only has to survive a missing implementation
    // (desktop, tests).
    unawaited(widget.onHaptic().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool active = widget.enabled && _pressed && !reduceMotion;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (PointerDownEvent _) => _setPressed(true),
      onPointerUp: (PointerUpEvent _) => _setPressed(false),
      onPointerCancel: (PointerCancelEvent _) => _setPressed(false),
      child: AnimatedScale(
        scale: active ? TactileButton._pressedScale : 1,
        duration: TactileButton._duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
