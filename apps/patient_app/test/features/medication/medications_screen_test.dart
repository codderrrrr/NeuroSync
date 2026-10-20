import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/features/medication/data/medication_repository.dart';
import 'package:neurosync_patient/features/medication/presentation/add_medication_screen.dart';
import 'package:neurosync_patient/features/medication/presentation/medications_screen.dart';
import 'package:neurosync_patient/features/medication/state/medication_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

Map<String, dynamic> medicationJson({
  int id = 1,
  String name = 'Levodopa',
  String? doseLabel = '100mg',
  String? frequencyLabel = '4 times daily',
  bool isActive = true,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'dose_label': doseLabel,
    'frequency_label': frequencyLabel,
    'is_active': isActive,
    'created_at': '2026-06-18T10:00:00Z',
    'updated_at': '2026-06-18T10:00:00Z',
  };
}

class _Harness extends StatelessWidget {
  const _Harness({required this.controller});

  final MedicationController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: MedicationsScreen(controller: controller),
    );
  }
}

({MedicationController controller, List<http.Request> requests}) build(
  Future<http.Response> Function(http.Request) handler,
) {
  final List<http.Request> requests = <http.Request>[];
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: MockClient((http.Request request) {
      requests.add(request);
      return handler(request);
    }),
    sessionToken: SessionTokenCache(),
  );
  return (
    controller: MedicationController(
      repository: MedicationRepository(apiClient: apiClient),
    ),
    requests: requests,
  );
}

Future<void> _pump(WidgetTester tester, _Harness harness) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty list explains what it is for',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response('[]', 200));

    await _pump(tester, _Harness(controller: built.controller));

    expect(find.text('Medications'), findsOneWidget);
    expect(
      find.textContaining('No medications recorded yet'),
      findsOneWidget,
    );
    expect(
        find.widgetWithText(PrimaryButton, 'Add medication'), findsOneWidget);
  });

  testWidgets('recorded medications are listed exactly as entered',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<dynamic>[
            medicationJson(),
            medicationJson(
              id: 2,
              name: 'Ropinirole',
              doseLabel: null,
              frequencyLabel: null,
            ),
          ]),
          200,
        ));

    await _pump(tester, _Harness(controller: built.controller));

    expect(find.text('Levodopa'), findsOneWidget);
    expect(find.textContaining('100mg · 4 times daily'), findsOneWidget);
    // A medication with no dose or frequency shows only its name.
    expect(find.text('Ropinirole'), findsOneWidget);
  });

  testWidgets('the screen states plainly that nothing is interpreted',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response('[]', 200));

    await _pump(tester, _Harness(controller: built.controller));

    expect(
      find.textContaining('does not check doses or suggest changes'),
      findsOneWidget,
    );
  });

  testWidgets('a medication marked as past stays on record but leaves the set',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(jsonEncode(medicationJson(isActive: false)), 200);
    });

    await _pump(tester, _Harness(controller: built.controller));
    await tester.tap(find.text('Mark as past'));
    await tester.pumpAndSettle();

    expect(find.text('NO LONGER CURRENT'), findsOneWidget);
    expect(find.text('Mark as current'), findsOneWidget);
    // Deactivating hides a row, it never deletes history.
    expect(find.text('Levodopa'), findsOneWidget);
    expect(built.controller.activeMedications, isEmpty);
  });

  testWidgets('adding a medication stores it and returns to the list',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response('[]', 200);
      }
      return http.Response(jsonEncode(medicationJson()), 201);
    });

    await _pump(tester, _Harness(controller: built.controller));
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add medication'));
    await tester.pumpAndSettle();

    expect(find.byType(AddMedicationScreen), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'Levodopa');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save medication'));
    await tester.pumpAndSettle();

    expect(find.byType(MedicationsScreen), findsOneWidget);
    expect(find.text('Levodopa'), findsOneWidget);
  });

  testWidgets('the add form says the fields are optional and verbatim',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response('[]', 200));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AddMedicationScreen(controller: built.controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dose (optional)'), findsOneWidget);
    expect(find.text('How often (optional)'), findsOneWidget);
    expect(
      find.textContaining('exactly as they are written on your prescription'),
      findsOneWidget,
    );
  });

  testWidgets('a name is required before the form submits',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async =>
        http.Response(jsonEncode(medicationJson()), 201));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AddMedicationScreen(controller: built.controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Save medication'));
    await tester.pumpAndSettle();

    expect(find.byType(AddMedicationScreen), findsOneWidget);
    expect(find.text('A medication needs a name.'), findsOneWidget);
    expect(
        built.requests.where((http.Request r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('a server error is shown rather than swallowed',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{'detail': 'A medication needs a name.'}),
          422,
        ));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AddMedicationScreen(controller: built.controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'X');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save medication'));
    await tester.pumpAndSettle();

    expect(find.byType(AddMedicationScreen), findsOneWidget);
    expect(find.text('A medication needs a name.'), findsOneWidget);
  });

  testWidgets('shows a spinner while the list is still loading',
      (WidgetTester tester) async {
    // A request that never returns yet, so the screen is observed mid-flight.
    final Completer<http.Response> pending = Completer<http.Response>();
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) => pending.future);

    // Pumped by hand rather than settled: the request deliberately never
    // finishes, and the spinner animates forever, so settling would time out.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_Harness(controller: built.controller));
    // The first frame runs the post-frame callback that starts the load.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Nothing is claimed while the answer is still outstanding.
    expect(find.text('No medications recorded yet'), findsNothing);

    pending.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('No medications recorded yet'), findsOneWidget);
  });

  testWidgets('a failed list load is shown rather than looking empty',
      (WidgetTester tester) async {
    // The distinction matters: "we could not ask" and "you have none" are
    // different facts, and only one of them is worth retrying.
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(
              <String, dynamic>{'detail': 'Could not load medications.'}),
          500,
        ));

    await _pump(tester, _Harness(controller: built.controller));

    expect(find.text('Could not load medications.'), findsOneWidget);
    expect(find.text('No medications recorded yet'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
