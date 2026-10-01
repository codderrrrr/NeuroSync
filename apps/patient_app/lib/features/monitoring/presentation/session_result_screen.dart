import 'package:flutter/material.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../models/session_result.dart';

/// Shows what the backend stored about one monitoring session.
///
/// The screen describes the recording: whether it completed, how long it took,
/// how many taps it captured, and its quality. It deliberately does not
/// interpret the data - no scores, no comparisons, no clinical language.
class SessionResultScreen extends StatelessWidget {
  const SessionResultScreen({
    super.key,
    required this.assessmentTitle,
    required this.completedAt,
    required this.result,
    required this.onDone,
  });

  final String assessmentTitle;
  final DateTime? completedAt;
  final SessionResult result;
  final VoidCallback onDone;

  Color get _qualityColor {
    switch (result.quality) {
      case RecordingQuality.valid:
        return AppTheme.active;
      case RecordingQuality.borderline:
        return AppTheme.pending;
      case RecordingQuality.invalid:
      case RecordingQuality.incomplete:
        return AppTheme.danger;
    }
  }

  Color get _qualityTint {
    switch (result.quality) {
      case RecordingQuality.valid:
        return AppTheme.activeTint;
      case RecordingQuality.borderline:
        return AppTheme.pendingTint;
      case RecordingQuality.invalid:
      case RecordingQuality.incomplete:
        return AppTheme.danger.withValues(alpha: 0.12);
    }
  }

  String get _qualityExplanation {
    switch (result.quality) {
      case RecordingQuality.valid:
        return 'The recording is complete and steady enough to use.';
      case RecordingQuality.borderline:
        return 'The recording can be used, but part of it was uneven.';
      case RecordingQuality.invalid:
        return 'The recording ran too long to be compared with others.';
      case RecordingQuality.incomplete:
        return 'The recording ended before enough tapping was captured.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String durationLabel = _formatDuration(result.durationMs);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          children: <Widget>[
            const LargeTitle('Session complete'),
            const SizedBox(height: 6),
            MutedText(
              completedAt != null
                  ? '$assessmentTitle \u00b7 ${formatShortDateTime(completedAt!)}'
                  : assessmentTitle,
            ),
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _qualityTint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          result.quality.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _qualityColor,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _qualityExplanation,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Your recording'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: <Widget>[
                  _ResultRow(
                      label: 'Taps recorded', value: '${result.totalTaps}'),
                  const Divider(indent: 18, endIndent: 18),
                  _ResultRow(label: 'Duration', value: durationLabel),
                  const Divider(indent: 18, endIndent: 18),
                  _ResultRow(
                    label: 'Mean interval',
                    value: '${result.meanInterTapIntervalMs} ms',
                  ),
                  const Divider(indent: 18, endIndent: 18),
                  _ResultRow(
                    label: 'Variability',
                    value: '\u00b1${result.interTapVariabilityMs} ms',
                  ),
                  const Divider(indent: 18, endIndent: 18),
                  _ResultRow(
                    label: 'Longest pause',
                    value: '${result.longestPauseMs} ms',
                  ),
                  const Divider(indent: 18, endIndent: 18),
                  _ResultRow(
                    label: 'Tapping rate',
                    value: '${result.tapsPerSecond.toStringAsFixed(1)} /s',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const AppCard(
              child: MutedText(
                'These numbers describe your recording, not your health. '
                'Your doctor reviews results over time.',
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Done', onPressed: onDone),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int durationMs) {
    final double seconds = durationMs / 1000;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
    }
    final int minutes = seconds ~/ 60;
    final int rest = seconds.round() % 60;
    return '$minutes min ${rest.toString().padLeft(2, '0')} s';
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.darkLabel,
            ),
          ),
        ],
      ),
    );
  }
}
