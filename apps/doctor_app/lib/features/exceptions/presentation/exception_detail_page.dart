import 'package:flutter/material.dart';

import '../../../app/portal_widgets.dart';
import '../../../app_scope.dart';
import '../../../core/formatting/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_texts.dart';
import '../models/review_exception.dart';
import '../state/exception_controller.dart';
import 'queue_widgets.dart';

/// One routed observation, with the evidence behind it and the reviewer's
/// decision recorded against it.
///
/// The page shows what was recorded next to the patient's own reference, because
/// the routing rule only ever compared those two. It deliberately offers no
/// score, no trend and no recommendation: what the recording means is the
/// clinician's judgement, and the only words this app stores are theirs.
class ExceptionDetailPage extends StatefulWidget {
  const ExceptionDetailPage({
    super.key,
    required this.exceptionId,
    required this.patientName,
  });

  final int exceptionId;
  final String patientName;

  @override
  State<ExceptionDetailPage> createState() => _ExceptionDetailPageState();
}

class _ExceptionDetailPageState extends State<ExceptionDetailPage> {
  final TextEditingController _note = TextEditingController();
  ReviewOutcome? _pendingOutcome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppScope.of(context).exceptions.loadDetail(widget.exceptionId);
      }
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(ReviewOutcome outcome) async {
    final ExceptionController controller = AppScope.of(context).exceptions;
    final bool closed = await controller.review(
      exceptionId: widget.exceptionId,
      outcome: outcome,
      note: _note.text,
    );
    if (!mounted || !closed) {
      return;
    }
    setState(() => _pendingOutcome = null);
    // The note field belongs to this decision; leaving the text behind would
    // make the next one look pre-filled with someone else's words.
    _note.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recorded as ${outcome.wire}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ExceptionController controller = AppScope.of(context).exceptions;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: PortalPage(
          title: 'Review',
          subtitle: 'For ${widget.patientName}.',
          maxWidth: 860,
          child: ListenableBuilder(
            listenable: controller,
            builder: (BuildContext context, Widget? child) {
              final ReviewExceptionDetail? detail =
                  controller.detailFor(widget.exceptionId);
              if (detail == null) {
                if (controller.detailError != null) {
                  return Center(
                    child: EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load this exception',
                      message: controller.detailError!,
                      action: SecondaryButton(
                        label: 'Try again',
                        onPressed: () =>
                            controller.loadDetail(widget.exceptionId),
                      ),
                    ),
                  );
                }
                return const TableSkeleton(rows: 4, height: 84);
              }
              return _Body(
                detail: detail,
                note: _note,
                // A refused review has to be visible where the decision was
                // taken, or the button simply appears to do nothing.
                errorMessage: controller.detailError,
                isSubmitting: controller.isReviewing,
                pendingOutcome: _pendingOutcome,
                onChoose: (ReviewOutcome outcome) =>
                    setState(() => _pendingOutcome = outcome),
                onCancel: () => setState(() => _pendingOutcome = null),
                onSubmit: _submit,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.detail,
    required this.note,
    required this.errorMessage,
    required this.isSubmitting,
    required this.pendingOutcome,
    required this.onChoose,
    required this.onCancel,
    required this.onSubmit,
  });

  final ReviewExceptionDetail detail;
  final TextEditingController note;
  final String? errorMessage;
  final bool isSubmitting;
  final ReviewOutcome? pendingOutcome;
  final ValueChanged<ReviewOutcome> onChoose;
  final VoidCallback onCancel;
  final Future<void> Function(ReviewOutcome) onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        _RoutingCard(detail: detail),
        const SizedBox(height: 20),
        _EvidenceCard(detail: detail),
        const SizedBox(height: 20),
        if (detail.isOpen)
          _DecisionCard(
            note: note,
            errorMessage: errorMessage,
            isSubmitting: isSubmitting,
            pendingOutcome: pendingOutcome,
            onChoose: onChoose,
            onCancel: onCancel,
            onSubmit: onSubmit,
          )
        else
          _ClosedCard(detail: detail),
        const SizedBox(height: 28),
      ],
    );
  }
}

/// Why this is in the queue, in the routing rule's own words.
class _RoutingCard extends StatelessWidget {
  const _RoutingCard({required this.detail});

  final ReviewExceptionDetail detail;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      children: <Widget>[
        Text(
          exceptionTypeLabel(detail.summary.exceptionType),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          detail.summary.rationale,
          style: const TextStyle(
            fontSize: 15,
            height: 1.45,
            color: AppTheme.darkSecondaryLabel,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            StatusTagForException(detail.summary.status),
            StatusTag(
              label:
                  evidenceLabel(detail.summary.evidenceStrength).toUpperCase(),
              color: AppTheme.darkSecondaryLabel,
              tint: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.07),
            ),
            StatusTag(
              label: '${detail.supportingObservations} SUPPORTING OBSERVATION'
                  '${detail.supportingObservations == 1 ? '' : 'S'}',
              color: AppTheme.darkSecondaryLabel,
              tint: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.07),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FactLine(
          label: 'Recorded',
          value: formatQueueDate(detail.summary.createdAt),
        ),
        _FactLine(
          label: 'Assessment',
          value: detail.summary.assessmentTitle,
        ),
        _FactLine(
          label: 'Medication timing',
          value: medicationContextLabel(detail.summary.medicationContext),
        ),
      ],
    );
  }
}

/// The recording beside the patient's own reference.
///
/// Only the two, in the same order, because the routing rule only ever compared
/// those two; anything else on screen would be invented context.
class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.detail});

  final ReviewExceptionDetail detail;

  @override
  Widget build(BuildContext context) {
    final ExceptionBaseline? baseline = detail.baseline;
    return _Panel(
      children: <Widget>[
        Text(
          'Recording against this patient\'s usual range',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          baseline == null
              ? 'No baseline was established yet, so this recording was compared '
                  'against nothing.'
              : 'Built from ${baseline.observationCount} of this patient\'s own '
                  'recordings, at ${baseline.confidence} confidence.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppTheme.darkSecondaryLabel,
          ),
        ),
        const SizedBox(height: 16),
        _MeasurementRow(
          label: 'Tap rate',
          observed: '${detail.tapsPerSecond.toStringAsFixed(2)} per second',
          reference: baseline == null
              ? null
              : '${baseline.tapsPerSecond.toStringAsFixed(2)} per second',
          changed: detail.changedFeatures.contains('taps_per_second'),
        ),
        _MeasurementRow(
          label: 'Average gap between taps',
          observed: '${detail.meanInterTapIntervalMs} ms',
          reference:
              baseline == null ? null : '${baseline.meanInterTapIntervalMs} ms',
          changed:
              detail.changedFeatures.contains('mean_inter_tap_interval_ms'),
        ),
        _MeasurementRow(
          label: 'Variability between taps',
          observed: '${detail.interTapVariabilityMs} ms',
          reference:
              baseline == null ? null : '${baseline.interTapVariabilityMs} ms',
          changed: detail.changedFeatures.contains('inter_tap_variability_ms'),
        ),
        _MeasurementRow(
          label: 'Longest pause',
          observed: '${detail.longestPauseMs} ms',
          reference: baseline == null ? null : '${baseline.longestPauseMs} ms',
          changed: detail.changedFeatures.contains('longest_pause_ms'),
        ),
        const SizedBox(height: 14),
        _FactLine(
          label: 'Recording quality',
          value: detail.recordingQuality,
        ),
        _FactLine(
          label: 'Taps',
          value:
              '${detail.totalTaps} over ${(detail.durationMs / 1000).round()}s',
        ),
        _FactLine(
          label: 'Usable history',
          value: '${detail.usableHistoryCount} earlier recordings',
        ),
      ],
    );
  }
}

/// The doctor's decision, once it exists.
///
/// Shown rather than editable: the backend refuses a second review, so this page
/// must not offer to overwrite what was recorded.
class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.detail});

  final ReviewExceptionDetail detail;

  @override
  Widget build(BuildContext context) {
    final DateTime? at = detail.reviewedAt;
    return _Panel(
      children: <Widget>[
        Text(
          detail.summary.status == 'reviewed'
              ? 'Reviewed'
              : 'Dismissed as needing no action',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          at == null ? 'Recorded by you.' : formatQueueDate(at),
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.darkSecondaryLabel,
          ),
        ),
        if (detail.reviewNote != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              detail.reviewNote!,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Close this exception.
///
/// One note field and two outcomes, with the outcome confirmed before it is
/// sent: a review cannot be undone from this page, so the button that commits
/// it is not the button that picks it.
class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.note,
    required this.errorMessage,
    required this.isSubmitting,
    required this.pendingOutcome,
    required this.onChoose,
    required this.onCancel,
    required this.onSubmit,
  });

  final TextEditingController note;
  final String? errorMessage;
  final bool isSubmitting;
  final ReviewOutcome? pendingOutcome;
  final ValueChanged<ReviewOutcome> onChoose;
  final VoidCallback onCancel;
  final Future<void> Function(ReviewOutcome) onSubmit;

  @override
  Widget build(BuildContext context) {
    final ReviewOutcome? chosen = pendingOutcome;
    return _Panel(
      children: <Widget>[
        Text(
          'Your review',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Recorded against this exception in your own words. Nothing here is '
          'interpreted for you.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppTheme.darkSecondaryLabel,
          ),
        ),
        if (errorMessage != null) ...<Widget>[
          const SizedBox(height: 14),
          ErrorText(errorMessage!),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: note,
          maxLines: 3,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Optional note',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        if (chosen == null)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              PrimaryButton(
                label: 'Mark reviewed',
                onPressed: isSubmitting
                    ? null
                    : () => onChoose(ReviewOutcome.reviewed),
              ),
              SecondaryButton(
                label: 'Dismiss',
                onPressed: isSubmitting
                    ? null
                    : () => onChoose(ReviewOutcome.dismissed),
              ),
            ],
          )
        else
          _ConfirmRow(
            outcome: chosen,
            isSubmitting: isSubmitting,
            onCancel: onCancel,
            onConfirm: () => onSubmit(chosen),
          ),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    required this.outcome,
    required this.isSubmitting,
    required this.onCancel,
    required this.onConfirm,
  });

  final ReviewOutcome outcome;
  final bool isSubmitting;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final String verb =
        outcome == ReviewOutcome.reviewed ? 'mark as reviewed' : 'dismiss';
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        PrimaryButton(
          label: 'Confirm: $verb',
          isLoading: isSubmitting,
          onPressed: isSubmitting ? null : onConfirm,
        ),
        SecondaryButton(
          label: 'Cancel',
          onPressed: isSubmitting ? null : onCancel,
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.darkSecondaryLabel,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One measured value beside the reference it was compared against.
///
/// A changed feature is marked with the accent, and with the word "outside
/// range", so the signal never depends on colour alone.
class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.label,
    required this.observed,
    required this.reference,
    required this.changed,
  });

  final String label;
  final String observed;
  final String? reference;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              observed,
              style: TextStyle(
                fontSize: 14,
                fontWeight: changed ? FontWeight.w600 : FontWeight.w400,
                color: changed ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              reference ?? '—',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 116,
            child: Text(
              changed ? 'Outside range' : '',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: changed ? FontWeight.w600 : FontWeight.w400,
                color: changed ? scheme.primary : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
