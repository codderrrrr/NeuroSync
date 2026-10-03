import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/features/exceptions/presentation/exception_detail_page.dart';
import 'package:neurosync_doctor/features/exceptions/presentation/exceptions_view.dart';

import '../../test_support.dart';

Future<http.Response> _queue(
  http.Request request, {
  List<Object>? items,
  int status = 200,
}) async {
  if (request.url.path == '/doctor/exceptions') {
    return json(items ?? <Object>[], status);
  }
  if (request.url.path == '/doctor/exceptions/7') {
    return json(exceptionDetailJson());
  }
  throw StateError('unexpected request: ${request.method} ${request.url.path}');
}

void main() {
  group('the queue', () {
    testWidgets('lists a routed observation with its reason and status',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) => _queue(
          request,
          items: <Object>[exceptionSummaryJson()],
        ),
      );

      expect(find.text('Review queue'), findsOneWidget);
      expect(find.text('Maya Lindqvist'), findsOneWidget);
      expect(find.text('Repeated change'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);
      expect(find.text('MODERATE EVIDENCE'), findsOneWidget);
    });

    testWidgets('says so plainly when nothing has been routed',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) => _queue(request),
      );

      expect(find.text('The queue is empty'), findsOneWidget);
      expect(
        find.textContaining('Nothing has been routed for review'),
        findsOneWidget,
      );
    });

    testWidgets('never presents a routing type as a diagnosis',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) => _queue(
          request,
          items: <Object>[
            exceptionSummaryJson(exceptionType: 'persistent_change'),
            exceptionSummaryJson(id: 8, exceptionType: 'review_requested'),
          ],
        ),
      );

      expect(find.text('Repeated change'), findsOneWidget);
      expect(find.text('Single change'), findsOneWidget);
      // The wire values are not user-facing.
      expect(find.text('persistent_change'), findsNothing);
      expect(find.text('review_requested'), findsNothing);
    });

    testWidgets('shows the reason on the row, not just a tag',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) => _queue(
          request,
          items: <Object>[exceptionSummaryJson()],
        ),
      );

      // The queue answer is the rule's own sentence, not a summary of it.
      expect(find.textContaining('Repeated change'), findsWidgets);
    });

    testWidgets('offers a retry when the queue cannot be loaded',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) => _queue(
          request,
          status: 500,
        ),
      );

      expect(find.text('Could not load the queue'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('filters to what is still waiting',
        (WidgetTester tester) async {
      final List<String?> requested = <String?>[];
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) async {
          if (request.url.path == '/doctor/exceptions') {
            requested.add(request.url.queryParameters['status']);
            return json(<Object>[exceptionSummaryJson()]);
          }
          return json(exceptionDetailJson());
        },
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(requested, <String?>[null, 'open']);
    });

    testWidgets('opens the detail page for a chosen entry',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) => _queue(
          request,
          items: <Object>[exceptionSummaryJson()],
        ),
      );

      await tester.tap(find.text('Maya Lindqvist'));
      await tester.pumpAndSettle();

      expect(find.byType(ExceptionDetailPage), findsOneWidget);
      expect(find.text('Your review'), findsOneWidget);
    });
  });

  group('narrow viewports', () {
    testWidgets('still name the patient and the reason',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: const ExceptionsView(),
        handler: (http.Request request) => _queue(
          request,
          items: <Object>[exceptionSummaryJson()],
        ),
        viewport: const Size(420, 800),
      );

      expect(find.text('Maya Lindqvist'), findsOneWidget);
      expect(find.text('Repeated change'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);
    });
  });
}
