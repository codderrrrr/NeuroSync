import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/features/medication/data/medication_repository.dart';
import 'package:neurosync_patient/features/medication/presentation/medication_context_step_sheet.dart';
import 'package:neurosync_patient/features/medication/state/medication_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

Map<String, dynamic> medicationJson({
  int id = 1,
  String name = 'Levodopa',
  String? doseLabel = '100mg',
  bool isActive = true,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'dose_label': doseLabel,
    'frequency_label': '4 times daily',
    'is_active': isActive,
    'created_at': '2026-06-18T10:00:00Z',
    'updated_at': '2026-06-18T10:00:00Z',
  };
}

/// Hosts the sheet in a real modal route and captures what it pops.
class _Harness extends StatelessWidget {
  const _Harness({required this.controller, required this.onResult});

  final MedicationController controller;

  /// Receives whatever the sheet pops, so a test can assert on the answer the
  /// caller will actually receive rather than only on what was rendered.
  final void Function(int?) onResult;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                onResult(
                  await MedicationContextStepSheet.show(context, controller),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
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

/// Pumps the harness and opens the sheet.
///
/// The default test surface is 800x600, tall enough that the sheet's save
/// button falls below the fold, so the surface is sized to the sheet rather
/// than every test scrolling to reach it.
Future<void> _openSheet(WidgetTester tester, _Harness harness) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness);
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the step opens optional and never demands an answer',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response('[]', 200));
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    expect(find.text('Medication check'), findsOneWidget);
    expect(find.textContaining('Optional'), findsOneWidget);
    expect(find.text('Continue without'), findsOneWidget);
    // Nothing to select and nothing to save: the step is a genuine no-op.
    final PrimaryButton save = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, 'Save and continue'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('a patient with no medications is told they can carry on',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response('[]', 200));
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    expect(
      find.textContaining('You have not added any medication yet'),
      findsOneWidget,
    );
  });

  testWidgets('reporting a dose records it and returns the event id',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 7,
          'medication_id': 1,
          'medication_name': 'Levodopa',
          'adherence': 'taken',
          'scheduled_at': null,
          'taken_at': '2026-06-18T09:30:00Z',
          'recorded_at': '2026-06-18T10:00:00Z',
        }),
        201,
      );
    });
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    await tester.tap(find.text('About 1 hour ago'));
    await tester.pump();
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    final http.Request post = built.requests.lastWhere(
      (http.Request request) => request.method == 'POST',
    );
    final Map<String, dynamic> body =
        jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['medication_id'], 1);
    expect(body['adherence'], 'taken');
    expect(body['taken_at'], isNotNull);
    // Exactly one dose was recorded, and the sheet closed on it.
    expect(
      built.requests.where((http.Request r) => r.method == 'POST'),
      hasLength(1),
    );
  });

  testWidgets('saving pops the event id the caller will attach',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 42,
          'medication_id': 1,
          'medication_name': 'Levodopa',
          'adherence': 'taken',
          'scheduled_at': null,
          'taken_at': '2026-06-18T09:30:00Z',
          'recorded_at': '2026-06-18T10:00:00Z',
        }),
        201,
      );
    });
    await built.controller.load();
    int? popped;

    await _openSheet(
      tester,
      _Harness(
        controller: built.controller,
        onResult: (int? value) => popped = value,
      ),
    );
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(popped, 42);
  });

  testWidgets('"I did not take it" is recorded without inventing a time',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 8,
          'medication_id': 1,
          'medication_name': 'Levodopa',
          'adherence': 'not_taken',
          'scheduled_at': null,
          'taken_at': null,
          'recorded_at': '2026-06-18T10:00:00Z',
        }),
        201,
      );
    });
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    await tester.tap(find.text('I did not take it'));
    await tester.pumpAndSettle();
    // With no dose taken, asking "when?" would be a question with no answer.
    expect(find.text('When?'), findsNothing);

    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body =
        jsonDecode(built.requests.last.body) as Map<String, dynamic>;
    expect(body['adherence'], 'not_taken');
    expect(body['taken_at'], isNull);
  });

  testWidgets('"I am not sure about the time" sends no time at all',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 9,
          'medication_id': 1,
          'medication_name': 'Levodopa',
          'adherence': 'taken',
          'scheduled_at': null,
          'taken_at': null,
          'recorded_at': '2026-06-18T10:00:00Z',
        }),
        201,
      );
    });
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    await tester.tap(find.text("I'm not sure"));
    await tester.pump();
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body =
        jsonDecode(built.requests.last.body) as Map<String, dynamic>;
    // The patient said they took it and could not say when. That stays two
    // separate facts: the backend must not be handed a timestamp it would then
    // classify as a known window.
    expect(body['adherence'], 'taken');
    expect(body['taken_at'], isNull);
  });

  testWidgets('"Not sure" about the dose itself is a complete answer',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'id': 10,
          'medication_id': 1,
          'medication_name': 'Levodopa',
          'adherence': 'not_sure',
          'scheduled_at': null,
          'taken_at': null,
          'recorded_at': '2026-06-18T10:00:00Z',
        }),
        201,
      );
    });
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    await tester.tap(find.text('Not sure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body =
        jsonDecode(built.requests.last.body) as Map<String, dynamic>;
    expect(body['adherence'], 'not_sure');
    expect(body['taken_at'], isNull);
  });

  testWidgets('an inactive medication is never offered as context',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<dynamic>[
            medicationJson(id: 1),
            medicationJson(id: 2, name: 'Past drug', isActive: false),
          ]),
          200,
        ));
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    expect(find.textContaining('Levodopa'), findsOneWidget);
    expect(find.textContaining('Past drug'), findsNothing);
  });

  testWidgets('a failed dose report closes the step instead of inventing one',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(
        jsonEncode(<String, dynamic>{'detail': 'Medication not found.'}),
        404,
      );
    });
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    // Nothing to attach: the caller receives null and the assessment is
    // submitted with an unknown context rather than a fabricated dose.
    expect(find.text('Medication check'), findsNothing);
    expect(built.controller.errorMessage, 'Medication not found.');
  });

  testWidgets('continuing without records nothing at all',
      (WidgetTester tester) async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response('{}', 201);
    });
    await built.controller.load();

    await _openSheet(
        tester, _Harness(controller: built.controller, onResult: (_) {}));

    await tester.tap(find.text('Continue without'));
    await tester.pumpAndSettle();

    expect(
      built.requests.where((http.Request r) => r.method == 'POST'),
      isEmpty,
    );
  });
}
