import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_doctor/core/network/api_client.dart';
import 'package:neurosync_doctor/core/storage/session_token_store.dart';
import 'package:neurosync_doctor/features/patients/data/assignment_repository.dart';
import 'package:neurosync_doctor/features/patients/models/assessment_option.dart';
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

    test('reads the settings the assignment was created with', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(<dynamic>[
          assignmentJson(
            assessmentSlug: 'line_tracing',
            assessmentTitle: 'Line Tracing',
            parameters: <String, Object>{
              'pacing': 'slow',
              'repetitions': 6,
              'line_length_percent': 50,
            },
          ),
        ]),
      );

      await controller.loadAssignments(41);

      final assignment = controller.assignments.single;
      expect(assignment.assessmentSlug, 'line_tracing');
      expect(assignment.parameters['repetitions'], 6);
      expect(assignment.parameters['pacing'], 'slow');
    });

    test('recognises an exercise the doctor removed', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(
          <dynamic>[assignmentJson(status: 'archived')],
        ),
      );

      await controller.loadAssignments(41);

      expect(controller.assignments.single.isRemoved, isTrue);
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

  group('loadCatalog', () {
    test('loads every test with its declared settings', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(assessmentCatalogJson()),
      );

      await controller.loadCatalog();

      expect(controller.hasLoadedCatalog, isTrue);
      // Every entry is described; only the two that are ready can be handed out.
      expect(controller.assessments, hasLength(4));
      expect(
        controller.assignableAssessments.map((AssessmentOption o) => o.slug),
        <String>['finger_tapping', 'line_tracing'],
      );
      final tracing = controller.assessmentFor('line_tracing')!;
      expect(tracing.isCanvas, isTrue);
      expect(tracing.defaultDurationSeconds, 30);
      expect(tracing.defaultValues, <String, Object>{
        'pacing': 'comfortable',
        'repetitions': 3,
        'line_length_percent': 70,
      });
    });

    test('shows the held-back tests without letting them be assigned',
        () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(assessmentCatalogJson()),
      );

      await controller.loadCatalog();

      // A doctor has to see what is coming, but cannot pick it.
      for (final String slug in <String>['spiral_drawing', 'handwriting']) {
        final AssessmentOption option = controller.assessmentFor(slug)!;
        expect(option.isSupported, isFalse, reason: slug);
        expect(option.title, isNotEmpty, reason: slug);
        expect(option.parameters, isNotEmpty, reason: slug);
      }
      expect(
        controller.assignableAssessments.map((AssessmentOption o) => o.slug),
        isNot(contains('spiral_drawing')),
      );
      expect(
        controller.assignableAssessments.map((AssessmentOption o) => o.slug),
        isNot(contains('handwriting')),
      );
    });

    test('keeps a test without a runner visible but not assignable', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(<Map<String, dynamic>>[
          assessmentJson(slug: 'foot_tapping', isSupported: false),
          assessmentJson(),
        ]),
      );

      await controller.loadCatalog();

      expect(controller.assessments, hasLength(2));
      expect(controller.assignableAssessments, hasLength(1));
    });

    test('reads the phrase bound for a text setting', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(<Map<String, dynamic>>[
          assessmentJson(
            slug: 'handwriting',
            parameters: <Map<String, Object>>[
              textParameter('phrase', 'Phrase', 'NeuroSync', 60),
            ],
          ),
        ]),
      );

      await controller.loadCatalog();

      final phrase = controller.assessmentFor('handwriting')!.parameters.single;
      expect(phrase.isText, isTrue);
      expect(phrase.maxLength, 60);
    });

    test('surfaces a load failure without clearing what it already had',
        () async {
      int calls = 0;
      final AssignmentController controller = buildController(
        (http.Request request) async {
          calls++;
          if (calls == 1) {
            return json(assessmentCatalogJson());
          }
          return json(<String, dynamic>{'detail': 'Not authenticated.'}, 401);
        },
      );
      await controller.loadCatalog();

      await controller.loadCatalog();

      expect(controller.assessments, hasLength(4));
      expect(controller.errorMessage, 'Not authenticated.');
    });
  });

  group('createAssignment', () {
    test('posts the slug, duration and settings, then reloads the open patient',
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
        assessmentSlug: 'spiral_drawing',
        durationSeconds: 90,
        parameters: <String, Object>{'pacing': 'slow', 'turns': 4},
      );

      expect(created, isTrue);
      expect(controller.errorMessage, isNull);
      expect(requests, hasLength(2));
      expect(requests.first.method, 'POST');
      expect(requests.first.url.path, '/doctor/patients/41/assignments');
      expect(requests.last.method, 'GET');
      // The title is trimmed and an empty one is omitted entirely.
      expect(_body(requests.first)['title'], 'Morning taps');
      expect(_body(requests.first)['assessment_slug'], 'spiral_drawing');
      expect(_body(requests.first)['duration_seconds'], 90);
      expect(_body(requests.first)['parameters'],
          <String, Object>{'pacing': 'slow', 'turns': 4});
      expect(controller.assignments, hasLength(2));
    });

    test('omits an empty title and empty settings from the payload', () async {
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
      expect(_body(requests.single).containsKey('parameters'), isFalse);
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

  group('updateAssignment', () {
    test('patches only the fields the caller sends', () async {
      final List<http.Request> requests = <http.Request>[];
      final AssignmentController controller =
          buildController((http.Request request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          return json(assignmentJson(
            durationSeconds: 90,
            parameters: <String, Object>{'repetitions': 7, 'pacing': 'fast'},
          ));
        }
        return json(<dynamic>[assignmentJson()]);
      });
      await controller.loadAssignments(41);
      requests.clear();

      final bool saved = await controller.updateAssignment(
        patientId: 41,
        assignmentId: 77,
        durationSeconds: 90,
      );

      expect(saved, isTrue);
      expect(requests, hasLength(2));
      expect(requests.first.method, 'PATCH');
      expect(requests.first.url.path, '/doctor/patients/41/assignments/77');
      final payload = _body(requests.first);
      expect(payload['duration_seconds'], 90);
      // The title and settings were not touched, so they are not sent.
      expect(payload.containsKey('title'), isFalse);
      expect(payload.containsKey('parameters'), isFalse);
    });

    test('sends the full replacement settings when they change', () async {
      final List<http.Request> requests = <http.Request>[];
      final AssignmentController controller =
          buildController((http.Request request) async {
        requests.add(request);
        return request.method == 'PATCH'
            ? json(assignmentJson())
            : json(<dynamic>[assignmentJson()]);
      });

      await controller.updateAssignment(
        patientId: 41,
        assignmentId: 77,
        parameters: <String, Object>{
          'pacing': 'slow',
          'turns': 4,
          'size_percent': 80
        },
      );

      expect(_body(requests.first)['parameters'], <String, Object>{
        'pacing': 'slow',
        'turns': 4,
        'size_percent': 80,
      });
    });

    test('surfaces a rejected setting and reports failure', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(
          <String, dynamic>{'detail': "'turns' must be between 1 and 6."},
          422,
        ),
      );

      final bool saved = await controller.updateAssignment(
        patientId: 41,
        assignmentId: 77,
        parameters: <String, Object>{'turns': 20},
      );

      expect(saved, isFalse);
      expect(controller.errorMessage, "'turns' must be between 1 and 6.");
    });
  });

  group('removeAssignment', () {
    test('deletes the exercise and reloads the open patient', () async {
      final List<http.Request> requests = <http.Request>[];
      final AssignmentController controller =
          buildController((http.Request request) async {
        requests.add(request);
        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }
        return json(<dynamic>[assignmentJson(status: 'archived')]);
      });
      await controller.loadAssignments(41);
      requests.clear();

      final bool removed = await controller.removeAssignment(
        patientId: 41,
        assignmentId: 77,
      );

      expect(removed, isTrue);
      expect(requests, hasLength(2));
      expect(requests.first.method, 'DELETE');
      expect(requests.first.url.path, '/doctor/patients/41/assignments/77');
      expect(requests.last.method, 'GET');
      expect(controller.assignments.single.isRemoved, isTrue);
    });

    test('surfaces the API error and reports failure', () async {
      final AssignmentController controller = buildController(
        (http.Request request) async => json(
          <String, dynamic>{'detail': 'Exercise not found for this patient.'},
          404,
        ),
      );

      final bool removed = await controller.removeAssignment(
        patientId: 41,
        assignmentId: 999,
      );

      expect(removed, isFalse);
      expect(controller.errorMessage, 'Exercise not found for this patient.');
      expect(controller.isSubmitting, isFalse);
    });
  });

  group('AssessmentOption', () {
    test('seeds an editor from the stored settings', () {
      final option = AssessmentOption.fromJson(
        assessmentJson(parameters: <Map<String, Object>>[
          choiceParameter('pacing', 'Speed', 'comfortable',
              <String>['slow', 'comfortable', 'fast']),
          integerParameter('turns', 'Turns', 2, 1, 6),
        ]),
      );

      expect(
        option.valuesFrom(<String, Object>{'pacing': 'fast'}),
        <String, Object>{'pacing': 'fast', 'turns': 2},
      );
    });

    test('names a choice the way a clinician would say it', () {
      expect(AssessmentParameter.labelForChoice('comfortable'), 'Comfortable');
      expect(AssessmentParameter.labelForChoice('little'), 'Little');
    });
  });
}

Map<String, dynamic> _body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;
