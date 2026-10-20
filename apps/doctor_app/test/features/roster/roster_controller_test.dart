import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_doctor/features/roster/data/roster_repository.dart';
import 'package:neurosync_doctor/features/roster/models/roster_models.dart';
import 'package:neurosync_doctor/features/roster/state/roster_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../test_support.dart';

RosterController buildController(
  Future<http.Response> Function(http.Request) handler,
) =>
    RosterController(
      repository: RosterRepository(
        apiClient: ApiClient(
          baseUrl: 'http://api.test',
          httpClient: MockClient(handler),
          sessionToken: SessionTokenCache(),
        ),
      ),
    );

/// Answers the two dashboard reads with one pending request and one patient.
Future<http.Response> _dashboard(http.Request request) async {
  if (request.url.path == '/doctor/patient-links/pending') {
    return json(<dynamic>[pendingRequestJson()]);
  }
  if (request.url.path == '/doctor/patients') {
    return json(<dynamic>[rosterPatientJson()]);
  }
  throw StateError('unexpected request: ${request.method} ${request.url.path}');
}

void main() {
  group('loadDashboard', () {
    test('loads pending requests and the active roster', () async {
      final RosterController controller = buildController(_dashboard);

      await controller.loadDashboard();

      expect(controller.hasLoaded, isTrue);
      expect(controller.errorMessage, isNull);
      expect(controller.pending.single.linkId, 12);
      expect(controller.pending.single.patientName, 'Jonas Keller');
      expect(controller.patients.single.patientId, 41);
      expect(controller.patients.single.status, 'active');
    });

    test('lands an empty roster when nothing is linked', () async {
      final RosterController controller = buildController(
        (http.Request request) async => json(<dynamic>[]),
      );

      await controller.loadDashboard();

      expect(controller.hasLoaded, isTrue);
      expect(controller.pending, isEmpty);
      expect(controller.patients, isEmpty);
    });

    test('surfaces the API error and does not claim the dashboard loaded',
        () async {
      final RosterController controller = buildController(
        (http.Request request) async => json(
          <String, dynamic>{'detail': 'Doctor authentication required.'},
          401,
        ),
      );

      await controller.loadDashboard();

      expect(controller.errorMessage, 'Doctor authentication required.');
      expect(controller.hasLoaded, isFalse);
    });
  });

  group('accept', () {
    test('accepts a request and reloads both sections', () async {
      final List<String> calls = <String>[];
      final RosterController controller =
          buildController((http.Request request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          return json(<String, dynamic>{
            'id': 12,
            'patient_id': 41,
            'patient_name': 'Jonas Keller',
            'status': 'active',
            'accepted_at': '2026-09-30T10:00:00Z',
          });
        }
        return _dashboard(request);
      });
      await controller.loadDashboard();
      final PendingRequest request = controller.pending.single;
      calls.clear();

      final bool accepted = await controller.accept(request);

      expect(accepted, isTrue);
      expect(controller.errorMessage, isNull);
      expect(
        calls,
        <String>[
          'POST /doctor/patient-links/12/accept',
          'GET /doctor/patient-links/pending',
          'GET /doctor/patients',
        ],
      );
    });

    test('reports the rejection when the request is not the doctor\'s',
        () async {
      final RosterController controller =
          buildController((http.Request request) async {
        if (request.method == 'POST') {
          return json(
            <String, dynamic>{'detail': 'Patient request not found.'},
            404,
          );
        }
        return _dashboard(request);
      });
      await controller.loadDashboard();
      final PendingRequest request = controller.pending.single;

      final bool accepted = await controller.accept(request);

      expect(accepted, isFalse);
      expect(controller.errorMessage, 'Patient request not found.');
    });
  });
}
