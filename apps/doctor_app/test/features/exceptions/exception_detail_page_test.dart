import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/features/exceptions/presentation/exception_detail_page.dart';

import '../../test_support.dart';

Widget page() =>
    const ExceptionDetailPage(exceptionId: 7, patientName: 'Maya Lindqvist');

/// Answers the detail read and, once the doctor commits, the review write.
Future<http.Response> _reviewFlow(
  http.Request request, {
  Map<String, dynamic>? detail,
  Map<String, dynamic>? reviewed,
  List<Map<String, dynamic>>? sent,
  int reviewStatus = 200,
}) async {
  if (request.url.path == '/doctor/exceptions/7') {
    return json(detail ?? exceptionDetailJson());
  }
  if (request.url.path == '/doctor/exceptions/7/review') {
    sent?.add(jsonDecode(request.body) as Map<String, dynamic>);
    return json(reviewed ?? exceptionDetailJson(), reviewStatus);
  }
  throw StateError('unexpected request: ${request.method} ${request.url.path}');
}

/// Scrolls [label] into view before tapping it.
///
/// The decision panel sits below the evidence, so on a laptop viewport it
/// starts off-screen; tapping a widget nobody can see is not a test of it.
Future<void> tapButton(WidgetTester tester, String label) async {
  final Finder target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Picks an outcome and confirms it, so a review is actually committed.
Future<void> commit(WidgetTester tester, String outcome) async {
  await tapButton(tester, outcome == 'reviewed' ? 'Mark reviewed' : 'Dismiss');
  await tapButton(
    tester,
    outcome == 'reviewed' ? 'Confirm: mark as reviewed' : 'Confirm: dismiss',
  );
}

void main() {
  group('the evidence', () {
    testWidgets('puts the recording beside the patient\'s own reference',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(request),
      );

      expect(find.textContaining('Recorded against'), findsOneWidget);
      expect(find.text('0.37 per second'), findsOneWidget);
      expect(find.text('0.70 per second'), findsOneWidget);
      expect(find.textContaining("Built from 8 of this patient's"),
          findsOneWidget);
    });

    testWidgets('names the features that fell outside the range',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(request),
      );

      // The fixture changes tap rate and average gap, but not variability.
      expect(find.text('Outside range'), findsNWidgets(2));
    });

    testWidgets('says when there was no baseline to compare against',
        (WidgetTester tester) async {
      final Map<String, dynamic> detail = exceptionDetailJson();
      detail['baseline'] = null;
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(
          request,
          detail: detail,
        ),
      );

      expect(
        find.textContaining('No baseline was established'),
        findsOneWidget,
      );
    });

    testWidgets('offers no score, trend or risk figure',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(request),
      );

      expect(find.textContaining('risk'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('progression'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('offers a retry when the evidence cannot be loaded',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) async =>
            json(<String, dynamic>{'detail': 'Exception not found.'}, 404),
      );

      expect(find.text('Could not load this exception'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('recording a decision', () {
    testWidgets('asks before committing, because a review cannot be undone',
        (WidgetTester tester) async {
      final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(
          request,
          sent: sent,
          reviewed: exceptionDetailJson(
            status: 'reviewed',
            reviewedAt: '2026-09-30T12:00:00Z',
            reviewedByDoctorId: 3,
          ),
        ),
      );

      await tapButton(tester, 'Mark reviewed');

      // Choosing an outcome is not yet a decision.
      expect(sent, isEmpty);
      expect(find.text('Confirm: mark as reviewed'), findsOneWidget);

      await tapButton(tester, 'Confirm: mark as reviewed');

      expect(sent, hasLength(1));
      expect(sent.single['status'], 'reviewed');
    });

    testWidgets('sends the doctor\'s own words with the decision',
        (WidgetTester tester) async {
      final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(
          request,
          sent: sent,
          reviewed: exceptionDetailJson(
            status: 'reviewed',
            reviewNote: 'Discussed in clinic.',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Discussed in clinic.');
      await commit(tester, 'reviewed');

      expect(sent.single['note'], 'Discussed in clinic.');
    });

    testWidgets('records a dismissal as its own outcome',
        (WidgetTester tester) async {
      final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(
          request,
          sent: sent,
          reviewed: exceptionDetailJson(status: 'dismissed'),
        ),
      );

      await commit(tester, 'dismissed');

      expect(sent.single['status'], 'dismissed');
    });

    testWidgets('a conflict leaves the decision on screen to resolve',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(
          request,
          reviewStatus: 409,
          reviewed: <String, dynamic>{
            'detail': 'This exception has already been reviewed.',
          },
        ),
      );

      await commit(tester, 'reviewed');

      expect(
        find.text('This exception has already been reviewed.'),
        findsOneWidget,
      );
      // The decision was not recorded, so the app has not pretended it was:
      // the outcome is still unchosen and the confirm step is still there.
      expect(find.text('Confirm: mark as reviewed'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Mark reviewed'), findsNothing);
    });
  });

  group('an entry that is already closed', () {
    testWidgets('shows the recorded decision and stops offering one',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(
          request,
          detail: exceptionDetailJson(
            status: 'reviewed',
            reviewedAt: '2026-09-30T12:00:00Z',
            reviewedByDoctorId: 3,
            reviewNote: 'Discussed in clinic.',
          ),
        ),
      );

      expect(find.text('Reviewed'), findsOneWidget);
      expect(find.text('Discussed in clinic.'), findsOneWidget);
      expect(find.text('Mark reviewed'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
    });

    testWidgets('distinguishes a dismissal from a review',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: page(),
        handler: (http.Request request) => _reviewFlow(
          request,
          detail: exceptionDetailJson(status: 'dismissed'),
        ),
      );

      expect(find.text('Dismissed as needing no action'), findsOneWidget);
    });
  });
}
