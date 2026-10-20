import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/features/check_ins/data/check_in_repository.dart';
import 'package:neurosync_patient/features/check_ins/state/check_in_controller.dart';
import 'package:neurosync_core/neurosync_core.dart';

CheckInController buildController(MockClient mockClient) {
  return CheckInController(
    repository: CheckInRepository(
      apiClient: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: mockClient,
        sessionToken: SessionTokenCache(),
      ),
    ),
  );
}

Map<String, dynamic> _checkInJson({
  required int id,
  required String recordedAt,
  int tremor = 1,
  int stiffness = 2,
  int slowness = 0,
  int balance = 3,
  String? note,
}) {
  return <String, dynamic>{
    'id': id,
    'recorded_at': recordedAt,
    'tremor': tremor,
    'stiffness': stiffness,
    'slowness': slowness,
    'balance': balance,
    'note': note,
    'created_at': recordedAt,
  };
}

void main() {
  test('loading maps the ratings the API reports', () async {
    final CheckInController controller = buildController(
      MockClient((http.Request request) async {
        expect(request.url.path, '/check-ins');
        return http.Response(
          jsonEncode(<dynamic>[
            _checkInJson(id: 2, recordedAt: '2026-06-02T08:00:00Z', note: 'ok'),
            _checkInJson(id: 1, recordedAt: '2026-06-01T08:00:00Z'),
          ]),
          200,
        );
      }),
    );

    await controller.load();

    expect(controller.checkIns, hasLength(2));
    expect(controller.checkIns.first.id, 2);
    expect(controller.checkIns.first.tremor, 1);
    expect(controller.checkIns.first.stiffness, 2);
    expect(controller.checkIns.first.balance, 3);
    expect(controller.checkIns.first.note, 'ok');
    expect(controller.checkIns.last.note, isNull);
    expect(controller.hasLoaded, isTrue);
    expect(controller.errorMessage, isNull);
  });

  test('recording a check-in posts the ratings and prepends the server row',
      () async {
    final CheckInController controller = buildController(
      MockClient((http.Request request) async {
        expect(request.url.path, '/check-ins');
        final Map<String, dynamic> body =
            jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['tremor'], 2);
        expect(body['stiffness'], 1);
        expect(body['slowness'], 3);
        expect(body['balance'], 0);
        expect(body['note'], 'after lunch');
        // The client omits recorded_at so the server stamps the moment.
        expect(body.containsKey('recorded_at'), isFalse);
        return http.Response(
          jsonEncode(
            _checkInJson(
              id: 9,
              recordedAt: '2026-06-03T10:00:00Z',
              tremor: 2,
              stiffness: 1,
              slowness: 3,
              balance: 0,
              note: 'after lunch',
            ),
          ),
          201,
        );
      }),
    );

    final bool succeeded = await controller.create(
      tremor: 2,
      stiffness: 1,
      slowness: 3,
      balance: 0,
      note: 'after lunch',
    );

    expect(succeeded, isTrue);
    expect(controller.checkIns, hasLength(1));
    expect(controller.checkIns.single.id, 9);
    expect(controller.checkIns.single.note, 'after lunch');
    expect(controller.hasLoaded, isTrue);
  });

  test('a rejected check-in surfaces the API message', () async {
    final CheckInController controller = buildController(
      MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'detail': 'recorded_at cannot be in the future.',
          }),
          422,
        ),
      ),
    );

    final bool succeeded = await controller.create(
      tremor: 0,
      stiffness: 0,
      slowness: 0,
      balance: 0,
    );

    expect(succeeded, isFalse);
    expect(controller.checkIns, isEmpty);
    expect(controller.errorMessage, 'recorded_at cannot be in the future.');
    expect(controller.isSubmitting, isFalse);
  });

  test('clearing removes loaded check-ins on sign-out', () async {
    final CheckInController controller = buildController(
      MockClient((http.Request request) async => http.Response(
            jsonEncode(<dynamic>[
              _checkInJson(id: 5, recordedAt: '2026-06-05T08:00:00Z'),
            ]),
            200,
          )),
    );
    await controller.load();

    controller.clear();

    expect(controller.checkIns, isEmpty);
    expect(controller.hasLoaded, isFalse);
    expect(controller.errorMessage, isNull);
  });
}
