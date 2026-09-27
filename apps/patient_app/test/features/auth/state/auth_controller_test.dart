import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/features/auth/data/auth_repository.dart';
import 'package:neurosync_patient/features/auth/state/auth_controller.dart';

const String _patientJson =
    '{"id": 1, "email": "ada@example.com", "name": "Ada Lovelace", '
    '"created_at": "2026-01-01T10:00:00Z"}';

String _authBody([String token = 'token-1']) {
  return jsonEncode(<String, dynamic>{
    'patient': jsonDecode(_patientJson),
    'access_token': token,
    'token_type': 'bearer',
    'expires_at': '2026-12-31T10:00:00Z',
  });
}

AuthController buildController({
  required MockClient mockClient,
  required SessionTokenStore tokenStore,
}) {
  final SessionTokenCache tokenCache = SessionTokenCache();
  return AuthController(
    repository: AuthRepository(
      apiClient: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: mockClient,
        sessionToken: tokenCache,
      ),
    ),
    tokenStore: tokenStore,
    tokenCache: tokenCache,
  );
}

void main() {
  test('restoring with no stored token signs the patient out', () async {
    final AuthController controller = buildController(
      mockClient:
          MockClient((http.Request request) async => http.Response('{}', 500)),
      tokenStore: InMemorySessionTokenStore(),
    );

    await controller.restoreSession();

    expect(controller.status, AuthStatus.signedOut);
  });

  test('restoring a usable stored session signs the patient in', () async {
    final AuthController controller = buildController(
      mockClient: MockClient((http.Request request) async {
        expect(request.url.path, '/auth/me');
        expect(request.headers['Authorization'], 'Bearer stored-token');
        return http.Response(_patientJson, 200);
      }),
      tokenStore: InMemorySessionTokenStore('stored-token'),
    );

    await controller.restoreSession();

    expect(controller.status, AuthStatus.signedIn);
    expect(controller.patient?.email, 'ada@example.com');
    expect(controller.patient?.firstName, 'Ada');
  });

  test('an unusable stored token is discarded', () async {
    final InMemorySessionTokenStore store =
        InMemorySessionTokenStore('stale-token');
    final AuthController controller = buildController(
      mockClient: MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{'detail': 'Authentication required.'}),
          401,
        ),
      ),
      tokenStore: store,
    );

    await controller.restoreSession();

    expect(controller.status, AuthStatus.signedOut);
    expect(await store.read(), isNull);
  });

  test('signing in stores the session token', () async {
    final InMemorySessionTokenStore store = InMemorySessionTokenStore();
    final AuthController controller = buildController(
      mockClient: MockClient((http.Request request) async {
        expect(request.url.path, '/auth/login');
        return http.Response(_authBody(), 200);
      }),
      tokenStore: store,
    );

    final bool succeeded = await controller.signIn(
      email: 'ada@example.com',
      password: 'correct-horse-battery',
    );

    expect(succeeded, isTrue);
    expect(controller.status, AuthStatus.signedIn);
    expect(await store.read(), 'token-1');
  });

  test('signing up authenticates the patient immediately', () async {
    final InMemorySessionTokenStore store = InMemorySessionTokenStore();
    final AuthController controller = buildController(
      mockClient: MockClient((http.Request request) async {
        expect(request.url.path, '/auth/signup');
        return http.Response(_authBody('token-2'), 201);
      }),
      tokenStore: store,
    );

    final bool succeeded = await controller.signUp(
      name: 'Ada Lovelace',
      email: 'ada@example.com',
      password: 'correct-horse-battery',
    );

    expect(succeeded, isTrue);
    expect(controller.status, AuthStatus.signedIn);
    expect(await store.read(), 'token-2');
  });

  test('a rejected sign-in keeps the message for the UI', () async {
    final AuthController controller = buildController(
      mockClient: MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{'detail': 'Invalid email or password.'}),
          401,
        ),
      ),
      tokenStore: InMemorySessionTokenStore(),
    );

    final bool succeeded = await controller.signIn(
      email: 'ada@example.com',
      password: 'wrong-password',
    );

    expect(succeeded, isFalse);
    expect(controller.status, isNot(AuthStatus.signedIn));
    expect(controller.errorMessage, 'Invalid email or password.');
  });

  test('signing out clears the stored token', () async {
    final InMemorySessionTokenStore store =
        InMemorySessionTokenStore('token-1');
    final AuthController controller = buildController(
      mockClient: MockClient((http.Request request) async {
        if (request.url.path == '/auth/me') {
          return http.Response(_patientJson, 200);
        }
        return http.Response('', 204);
      }),
      tokenStore: store,
    );
    await controller.restoreSession();

    await controller.signOut();

    expect(controller.status, AuthStatus.signedOut);
    expect(controller.patient, isNull);
    expect(await store.read(), isNull);
  });
}
