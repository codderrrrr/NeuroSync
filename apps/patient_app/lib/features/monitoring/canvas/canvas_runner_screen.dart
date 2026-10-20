import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../models/canvas_event.dart';
import '../models/monitoring_plan.dart';
import '../models/monitoring_session.dart';
import '../state/monitoring_controller.dart';
import 'canvas_ink.dart';
import 'canvas_target.dart';

/// The runner for the tracing tests: spiral drawing, line tracing and
/// handwriting.
///
/// Captures the raw point stream - each sample's offset in milliseconds and
/// where it landed - and hands it to the controller, which submits it to the
/// backend. The app derives nothing itself: features and quality are the
/// server's, computed from the same stream it stored.
///
/// No medication step here. Dose timing is supporting context for a
/// longitudinal comparison, and there is no comparison for a tracing test yet,
/// so there is nothing for it to support.
class CanvasRunnerScreen extends StatefulWidget {
  const CanvasRunnerScreen({
    super.key,
    required this.controller,
    required this.item,
    required this.onCompleted,
  });

  final MonitoringController controller;
  final MonitoringPlanItem item;

  /// Called with the completed session the backend returned.
  final ValueChanged<MonitoringSession> onCompleted;

  @override
  State<CanvasRunnerScreen> createState() => _CanvasRunnerScreenState();
}

class _CanvasRunnerScreenState extends State<CanvasRunnerScreen> {
  final Stopwatch _stopwatch = Stopwatch();
  final List<CanvasEvent> _events = <CanvasEvent>[];

  /// The same points as [_events], grouped by stroke, in the shape the canvas
  /// paints. Kept alongside rather than derived from the event list on every
  /// frame, so drawing stays cheap while the finger is moving.
  final List<List<Offset>> _strokes = <List<Offset>>[];
  int _pointCount = 0;

  Timer? _tickTimer;
  bool _isSubmitting = false;
  bool _hasFinished = false;

  int get _durationSeconds => widget.item.effectiveDurationSeconds;

  bool get _isRecording => _stopwatch.isRunning;

  int get _remainingSeconds {
    final int remaining =
        _durationSeconds * 1000 - _stopwatch.elapsedMilliseconds;
    return (remaining / 1000).ceil().clamp(0, _durationSeconds);
  }

  double get _progress {
    final int totalMs = _durationSeconds * 1000;
    return (_stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  /// How many separate passes have been finished, as the patient can see them.
  int get _completedStrokes {
    int count = 0;
    for (final CanvasEvent event in _events) {
      if (event.type == CanvasEventType.strokeEnd) {
        count++;
      }
    }
    return count;
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _events.clear();
      _strokes.clear();
      _pointCount = 0;
      _hasFinished = false;
    });
    _stopwatch
      ..reset()
      ..start();
    // A coarse ticker drives the countdown; the sampled points come from the
    // stopwatch, so their timing does not depend on frame scheduling.
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        return;
      }
      if (_stopwatch.elapsedMilliseconds >= _durationSeconds * 1000) {
        _finish();
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  void _onStrokeStart(DragStartDetails details) {
    if (!_isRecording) {
      return;
    }
    setState(() {
      _events.add(CanvasEvent.strokeStart(
        _stopwatch.elapsedMilliseconds,
        details.localPosition.dx,
        details.localPosition.dy,
      ));
      _strokes.add(<Offset>[
        Offset(details.localPosition.dx, details.localPosition.dy),
      ]);
      _pointCount++;
    });
  }

  void _onStrokeUpdate(DragUpdateDetails details) {
    if (!_isRecording || _strokes.isEmpty) {
      return;
    }
    setState(() {
      _events.add(CanvasEvent.strokePoint(
        _stopwatch.elapsedMilliseconds,
        details.localPosition.dx,
        details.localPosition.dy,
      ));
      _strokes.last
          .add(Offset(details.localPosition.dx, details.localPosition.dy));
      _pointCount++;
    });
  }

  void _onStrokeEnd(DragEndDetails details) {
    if (!_isRecording || _strokes.isEmpty) {
      return;
    }
    setState(() {
      _events.add(CanvasEvent.strokeEnd(
        _stopwatch.elapsedMilliseconds,
        details.localPosition.dx,
        details.localPosition.dy,
      ));
      _strokes.last
          .add(Offset(details.localPosition.dx, details.localPosition.dy));
      _pointCount++;
    });
  }

  Future<void> _finish() async {
    if (_hasFinished) {
      return;
    }
    _hasFinished = true;
    _tickTimer?.cancel();
    _stopwatch.stop();
    if (_events.isEmpty) {
      setState(() {});
      return;
    }
    setState(() => _isSubmitting = true);
    final bool submitted = await widget.controller.completeSession(
      const <int>[],
      canvasEvents: _events,
    );
    if (!mounted) {
      return;
    }
    if (submitted) {
      widget.onCompleted(widget.controller.lastCompletedSession!);
      return;
    }
    // Submission failed: surface it and let the patient retry the same capture
    // rather than lose the recording.
    setState(() => _isSubmitting = false);
  }

  Future<void> _abandon() async {
    if (!await _confirmAbandon() || !mounted) {
      return;
    }
    widget.controller.abandonSession();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmAbandon() async {
    if (_events.isEmpty) {
      return true;
    }
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.of(context).background,
        title: const Text('Leave without sending?'),
        content: const Text(
          'This recording has not been sent yet, so it will be lost.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Leave',
                style: TextStyle(color: AppColors.of(context).danger)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final MonitoringPlanItem item = widget.item;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _abandon();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _isRecording || _events.isNotEmpty
              ? _RecordingView(
                  title: item.assessment.title,
                  progress: _progress,
                  remainingSeconds: _remainingSeconds,
                  completedStrokes: _completedStrokes,
                  expectedStrokes: item.repetitions,
                  strokes: _strokes,
                  pointCount: _pointCount,
                  target: CanvasTarget.forAssessment(
                    assessment: item.assessment,
                    item: item,
                  ),
                  isSubmitting: _isSubmitting,
                  onStrokeStart: _onStrokeStart,
                  onStrokeUpdate: _onStrokeUpdate,
                  onStrokeEnd: _onStrokeEnd,
                  onFinishNow: _finish,
                )
              : _PreparationView(
                  item: item,
                  errorMessage: widget.controller.errorMessage,
                  isSubmitting: _isSubmitting,
                  onStart: _startRecording,
                  onFinish: _finish,
                  onCancel: () => Navigator.of(context).pop(),
                ),
        ),
      ),
    );
  }
}

/// Preparation: how their doctor set the test up, and how to begin.
class _PreparationView extends StatelessWidget {
  const _PreparationView({
    required this.item,
    required this.errorMessage,
    required this.isSubmitting,
    required this.onStart,
    required this.onFinish,
    required this.onCancel,
  });

  final MonitoringPlanItem item;
  final String? errorMessage;
  final bool isSubmitting;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final List<({String label, String value})> settings = item.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
      children: <Widget>[
        TextButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          label: const Text('Home'),
        ),
        const SizedBox(height: 8),
        LargeTitle(item.assessment.title),
        const SizedBox(height: 6),
        MutedText(
          'This takes about ${item.effectiveDurationSeconds} seconds.',
        ),
        const SizedBox(height: 24),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Before you start',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              MutedText(item.assessment.instructions),
            ],
          ),
        ),
        // What the doctor actually configured, in their own words, so the test
        // is not a surprise halfway through.
        if (settings.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'YOUR DOCTOR SET THIS TEST UP AS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: AppColors.of(context).secondaryLabel,
                  ),
                ),
                const SizedBox(height: 12),
                for (final ({String label, String value}) setting in settings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 96,
                          child: Text(
                            setting.label,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.of(context).secondaryLabel,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            setting.value,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.of(context).label,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (errorMessage != null) ...<Widget>[
          ErrorText(errorMessage!),
          const SizedBox(height: 12),
        ],
        PrimaryButton(
          label: 'Start test',
          isLoading: isSubmitting,
          onPressed: onStart,
          tactile: true,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: isSubmitting ? 'Sending…' : 'Send recording now',
          onPressed: isSubmitting ? null : onFinish,
        ),
      ],
    );
  }
}

/// The recording view: the shape to trace, the patient's own marks, how many
/// passes are done, and a countdown.
class _RecordingView extends StatelessWidget {
  const _RecordingView({
    required this.title,
    required this.progress,
    required this.remainingSeconds,
    required this.completedStrokes,
    required this.expectedStrokes,
    required this.strokes,
    required this.pointCount,
    required this.target,
    required this.isSubmitting,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    required this.onStrokeEnd,
    required this.onFinishNow,
  });

  final String title;
  final double progress;
  final int remainingSeconds;
  final int completedStrokes;
  final int expectedStrokes;

  /// The patient's own points, in the shape the ink painter draws.
  final List<List<Offset>> strokes;
  final int pointCount;

  final CanvasTarget target;
  final bool isSubmitting;
  final void Function(DragStartDetails) onStrokeStart;
  final void Function(DragUpdateDetails) onStrokeUpdate;
  final void Function(DragEndDetails) onStrokeEnd;

  /// Sends whatever has been drawn so far, without waiting for the timer.
  ///
  /// A patient who has finished the shape should not have to sit out the rest
  /// of the recording window to send it.
  final VoidCallback onFinishNow;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // The ring fills as the recording goes on. A counting number
              // would make the last seconds arrive as pressure, and the
              // patient would watch the clock instead of the shape.
              CalmProgressRing(
                progress: progress,
                caption: remainingSeconds > 0
                    ? 'About $remainingSeconds seconds left'
                    : 'Finishing',
              ),
              const SizedBox(height: 12),
              _PassTracker(
                completed: completedStrokes,
                expected: expectedStrokes,
                // A tracing test asks for a line, not an abstract "pass", and
                // the patient should be told which of the two they are doing.
                noun: target.shape == CanvasTargetShape.line ? 'Line' : 'Pass',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: onStrokeStart,
                  onPanUpdate: onStrokeUpdate,
                  onPanEnd: onStrokeEnd,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          // The guide sits underneath, so the patient can
                          // always see where they were asked to go.
                          CustomPaint(
                            painter: CanvasTargetPainter(
                              target: target,
                              strokeColor: scheme.primary,
                              guideColor: scheme.onSurfaceVariant,
                            ),
                          ),
                          // Their own marks on top: what they have drawn, and
                          // therefore what the recording will contain.
                          CustomPaint(
                            painter: CanvasInkPainter(
                              strokes: strokes,
                              completedStrokes: completedStrokes,
                              pointCount: pointCount,
                              inkColor: AppColors.of(context).primary,
                              activeInkColor: AppColors.of(context)
                                  .primary
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: isSubmitting
                  ? 'Sending…'
                  : completedStrokes >= expectedStrokes
                      ? 'All done — finish and send'
                      : 'Finish and send now',
              onPressed: isSubmitting ? null : onFinishNow,
            ),
          ),
        ),
      ],
    );
  }
}

/// One pill per requested pass, filled as the patient completes them.
///
/// A single "2 of 3" sentence is easy to miss mid-movement; the pills are what
/// makes "how much is left" readable at a glance without reading numbers.
class _PassTracker extends StatelessWidget {
  const _PassTracker({
    required this.completed,
    required this.expected,
    required this.noun,
  });

  final int completed;
  final int expected;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int total = expected < 1 ? 1 : expected;
    final int done = completed.clamp(0, total);
    final bool isFinished = completed >= total;

    return Column(
      children: <Widget>[
        Text(
          isFinished
              ? 'All $total done — send when you are ready'
              : '$noun ${done + 1} of $total',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isFinished
                ? AppColors.of(context).active
                : scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int index = 0; index < total; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: index < done ? 22 : 14,
                  height: 6,
                  decoration: BoxDecoration(
                    color: index < done
                        ? AppColors.of(context).primary
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
