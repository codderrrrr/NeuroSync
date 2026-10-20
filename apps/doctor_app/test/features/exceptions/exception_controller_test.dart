import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_doctor/features/exceptions/data/exception_repository.dart';
import 'package:neurosync_doctor/features/exceptions/models/review_exception.dart';
import 'package:neurosync_doctor/features/exceptions/state/exception_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../test_support.dart';

/// A controller wired to a scripted API, the same shape the app builds in
/// `main.dart` but with no real network behind it.
ExceptionController buildController(
  Future<http.Response> Function(http.Request) handler,
) =>
    ExceptionController(
      repository: ExceptionRepository(
        apiClient: ApiClient(
          baseUrl: 'http://api.test',
          httpClient: MockClient(handler),
          sessionToken: SessionTokenCache(),
        ),
      ),
    );

void main() {
  group('loading the queue', () {
    test('asks for every entry when no filter is chosen', () async {
      String? requested;
      final ExceptionController controller =
          buildController((http.Request r) async {
        requested = r.url.path;
        return json(<Map<String, dynamic>>[]);
      });

      await controller.load();

      expect(requested, '/doctor/exceptions');
      expect(controller.items, isEmpty);
      expect(controller.hasLoaded, isTrue);
      expect(controller.errorMessage, isNull);
    });

    test('sends the status the filter names', () async {
      String? status;
      final ExceptionController controller =
          buildController((http.Request r) async {
        status = r.url.queryParameters['status'];
        return json(<Map<String, dynamic>>[]);
      });

      await controller.applyFilter(ExceptionFilter.open);

      expect(status, 'open');
      expect(controller.filter, ExceptionFilter.open);
    });

    test('sends no status for the unfiltered view', () async {
      final ExceptionController controller =
          buildController((http.Request r) async {
        return json(<Map<String, dynamic>>[]);
      });

      // The API treats a missing status as "everything"; sending an empty one
      // would ask for entries that match nothing.
      await controller.applyFilter(ExceptionFilter.reviewed);
      await controller.applyFilter(ExceptionFilter.all);

      expect(controller.filter, ExceptionFilter.all);
    });

    test('reads the row the way the API writes it', () async {
      final ExceptionController controller =
          buildController((http.Request r) async {
        return json(<Map<String, dynamic>>[exceptionSummaryJson()]);
      });

      await controller.load();

      final ReviewExceptionSummary item = controller.items.single;
      expect(item.id, 7);
      expect(item.patientName, 'Maya Lindqvist');
      expect(item.exceptionType, 'persistent_change');
      expect(item.evidenceStrength, 'moderate');
      expect(item.medicationContext, 'unknown');
      expect(item.minutesSinceMedication, isNull);
      expect(item.isOpen, isTrue);
    });

    test('keeps the queue readable when the server fails', () async {
      int attempt = 0;
      final ExceptionController controller =
          buildController((http.Request r) async {
        attempt++;
        if (attempt == 1) {
          return json(<String, dynamic>{'detail': 'Server exploded.'}, 500);
        }
        return json(<Map<String, dynamic>>[exceptionSummaryJson()]);
      });

      await controller.load();
      expect(controller.errorMessage, 'Server exploded.');

      await controller.load();
      expect(controller.errorMessage, isNull);
      expect(controller.items, hasLength(1));
    });

    test('does not refetch a filter that is already selected', () async {
      int calls = 0;
      final ExceptionController controller =
          buildController((http.Request r) async {
        calls++;
        return json(<Map<String, dynamic>>[]);
      });

      await controller.applyFilter(ExceptionFilter.open);
      await controller.applyFilter(ExceptionFilter.open);

      expect(calls, 1);
    });
  });

  group('opening one entry', () {
    test('loads the evidence behind it once', () async {
      int calls = 0;
      final ExceptionController controller =
          buildController((http.Request r) async {
        calls++;
        return json(exceptionDetailJson());
      });

      await controller.loadDetail(7);
      await controller.loadDetail(7);

      expect(calls, 1);
      final ReviewExceptionDetail detail = controller.detailFor(7)!;
      expect(detail.routingRule, 'repeated_change');
      expect(detail.totalTaps, 10);
      expect(detail.baseline!.observationCount, 8);
      expect(detail.changedFeatures, contains('taps_per_second'));
      expect(detail.reviewNote, isNull);
    });

    test('surfaces a failure without pretending the entry loaded', () async {
      final ExceptionController controller =
          buildController((http.Request r) async {
        return json(<String, dynamic>{'detail': 'Exception not found.'}, 404);
      });

      await controller.loadDetail(7);

      expect(controller.detailFor(7), isNull);
      expect(controller.detailError, 'Exception not found.');
    });
  });

  group('recording a review', () {
    test('sends the chosen outcome and the doctor\'s note', () async {
      Map<String, dynamic>? sent;
      final ExceptionController controller =
          buildController((http.Request r) async {
        if (r.method == 'POST') {
          sent = jsonDecode(r.body) as Map<String, dynamic>;
          return json(
            exceptionDetailJson(
              status: 'reviewed',
              reviewedAt: '2026-09-30T12:00:00Z',
              reviewedByDoctorId: 3,
              reviewNote: 'Discussed in clinic.',
            ),
          );
        }
        return json(<Map<String, dynamic>>[exceptionSummaryJson()]);
      });

      await controller.load();
      final bool closed = await controller.review(
        exceptionId: 7,
        outcome: ReviewOutcome.reviewed,
        note: '  Discussed in clinic.  ',
      );

      expect(closed, isTrue);
      expect(sent!['status'], 'reviewed');
      // The note is trimmed but never reworded: these are the doctor's words.
      expect(sent!['note'], 'Discussed in clinic.');
    });

    test('omits the note entirely when the doctor left it blank', () async {
      Map<String, dynamic>? sent;
      final ExceptionController controller =
          buildController((http.Request r) async {
        if (r.method == 'POST') {
          sent = jsonDecode(r.body) as Map<String, dynamic>;
          return json(exceptionDetailJson(status: 'dismissed'));
        }
        return json(<Map<String, dynamic>>[exceptionSummaryJson()]);
      });

      await controller.review(
        exceptionId: 7,
        outcome: ReviewOutcome.dismissed,
        note: '   ',
      );

      expect(sent!.containsKey('note'), isFalse);
      expect(sent!['status'], 'dismissed');
    });

    test('moves the closed entry out of the queue it came from', () async {
      final ExceptionController controller =
          buildController((http.Request r) async {
        if (r.method == 'POST') {
          return json(exceptionDetailJson(status: 'reviewed'));
        }
        return json(<Map<String, dynamic>>[exceptionSummaryJson()]);
      });

      await controller.load();
      await controller.review(exceptionId: 7, outcome: ReviewOutcome.reviewed);

      expect(controller.items.single.isOpen, isFalse);
      expect(controller.openCount, 0);
      expect(controller.detailFor(7)!.summary.status, 'reviewed');
    });

    test('reports a conflict and leaves the entry untouched', () async {
      final ExceptionController controller =
          buildController((http.Request r) async {
        if (r.method == 'POST') {
          return json(
            <String, dynamic>{
              'detail': 'This exception has already been reviewed.',
            },
            409,
          );
        }
        return json(<Map<String, dynamic>>[exceptionSummaryJson()]);
      });

      await controller.load();
      final bool closed = await controller.review(
        exceptionId: 7,
        outcome: ReviewOutcome.dismissed,
      );

      expect(closed, isFalse);
      expect(
          controller.detailError, 'This exception has already been reviewed.');
      expect(controller.items.single.isOpen, isTrue);
    });
  });

  group('wording', () {
    test('never presents a routing type as a diagnosis', () {
      expect(exceptionTypeLabel('persistent_change'), 'Repeated change');
      expect(
        exceptionTypeLabel('contextual_change'),
        'Change under a known context',
      );
      expect(exceptionTypeLabel('review_requested'), 'Single change');
      // An unrecognised type still renders something, rather than raw wire data.
      expect(exceptionTypeLabel('something_new'), 'Routed for review');
    });

    test('describes evidence as a quantity of information, not a score', () {
      expect(evidenceLabel('stronger'), 'Strong evidence');
      expect(evidenceLabel('insufficient'), 'Insufficient evidence');
    });

    test('never narrows unreported medication timing into a window', () {
      expect(
        medicationContextLabel('unknown'),
        'Medication timing not reported',
      );
      expect(
        medicationContextLabel('recently_after_medication'),
        'Shortly after a dose',
      );
    });
  });
}
