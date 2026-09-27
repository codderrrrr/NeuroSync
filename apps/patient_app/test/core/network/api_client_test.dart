import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/network/api_exception.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';

ApiClient buildClient(MockClient mockClient, {String? token}) {
  return ApiClient(
    baseUrl: 'http://api.test',
    httpClient: mockClient,
    sessionToken: SessionTokenCache()..value = token,
  );
}

void main() {
  test('decodes a JSON object response', () async {
    final ApiClient client = buildClient(
      MockClient((http.Request request) async {
        return http.Response(
            jsonEncode(<String, dynamic>{'status': 'healthy'}), 200);
      }),
    );

    final Map<String, dynamic> body = await client.getObject('/health');

    expect(body['status'], 'healthy');
  });

  test('sends the cached bearer token', () async {
    String? authorization;
    final ApiClient client = buildClient(
      MockClient((http.Request request) async {
        authorization = request.headers['Authorization'];
        return http.Response('{}', 200);
      }),
      token: 'token-123',
    );

    await client.getObject('/auth/me');

    expect(authorization, 'Bearer token-123');
  });

  test('translates an error response into an ApiException', () async {
    final ApiClient client = buildClient(
      MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{'detail': 'Invalid email or password.'}),
          401,
        );
      }),
    );

    await expectLater(
      client.getObject('/auth/me'),
      throwsA(
        isA<ApiException>()
            .having((ApiException error) => error.statusCode, 'statusCode', 401)
            .having(
              (ApiException error) => error.message,
              'message',
              'Invalid email or password.',
            ),
      ),
    );
  });

  test('reads the first validation message from a 422 response', () async {
    final ApiClient client = buildClient(
      MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'detail': <dynamic>[
              <String, dynamic>{
                'msg': 'value is not a valid email address',
                'loc': <dynamic>['body', 'email'],
              },
            ],
          }),
          422,
        );
      }),
    );

    await expectLater(
      client.postObject('/auth/signup', <String, dynamic>{'email': 'nope'}),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.message,
          'message',
          'value is not a valid email address',
        ),
      ),
    );
  });

  test('reports connection failures as ApiException', () async {
    final ApiClient client = buildClient(
      MockClient((http.Request request) async {
        throw http.ClientException('Connection refused');
      }),
    );

    await expectLater(
        client.getObject('/health'), throwsA(isA<ApiException>()));
  });
}
