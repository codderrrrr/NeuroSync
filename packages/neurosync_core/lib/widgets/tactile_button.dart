import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A press response a hand with tremor can feel and aim at.
///
/// The control sinks while it is held and springs back on release. The
/// movement is deeper than a typical press because the feedback has to
/// survive a hand that is not steady: a 1.5% change is invisible to someone
/// with an intention tremor, 4% is not.
///
/// A brush of the finger is not a press. The haptic waits until the contact
/// has lasted 50ms, so a tremor that grazes the control does not tick. The
/// button still activates: the haptic is feedback, and swallowing a
/// deliberate press because it was short would be worse than a stray tick.
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
    this.onHaptic = HapticFeedback.lightImpact,
  });

  final bool enabled;
  final Widget child;

  /// Overridable so tests can count feedback without a device.
  final Future<void> Function() onHaptic;

  /// How far the control sinks while it is held.
  static const double pressedScale = 0.96;

  /// The spring back to the resting size.
  static const Duration duration = Duration(milliseconds: 220);

  /// How long a contact has to last before it counts as a press.
  static const Duration pressThreshold = Duration(milliseconds: 50);

  @override
  State<TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<TactileButton> {
  bool _pressed = false;
  Timer? _pressTimer;

  @override
  void dispose() {
    _pressTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) {
      return;
    }
    setState(() => _pressed = true);
    // The tick waits for the contact to settle, so a graze is not a press.
    _pressTimer?.cancel();
    _pressTimer = Timer(TactileButton.pressThreshold, () {
      if (!mounted || !_pressed) {
        return;
      }
      _tick();
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _release();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _release();
  }

  void _release() {
    _pressTimer?.cancel();
    if (!_pressed) {
      return;
    }
    setState(() => _pressed = false);
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
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedScale(
        scale: active ? TactileButton.pressedScale : 1,
        duration: TactileButton.duration,
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
