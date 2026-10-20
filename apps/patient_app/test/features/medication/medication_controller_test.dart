import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/features/medication/data/medication_repository.dart';
import 'package:neurosync_patient/features/medication/models/medication.dart';
import 'package:neurosync_patient/features/medication/state/medication_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

Map<String, dynamic> medicationJson({
  int id = 1,
  String name = 'Levodopa',
  bool isActive = true,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'dose_label': '100mg',
    'frequency_label': '4 times daily',
    'is_active': isActive,
    'created_at': '2026-06-18T10:00:00Z',
    'updated_at': '2026-06-18T10:00:00Z',
  };
}

/// Builds a controller over a scripted HTTP handler, recording every request.
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

void main() {
  test('loads the medications the backend returns', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<dynamic>[
            medicationJson(),
            medicationJson(id: 2, name: 'Ropinirole')
          ]),
          200,
        ));

    await built.controller.load();

    expect(built.controller.hasLoaded, isTrue);
    expect(built.controller.medications, hasLength(2));
    expect(built.controller.errorMessage, isNull);
  });

  test('a failed load reports the message instead of an empty list', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{'detail': 'Server exploded.'}),
          500,
        ));

    await built.controller.load();

    expect(built.controller.errorMessage, 'Server exploded.');
    expect(built.controller.medications, isEmpty);
    expect(built.controller.hasLoaded, isFalse);
  });

  test('only active medications are offered as context', () async {
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

    expect(built.controller.medications, hasLength(2));
    expect(built.controller.activeMedications.map((Medication m) => m.id),
        <int>[1]);
  });

  test('a name is required before anything is sent', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response('{}', 201));

    final bool added = await built.controller.add(name: '   ');

    expect(added, isFalse);
    expect(built.controller.errorMessage, 'A medication needs a name.');
    expect(built.requests, isEmpty);
  });

  test('a new medication is stored exactly as typed', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async =>
        http.Response(jsonEncode(medicationJson()), 201));

    final bool added = await built.controller.add(
      name: '  Levodopa ',
      doseLabel: ' 100mg ',
      frequencyLabel: '   ',
    );

    expect(added, isTrue);
    final Map<String, dynamic> body =
        jsonDecode(built.requests.single.body) as Map<String, dynamic>;
    // Surrounding whitespace is tidied away...
    expect(body['name'], 'Levodopa');
    expect(body['dose_label'], '100mg');
    // ...but a field the patient left blank is sent as null, never as ''.
    expect(body['frequency_label'], isNull);
    expect(body['frequency_label'], isNot(''));
    expect(built.controller.medications, hasLength(1));
  });

  test('deactivating keeps the medication and swaps its flag', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode(<dynamic>[medicationJson()]), 200);
      }
      return http.Response(jsonEncode(medicationJson(isActive: false)), 200);
    });
    await built.controller.load();

    final bool updated = await built.controller.setActive(
      medicationId: 1,
      isActive: false,
    );

    expect(updated, isTrue);
    expect(built.controller.medications.single.isActive, isFalse);
    expect(built.controller.activeMedications, isEmpty);
    expect(built.requests.last.url.query, contains('is_active=false'));
  });

  test('a reported dose sends exactly what the patient said', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'id': 7,
            'medication_id': 1,
            'medication_name': 'Levodopa',
            'adherence': 'not_taken',
            'scheduled_at': null,
            'taken_at': null,
            'recorded_at': '2026-06-18T10:00:00Z',
          }),
          201,
        ));

    final MedicationEvent? event = await built.controller.reportDose(
      medicationId: 1,
      adherence: MedicationAdherence.notTaken,
    );

    expect(event, isNotNull);
    expect(event!.adherence, MedicationAdherence.notTaken);
    final Map<String, dynamic> body =
        jsonDecode(built.requests.single.body) as Map<String, dynamic>;
    expect(body['adherence'], 'not_taken');
    expect(body['medication_id'], 1);
    // No time was given, so none is invented for the backend to classify.
    expect(body['taken_at'], isNull);
    expect(event, isNotNull);
  });

  test('a reported dose with a time sends it as UTC', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'id': 8,
            'medication_id': 1,
            'medication_name': 'Levodopa',
            'adherence': 'taken',
            'scheduled_at': null,
            'taken_at': '2026-06-18T09:30:00Z',
            'recorded_at': '2026-06-18T10:00:00Z',
          }),
          201,
        ));

    final MedicationEvent? event = await built.controller.reportDose(
      medicationId: 1,
      adherence: MedicationAdherence.taken,
      takenAt: DateTime.parse('2026-06-18T09:30:00Z'),
    );

    expect(event, isNotNull);
    final Map<String, dynamic> body =
        jsonDecode(built.requests.single.body) as Map<String, dynamic>;
    expect(body['taken_at'], '2026-06-18T09:30:00.000Z');
  });

  test('a dose report that fails returns null so nothing is attached',
      () async {
    // The caller attaches no context on null. A dose the app could not record
    // must never be replaced by one it made up.
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{'detail': 'Medication not found.'}),
          404,
        ));

    final MedicationEvent? event = await built.controller.reportDose(
      medicationId: 999,
      adherence: MedicationAdherence.taken,
      takenAt: DateTime.now(),
    );

    expect(event, isNull);
    expect(built.controller.errorMessage, 'Medication not found.');
    expect(event, isNull);
  });

  test('clearing drops every patient-owned record on sign-out', () async {
    final ({
      MedicationController controller,
      List<http.Request> requests
    }) built = build((http.Request request) async => http.Response(
          jsonEncode(<dynamic>[medicationJson()]),
          200,
        ));
    await built.controller.load();

    built.controller.clear();

    expect(built.controller.medications, isEmpty);
    expect(built.controller.hasLoaded, isFalse);
  });
}
