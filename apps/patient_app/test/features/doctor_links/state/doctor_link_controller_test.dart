import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/models/doctor_link.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';

DoctorLinkController buildController(MockClient mockClient) {
  return DoctorLinkController(
    repository: DoctorLinkRepository(
      apiClient: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: mockClient,
        sessionToken: SessionTokenCache(),
      ),
    ),
  );
}

void main() {
  test('loading maps the statuses the API reports', () async {
    final DoctorLinkController controller = buildController(
      MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<dynamic>[
            <String, dynamic>{
              'doctor_id': 1,
              'status': 'pending',
              'created_at': '2026-01-01T10:00:00Z',
            },
            <String, dynamic>{
              'doctor_id': 2,
              'status': 'active',
              'created_at': '2026-01-02T10:00:00Z',
            },
          ]),
          200,
        );
      }),
    );

    await controller.load();

    expect(controller.links, hasLength(2));
    expect(controller.links.first.status, DoctorLinkStatus.pending);
    expect(controller.links.first.isPending, isTrue);
    expect(controller.links.last.status, DoctorLinkStatus.active);
    expect(controller.hasLoaded, isTrue);
    expect(controller.errorMessage, isNull);
  });

  test('a link request shows the pending state returned by the server',
      () async {
    final DoctorLinkController controller = buildController(
      MockClient((http.Request request) async {
        expect(request.url.path, '/doctor-links');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'doctor_id': 7,
            'status': 'pending',
            'created_at': '2026-01-03T10:00:00Z',
          }),
          201,
        );
      }),
    );

    final bool succeeded = await controller.request('ABC123');

    expect(succeeded, isTrue);
    expect(controller.links, hasLength(1));
    expect(controller.links.single.doctorId, 7);
    expect(controller.links.single.status, DoctorLinkStatus.pending);
    expect(controller.hasPendingConfirmation, isTrue);
  });

  test('an unknown doctor code surfaces the API message', () async {
    final DoctorLinkController controller = buildController(
      MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'detail': 'That doctor code was not recognised.',
          }),
          404,
        ),
      ),
    );

    final bool succeeded = await controller.request('NOPE99');

    expect(succeeded, isFalse);
    expect(controller.links, isEmpty);
    expect(controller.errorMessage, 'That doctor code was not recognised.');
  });

  test('clearing removes loaded links on sign-out', () async {
    final DoctorLinkController controller = buildController(
      MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<dynamic>[
            <String, dynamic>{
              'doctor_id': 3,
              'status': 'pending',
              'created_at': '2026-01-04T10:00:00Z',
            },
          ]),
          200,
        ),
      ),
    );
    await controller.load();

    controller.clear();

    expect(controller.links, isEmpty);
    expect(controller.hasLoaded, isFalse);
  });
}
