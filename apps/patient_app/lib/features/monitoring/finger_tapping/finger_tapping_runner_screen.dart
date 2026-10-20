import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../medication/presentation/medication_context_step_sheet.dart';
import '../../medication/state/medication_controller.dart';
import '../state/monitoring_controller.dart';

/// The finger-tapping runner: preparation, recording, and hand-off.
///
/// Captures raw tap offsets (milliseconds since the recording started) and
/// hands them to the controller, which submits them to the backend. The app
/// computes nothing about the taps itself; all statistics and quality are
/// derived server-side.
class FingerTappingRunnerScreen extends StatefulWidget {
  const FingerTappingRunnerScreen({
    super.key,
    required this.controller,
    required this.durationSeconds,
    required this.assessmentTitle,
    required this.instructions,
    this.medications,
  });

  final MonitoringController controller;
  final int durationSeconds;
  final String assessmentTitle;
  final String instructions;

  /// Used only for the optional medication step between recording and
  /// submitting. Omitted (in tests, or before the medication list has loaded)
  /// the step is simply skipped.
  final MedicationController? medications;

  @override
  State<FingerTappingRunnerScreen> createState() =>
      _FingerTappingRunnerScreenState();
}

class _FingerTappingRunnerScreenState extends State<FingerTappingRunnerScreen> {
  final List<int> _tapOffsetsMs = <int>[];
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tickTimer;
  bool _hasAskedAboutMedication = false;
  int? _medicationEventId;

  bool get _isRecording => _stopwatch.isRunning;

  int get _remainingSeconds {
    final int elapsedMs = _stopwatch.elapsedMilliseconds;
    final int remaining = widget.durationSeconds * 1000 - elapsedMs;
    return (remaining / 1000).ceil().clamp(0, widget.durationSeconds);
  }

  double get _progress {
    final int totalMs = widget.durationSeconds * 1000;
    return (_stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  void _startRecording() {
    _stopwatch.start();
    // A coarse ticker drives the countdown; the tap offsets themselves come
    // from the stopwatch, so their precision is independent of frame timing.
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        return;
      }
      if (_stopwatch.elapsedMilliseconds >= widget.durationSeconds * 1000) {
        _finish();
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  void _registerTap() {
    if (!_isRecording) {
      return;
    }
    setState(() => _tapOffsetsMs.add(_stopwatch.elapsedMilliseconds));
  }

  Future<void> _finish() async {
    _tickTimer?.cancel();
    _stopwatch.stop();
    // Asked once per recording. A failed submission is retried with the same
    // answer rather than asking again, so a retry cannot log a second dose.
    if (!_hasAskedAboutMedication) {
      _hasAskedAboutMedication = true;
      _medicationEventId = await _askAboutMedication();
      if (!mounted) {
        return;
      }
    }
    final bool submitted = await widget.controller.completeSession(
      _tapOffsetsMs,
      medicationEventId: _medicationEventId,
    );
    if (!mounted) {
      return;
    }
    if (submitted) {
      // Hand the completed session (with the server's result) back to the
      // screen that pushed this runner.
      Navigator.of(context).pop(widget.controller.lastCompletedSession);
    } else {
      // Completion failed: surface the error and let the patient retry.
      setState(() {});
    }
  }

  /// Offer the medication step and return the dose event to attach, if any.
  ///
  /// The recording is already captured by this point, so a patient who
  /// dismisses the sheet, has no medications recorded, or has no medication
  /// controller yet still completes their session normally — with the timing
  /// simply left unknown.
  Future<int?> _askAboutMedication() async {
    final MedicationController? medications = widget.medications;
    if (medications == null) {
      return null;
    }
    if (!medications.hasLoaded) {
      // Load quietly: a failed load must not block the recording.
      await medications.load();
      if (!mounted) {
        return null;
      }
    }
    return MedicationContextStepSheet.show(context, medications);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        // Leaving mid-recording drops the session; the result stays honest.
        if (didPop && _isRecording) {
          widget.controller.abandonSession();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _isRecording
              ? _RecordingView(
                  title: widget.assessmentTitle,
                  progress: _progress,
                  remainingSeconds: _remainingSeconds,
                  tapCount: _tapOffsetsMs.length,
                  onTap: _registerTap,
                )
              : _PreparationView(
                  title: widget.assessmentTitle,
                  instructions: widget.instructions,
                  durationSeconds: widget.durationSeconds,
                  tapCount: _tapOffsetsMs.length,
                  errorMessage: widget.controller.errorMessage,
                  isSubmitting: widget.controller.isSubmitting,
                  onStart: _startRecording,
                  onFinish: _finish,
                ),
        ),
      ),
    );
  }
}

/// Preparation: what the test is, how to perform it, and how to begin.
class _PreparationView extends StatelessWidget {
  const _PreparationView({
    required this.title,
    required this.instructions,
    required this.durationSeconds,
    required this.tapCount,
    required this.errorMessage,
    required this.isSubmitting,
    required this.onStart,
    required this.onFinish,
  });

  final String title;
  final String instructions;
  final int durationSeconds;
  final int tapCount;
  final String? errorMessage;
  final bool isSubmitting;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
      children: <Widget>[
        const BackLabel(label: 'Home'),
        const SizedBox(height: 8),
        LargeTitle(title),
        const SizedBox(height: 6),
        MutedText('This takes about $durationSeconds seconds.'),
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
              MutedText(instructions),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (errorMessage != null) ...<Widget>[
          ErrorText(errorMessage!),
          const SizedBox(height: 12),
        ],
        PrimaryButton(
          label: 'Start test',
          isLoading: isSubmitting,
          onPressed: onStart,
        ),
        // If the recording was already captured (auto-finished) but submission
        // failed, the patient can retry sending it.
        if (tapCount > 0) ...<Widget>[
          const SizedBox(height: 12),
          SecondaryButton(
            label:
                isSubmitting ? 'Sending…' : 'Send recording ($tapCount taps)',
            onPressed: isSubmitting ? null : onFinish,
          ),
        ],
      ],
    );
  }
}

/// The recording view: one large tap pad, a live counter and a countdown.
class _RecordingView extends StatelessWidget {
  const _RecordingView({
    required this.title,
    required this.progress,
    required this.remainingSeconds,
    required this.tapCount,
    required this.onTap,
  });

  final String title;
  final double progress;
  final int remainingSeconds;
  final int tapCount;
  final VoidCallback onTap;

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
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '$remainingSeconds',
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: AppColors.of(context).primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'seconds left',
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: AppColors.of(context).primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$tapCount taps',
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  onTap: onTap,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.touch_app_outlined,
                          size: 56,
                          color: AppColors.of(context).primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap here',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Keep a steady rhythm',
                          style: TextStyle(
                            fontSize: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
