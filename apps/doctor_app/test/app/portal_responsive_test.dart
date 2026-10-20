import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/app/portal_shell.dart';
import 'package:neurosync_doctor/features/patients/presentation/assignment_page.dart';
import 'package:neurosync_doctor/features/roster/presentation/patient_detail_page.dart';

import '../test_support.dart';

/// The widths the portal is expected to hold up at: two desktops, a laptop, a
/// tablet in portrait and two narrow windows.
const List<Size> _viewports = <Size>[
  Size(1440, 900),
  Size(1280, 800),
  Size(1024, 768),
  Size(834, 1112),
  Size(820, 900),
  Size(480, 900),
  Size(380, 800),
];

Future<http.Response> _full(http.Request request) async {
  switch (request.url.path) {
    case '/doctor/patient-links/pending':
      return json(<dynamic>[
        pendingRequestJson(),
        pendingRequestJson(id: 13, name: 'Rosa Delgado'),
      ]);
    case '/doctor/patients':
      return json(<dynamic>[
        rosterPatientJson(),
        rosterPatientJson(id: 42, name: 'Bartholomew Fitzgerald-Kensington'),
        rosterPatientJson(id: 43, name: 'Wei'),
      ]);
    case '/doctor/exceptions':
      return json(<dynamic>[
        exceptionSummaryJson(),
        exceptionSummaryJson(
          id: 8,
          patientId: 43,
          patientName: 'Bartholomew Fitzgerald-Kensington',
          exceptionType: 'review_requested',
        ),
      ]);
  }
  if (request.url.path == '/doctor/assessments') {
    return json(assessmentCatalogJson());
  }
  if (request.url.path.endsWith('/assignments')) {
    return json(<dynamic>[
      assignmentJson(),
      assignmentJson(id: 78, title: 'Morning tapping', durationSeconds: 120),
    ]);
  }
  throw StateError('unexpected request: ${request.method} ${request.url.path}');
}

Widget portal() => PortalShell(
      doctorName: 'Dr. Amara Osei-Whitfield',
      onOpenProfile: () {},
      onSignOut: () {},
    );

/// Runs [body] with the semantics tree switched on, so navigation can be driven
/// by the destination's accessible name at every width. The handle is disposed
/// inside the test, because the framework verifies that before tear-downs run.
Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

/// Navigates by the destination's accessible name, which the shell exposes
/// whether it is a labelled rail row or an icon-only bar button.
Future<void> _goTo(WidgetTester tester, String destination) async {
  await tester.tap(find.bySemanticsLabel(destination));
  await tester.pumpAndSettle();
}

Future<void> _pumpPortal(WidgetTester tester, Size viewport) =>
    pumpDoctorScreen(
      tester,
      home: portal(),
      handler: _full,
      viewport: viewport,
    );

void main() {
  group('every viewport holds its layout', () {
    for (final Size size in _viewports) {
      testWidgets('overview at ${size.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await _withSemantics(tester, () async {
          await _pumpPortal(tester, size);

          expect(tester.takeException(), isNull);
          expect(find.text('2 REQUESTS WAITING'), findsOneWidget);
        });
      });

      testWidgets('roster at ${size.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await _withSemantics(tester, () async {
          await _pumpPortal(tester, size);
          await _goTo(tester, 'Patients');

          expect(tester.takeException(), isNull);
          expect(find.text('Maya Lindqvist'), findsOneWidget);
          // A long name is clipped, never allowed to widen the row.
          expect(
            find.text('Bartholomew Fitzgerald-Kensington'),
            findsOneWidget,
          );
        });
      });

      testWidgets('requests at ${size.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await _withSemantics(tester, () async {
          await _pumpPortal(tester, size);
          await _goTo(tester, 'Requests');

          expect(tester.takeException(), isNull);
          expect(find.text('Jonas Keller'), findsOneWidget);
          expect(find.text('Rosa Delgado'), findsOneWidget);
        });
      });

      testWidgets('review queue at ${size.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await _withSemantics(tester, () async {
          await _pumpPortal(tester, size);
          await _goTo(tester, 'Review');

          expect(tester.takeException(), isNull);
          expect(find.text('Maya Lindqvist'), findsOneWidget);
          expect(find.text('Repeated change'), findsOneWidget);
          // A long patient name is clipped, never allowed to widen the row.
          expect(
            find.text('Bartholomew Fitzgerald-Kensington'),
            findsOneWidget,
          );
        });
      });
    }
  });

  group('the roster is a grid of panels', () {
    testWidgets('a wide viewport gives each patient their own panel', (
      WidgetTester tester,
    ) async {
      await _withSemantics(tester, () async {
        await _pumpPortal(tester, const Size(1440, 900));
        await _goTo(tester, 'Patients');

        // A panel per patient, rather than a row of columns to read across.
        expect(find.text('Maya Lindqvist'), findsOneWidget);
        expect(find.text('Wei'), findsOneWidget);
        // A long name is clipped rather than overflowing its panel.
        expect(find.text('Bartholomew Fitzgerald-Kensington'), findsOneWidget);
        // Each panel carries the same facts a column used to.
        expect(find.textContaining('Linked'), findsWidgets);
      });
    });

    testWidgets('a narrow viewport keeps one panel per patient', (
      WidgetTester tester,
    ) async {
      await _withSemantics(tester, () async {
        await _pumpPortal(tester, const Size(480, 900));
        await _goTo(tester, 'Patients');

        expect(find.text('Maya Lindqvist'), findsOneWidget);
        // The list carries the same information without columns.
        expect(find.textContaining('Linked'), findsWidgets);
      });
    });

    testWidgets('the wordmark text gives way before anything overflows', (
      WidgetTester tester,
    ) async {
      await _withSemantics(tester, () async {
        await _pumpPortal(tester, const Size(380, 800));

        expect(find.text('NeuroSync'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('detail and assignment pages', () {
    for (final Size size in <Size>[
      const Size(1440, 900),
      const Size(820, 900),
      const Size(480, 900),
    ]) {
      testWidgets('patient detail at ${size.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await pumpDoctorScreen(
          tester,
          home: const PatientDetailPage(
            patientId: 41,
            patientName: 'Bartholomew Fitzgerald-Kensington',
          ),
          handler: _full,
          viewport: size,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Finger Tapping'), findsWidgets);
        // Durations are shown in the unit a doctor sets them in.
        expect(find.text('1 min'), findsOneWidget);
        expect(find.text('2 min'), findsOneWidget);
      });

      testWidgets('assignment page at ${size.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await pumpDoctorScreen(
          tester,
          home: const AssignmentPage(patientId: 41, patientName: 'Maya'),
          handler: _full,
          viewport: size,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Assign exercise'), findsOneWidget);
        // Every catalog test is offered, so the doctor picks rather than being
        // handed the one the app decided on.
        expect(find.text('Finger Tapping'), findsWidgets);
        expect(find.text('Spiral Drawing'), findsOneWidget);
        expect(find.text('Line Tracing'), findsOneWidget);
        expect(find.text('Handwriting'), findsOneWidget);
        // The two held-back tests are labelled as unavailable, which is what
        // tells a doctor they cannot be picked yet.
        expect(find.text('COMING SOON'), findsNWidgets(2));
        // No settings editor until a test is chosen: each test declares its
        // own, so there is nothing to show before one is picked.
        expect(find.text('HOW THE PATIENT DOES IT'), findsNothing);

        await tester.tap(find.text('Line Tracing'));
        await tester.pumpAndSettle();

        // Picking one reveals that test's own settings, rendered from the
        // catalog. They sit below the fold, so the list is scrolled first.
        expect(tester.takeException(), isNull);
        // The recording length starts at this test's catalog default.
        expect(find.text('30'), findsOneWidget);
        await tester.dragUntilVisible(
          find.text('HOW THE PATIENT DOES IT'),
          find.byType(Scrollable).last,
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();

        expect(find.text('HOW THE PATIENT DOES IT'), findsOneWidget);
        expect(find.text('Speed'), findsOneWidget);
        expect(find.text('Repetitions'), findsOneWidget);
        expect(find.text('Line length'), findsOneWidget);

        // The submit row is the last thing on the page; it is below the fold
        // at every width, so the list is scrolled to the end.
        await tester.dragUntilVisible(
          find.text('Assign'),
          find.byType(Scrollable).last,
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();
        expect(find.text('Assign'), findsOneWidget);
      });
    }
  });
}
