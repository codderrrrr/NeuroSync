import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_doctor/core/network/api_client.dart';
import 'package:neurosync_doctor/core/storage/session_token_store.dart';
import 'package:neurosync_doctor/features/patients/data/assignment_repository.dart';
import 'package:neurosync_doctor/features/patients/state/assignment_controller.dart';

import '../../test_support.dart';

AssignmentController buildController(
  Future<http.Response> Function(http.Request) handler,
) =>
    AssignmentController(
      repository: AssignmentRepository(
        apiClient: ApiClient(
          baseUrl: 'http://api.test',
          httpClient: MockClient(handler),
          sessionToken: SessionTokenCache(),
        ),
      ),
    );

void main() {
  group('loadAssignments', () {
    test('loads the exercises for the patient', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(<dynamic>[assignmentJson()]),
      );

      await controller.loadAssignments(41);

      expect(controller.hasLoaded, isTrue);
      expect(controller.errorMessage, isNull);
      expect(controller.assignments.single.title, 'Finger Tapping');
      expect(controller.assignments.single.durationSeconds, 60);
    });

    test('surfaces the API error and does not claim the list loaded', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(
          <String, dynamic>{'detail': 'Patient not found in your roster.'},
          404,
        ),
      );

      await controller.loadAssignments(41);

      expect(controller.errorMessage, 'Patient not found in your roster.');
      expect(controller.hasLoaded, isFalse);
    });
  });

  group('createAssignment', () {
    test('posts the slug and duration, then reloads the open patient',
        () async {
      final List<http.Request> requests = <http.Request>[];
      final AssignmentController controller =
          buildController((http.Request request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return json(assignmentJson(id: 78), 201);
        }
        return json(<dynamic>[assignmentJson(), assignmentJson(id: 78)]);
      });
      await controller.loadAssignments(41);
      requests.clear();

      final bool created = await controller.createAssignment(
        patientId: 41,
        title: '  Morning taps  ',
        assessmentSlug: 'finger_tapping',
        durationSeconds: 90,
      );

      expect(created, isTrue);
      expect(controller.errorMessage, isNull);
      expect(requests, hasLength(2));
      expect(requests.first.method, 'POST');
      expect(requests.first.url.path, '/doctor/patients/41/assignments');
      expect(requests.last.method, 'GET');
      // The title is trimmed and an empty one is omitted entirely.
      expect(_body(requests.first)['title'], 'Morning taps');
      expect(_body(requests.first)['assessment_slug'], 'finger_tapping');
      expect(_body(requests.first)['duration_seconds'], 90);
      expect(controller.assignments, hasLength(2));
    });

    test('omits an empty title from the payload', () async {
      final List<http.Request> requests = <http.Request>[];
      final AssignmentController controller =
          buildController((http.Request request) async {
        requests.add(request);
        return request.method == 'POST'
            ? json(assignmentJson(), 201)
            : json(<dynamic>[]);
      });

      await controller.createAssignment(
        patientId: 41,
        title: '   ',
        assessmentSlug: 'finger_tapping',
        durationSeconds: 30,
      );

      expect(requests.single.method, 'POST');
      expect(_body(requests.single).containsKey('title'), isFalse);
    });

    test('does not reload a patient that is not open', () async {
      final List<http.Request> requests = <http.Request>[];
      final AssignmentController controller =
          buildController((http.Request request) async {
        requests.add(request);
        return request.method == 'POST'
            ? json(assignmentJson(), 201)
            : json(<dynamic>[]);
      });

      final bool created = await controller.createAssignment(
        patientId: 41,
        title: null,
        assessmentSlug: 'finger_tapping',
        durationSeconds: 30,
      );

      expect(created, isTrue);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
    });

    test('surfaces the API error and reports failure', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(
          <String, dynamic>{'detail': 'Patient not found in your roster.'},
          404,
        ),
      );

      final bool created = await controller.createAssignment(
        patientId: 41,
        title: null,
        assessmentSlug: 'finger_tapping',
        durationSeconds: 30,
      );

      expect(created, isFalse);
      expect(controller.errorMessage, 'Patient not found in your roster.');
      expect(controller.isSubmitting, isFalse);
    });
  });
}

Map<String, dynamic> _body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;
