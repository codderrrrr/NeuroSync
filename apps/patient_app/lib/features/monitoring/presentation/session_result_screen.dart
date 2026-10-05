import 'package:flutter/material.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_texts.dart';
import '../../medication/models/medication_context.dart';
import '../models/longitudinal_summary.dart';
import '../models/session_result.dart';

/// Shows what the backend stored about one monitoring session.
///
/// The screen leads with the longitudinal state - how this recording compares
/// with the patient's own earlier recordings - and then describes the
/// recording itself: how long it took, how many taps it captured, and its
/// quality. The wording stays about the recording against the patient's own
/// range: no scores, no diagnosis, no clinical interpretation.
class SessionResultScreen extends StatelessWidget {
  const SessionResultScreen({
    super.key,
    required this.assessmentTitle,
    required this.completedAt,
    required this.result,
    required this.onDone,
    this.longitudinal,
  });

  final String assessmentTitle;
  final DateTime? completedAt;
  final SessionResult result;
  final VoidCallback onDone;

  /// Null only for a session recorded before the longitudinal layer existed.
  final LongitudinalSummary? longitudinal;

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
        return result.taps != null
            ? 'The recording ended before enough tapping was captured.'
            : 'The recording ended before the whole test was drawn.';
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
            if (longitudinal != null) ...<Widget>[
              _LongitudinalCard(summary: longitudinal!),
              const SizedBox(height: 16),
              _MedicationContextCard(summary: longitudinal!),
              const SizedBox(height: 16),
            ],
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
            // Two facts carry the session; the statistics below are supporting
            // detail rather than the headline.
            Row(
              children: <Widget>[
                Expanded(
                  child: _HeadlineStat(
                    label:
                        result.taps != null ? 'TAPS RECORDED' : 'PASSES DRAWN',
                    value: '${result.movementCount}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HeadlineStat(
                    label: 'DURATION',
                    value: durationLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader('More detail'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: <Widget>[
                  if (result.taps != null) ...<Widget>[
                    _ResultRow(
                      label: 'Mean interval',
                      value: '${result.taps!.meanInterTapIntervalMs} ms',
                    ),
                    const Divider(indent: 18, endIndent: 18),
                    _ResultRow(
                      label: 'Variability',
                      value: '\u00b1${result.taps!.interTapVariabilityMs} ms',
                    ),
                    const Divider(indent: 18, endIndent: 18),
                    _ResultRow(
                      label: 'Tapping rate',
                      value:
                          '${result.taps!.tapsPerSecond.toStringAsFixed(1)} /s',
                    ),
                  ] else ...<Widget>[
                    _ResultRow(
                      label: 'Points recorded',
                      value: '${result.canvas!.totalPoints}',
                    ),
                    const Divider(indent: 18, endIndent: 18),
                    _ResultRow(
                      label: 'Path length',
                      value: '${result.canvas!.pathLength.round()} px',
                    ),
                    const Divider(indent: 18, endIndent: 18),
                    _ResultRow(
                      label: 'Average speed',
                      value:
                          '${result.canvas!.meanSpeedPxPerSecond.round()} px/s',
                    ),
                  ],
                  const Divider(indent: 18, endIndent: 18),
                  _ResultRow(
                    label: 'Longest pause',
                    value: '${result.longestPauseMs} ms',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const AppCard(
              child: MutedText(
                'These numbers describe your recording, not your health. '
                'They are compared with your own earlier recordings, '
                'and your doctor reviews them over time.',
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

/// One primary number, large enough to read at a glance.
class _HeadlineStat extends StatelessWidget {
  const _HeadlineStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
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
        children: <Widget>[
          // The label yields before the value does: a statistic that cannot be
          // read is worse than one whose name is abbreviated.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
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

/// The longitudinal card: how this recording compares with the patient's own
/// earlier ones, and how much history that rests on.
class _LongitudinalCard extends StatelessWidget {
  const _LongitudinalCard({required this.summary});

  final LongitudinalSummary summary;

  Color get _color {
    switch (summary.state) {
      case LongitudinalState.withinBaseline:
        return AppTheme.active;
      case LongitudinalState.changed:
        return AppTheme.pending;
      case LongitudinalState.insufficientData:
      case LongitudinalState.unreliable:
        return AppTheme.accentMint;
    }
  }

  Color get _tint {
    switch (summary.state) {
      case LongitudinalState.withinBaseline:
        return AppTheme.activeTint;
      case LongitudinalState.changed:
        return AppTheme.pendingTint;
      case LongitudinalState.insufficientData:
      case LongitudinalState.unreliable:
        return AppTheme.accentMint.withValues(alpha: 0.12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? note = summary.confidenceNote;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'YOUR MONITORING RESULT',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _tint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              summary.state.shortLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _color,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // The headline is the plain-language state; the numbers live below it.
          Text(
            summary.state.label,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: AppTheme.darkLabel,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary.state.explanation,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            summary.historyContext,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              note,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The medication context card: supporting information beneath the result.
///
/// Deliberately says what was recorded and when, and nothing else. There is no
/// "your medication is wearing off" and no "your medication is not working"
/// here, because this app cannot know either of those and a patient reading
/// them would take them as clinical advice.
class _MedicationContextCard extends StatelessWidget {
  const _MedicationContextCard({required this.summary});

  final LongitudinalSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final MedicationContext contextTag = summary.medicationContext;
    final String? timing = summary.timingLabel;
    // "What this comparison rests on", in words. Not a percentage: the
    // backend describes how much was recorded, never how likely it is.
    final String evidence = summary.evidenceStrength.explanation;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'MEDICATION CONTEXT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: AppTheme.darkSecondaryLabel,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: contextTag.isKnown
                  ? AppTheme.accentMint.withValues(alpha: 0.12)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              contextTag.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: contextTag.isKnown
                    ? AppTheme.accentMint
                    : scheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            // The backend writes this sentence so the app and the server can
            // never describe the same timing differently.
            summary.medicationNote,
            style: TextStyle(
              fontSize: 15,
              color: scheme.onSurface,
              height: 1.35,
            ),
          ),
          if (timing != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              timing,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ],
          if (summary.medicationName != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              summary.medicationName!,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            evidence,
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
