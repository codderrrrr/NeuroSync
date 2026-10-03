import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/app/portal_shell.dart';
import 'package:neurosync_doctor/features/roster/presentation/dashboard_view.dart';
import 'package:neurosync_doctor/features/roster/presentation/patients_view.dart';

import '../test_support.dart';

Future<http.Response> _workspace(
  http.Request request, {
  List<Object> pending = const <Object>[],
  List<Object> patients = const <Object>[],
  Map<String, Object>? assignmentsByPatient,
}) async {
  switch (request.url.path) {
    case '/doctor/patient-links/pending':
      return json(pending);
    case '/doctor/patients':
      return json(patients);
    case '/doctor/patient-links/12/accept':
      return json(<String, dynamic>{
        'id': 12,
        'patient_id': 41,
        'patient_name': 'Jonas Keller',
        'status': 'active',
        'accepted_at': '2026-09-30T10:00:00Z',
      });
  }
  if (request.url.path.endsWith('/assignments')) {
    return json(assignmentsByPatient?[request.url.path] ?? <Object>[]);
  }
  throw StateError('unexpected request: ${request.method} ${request.url.path}');
}

Widget portal() => PortalShell(
      doctorName: 'Dr. Amara Osei',
      onOpenProfile: () {},
      onSignOut: () {},
    );

void main() {
  group('shell', () {
    testWidgets('shows a sidebar on a desktop viewport and starts on Overview',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: _workspace,
        viewport: const Size(1440, 900),
      );

      expect(find.text('NeuroSync'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      // The rail carries the account row; the compact bar uses a button.
      expect(find.text('Dr. Amara Osei'), findsOneWidget);
      expect(find.byTooltip('Profile'), findsNothing);
      expect(find.byType(DashboardView), findsOneWidget);
    });

    testWidgets('navigation keeps the rail while the content changes',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: _workspace,
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();

      // The rail is still there and still offers all three destinations.
      expect(find.text('Dr. Amara Osei'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.byType(PatientsView), findsOneWidget);
      expect(find.byType(DashboardView), findsNothing);
    });

    testWidgets('collapses to compact navigation on a narrow viewport',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: _workspace,
        viewport: const Size(760, 900),
      );

      // Below the breakpoint the rail is replaced by icon destinations and a
      // single account button.
      expect(find.byTooltip('Profile'), findsOneWidget);
      expect(find.text('Dr. Amara Osei'), findsNothing);
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });
  });

  group('overview', () {
    testWidgets('leads with a waiting request when there is one',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: (http.Request request) =>
            _workspace(request, pending: <Object>[pendingRequestJson()]),
        viewport: const Size(1440, 900),
      );

      expect(find.text('1 REQUEST WAITING'), findsOneWidget);
      expect(find.text('Review requests'), findsOneWidget);
    });

    testWidgets('says nothing needs attention when the queue is empty',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: _workspace,
        viewport: const Size(1440, 900),
      );

      expect(find.text('Nothing needs your attention'), findsOneWidget);
      expect(find.text('1 REQUEST WAITING'), findsNothing);
    });
  });

  group('roster', () {
    testWidgets('renders patients as a table on a wide viewport',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: (http.Request request) => _workspace(
          request,
          patients: <Object>[
            rosterPatientJson(),
            rosterPatientJson(id: 42, name: 'Ada Lovelace'),
          ],
        ),
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();

      expect(find.text('PATIENT'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('LINKED'), findsOneWidget);
      expect(find.text('Maya Lindqvist'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
    });

    testWidgets('explains an empty roster instead of showing a blank table',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: _workspace,
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();

      expect(find.text('No patients yet'), findsOneWidget);
      expect(find.text('PATIENT'), findsNothing);
    });

    testWidgets('search narrows the roster', (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: (http.Request request) => _workspace(
          request,
          patients: <Object>[
            rosterPatientJson(),
            rosterPatientJson(id: 42, name: 'Ada Lovelace'),
          ],
        ),
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'ada',
      );
      await tester.pumpAndSettle();

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Maya Lindqvist'), findsNothing);
    });

    testWidgets('surfaces a load failure with a retry',
        (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: (http.Request request) async => json(
          <String, dynamic>{'detail': 'Doctor authentication required.'},
          401,
        ),
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load your roster'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('requests', () {
    testWidgets('shows who is waiting and when', (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: (http.Request request) =>
            _workspace(request, pending: <Object>[pendingRequestJson()]),
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      expect(find.text('Jonas Keller'), findsOneWidget);
      expect(
        find.textContaining('Requested'),
        findsOneWidget,
      );
      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('accepting confirms immediately and empties the queue',
        (WidgetTester tester) async {
      bool accepted = false;
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: (http.Request request) async {
          if (request.url.path.endsWith('/accept')) {
            accepted = true;
          }
          return _workspace(
            request,
            pending: accepted ? <Object>[] : <Object>[pendingRequestJson()],
          );
        },
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(accepted, isTrue);
      expect(
        find.text('Jonas Keller is now on your roster.'),
        findsOneWidget,
      );
      expect(find.text('No open requests'), findsOneWidget);
    });

    testWidgets('explains an empty queue', (WidgetTester tester) async {
      await pumpDoctorScreen(
        tester,
        home: portal(),
        handler: _workspace,
        viewport: const Size(1440, 900),
      );

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      expect(find.text('No open requests'), findsOneWidget);
      expect(find.textContaining('link code'), findsOneWidget);
    });
  });
}
