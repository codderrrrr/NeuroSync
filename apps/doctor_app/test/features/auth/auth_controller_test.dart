import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_doctor/core/network/api_client.dart';
import 'package:neurosync_doctor/core/storage/session_token_store.dart';
import 'package:neurosync_doctor/features/auth/data/auth_repository.dart';
import 'package:neurosync_doctor/features/auth/models/auth_result.dart';
import 'package:neurosync_doctor/features/auth/models/doctor.dart';
import 'package:neurosync_doctor/features/auth/state/auth_controller.dart';

import '../../test_support.dart';

/// Builds an [AuthController] around a scripted API and an in-memory store
/// that already holds [storedToken] (when given).
AuthController buildController(
  Future<http.Response> Function(http.Request) handler, {
  String? storedToken,
}) {
  final InMemorySessionTokenStore tokenStore = InMemorySessionTokenStore();
  if (storedToken != null) {
    tokenStore.write(storedToken);
  }
  return AuthController(
    repository: AuthRepository(
      apiClient: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient(handler),
        sessionToken: SessionTokenCache(),
      ),
    ),
    tokenStore: tokenStore,
    tokenCache: SessionTokenCache(),
  );
}

void main() {
  group('sign up', () {
    test('stores the session and the generated link code', () async {
      final AuthController controller =
          buildController((http.Request request) async {
        expect(request.url.path, '/doctor/auth/signup');
        return json(authBody(), 201);
      });

      final bool ok = await controller.signUp(
        name: 'Dr. Amara Osei',
        email: 'amara@clinic.example.com',
        password: 'a-very-long-password',
      );

      expect(ok, isTrue);
      expect(controller.status, AuthStatus.signedIn);
      expect(controller.errorMessage, isNull);
      expect(controller.doctor, isA<Doctor>());
      expect(controller.doctor?.code, kDoctorCode);
      expect(controller.doctor?.firstName, 'Dr.');
    });

    test('surfaces the API error and stays signed out', () async {
      final AuthController controller =
          buildController((http.Request request) async => json(
                <String, dynamic>{
                  'detail': 'An account with this email already exists.'
                },
                409,
              ));

      final bool ok = await controller.signUp(
        name: 'Dr. Amara Osei',
        email: 'amara@clinic.example.com',
        password: 'a-very-long-password',
      );

      expect(ok, isFalse);
      expect(controller.status, AuthStatus.signedOut);
      expect(
        controller.errorMessage,
        'An account with this email already exists.',
      );
    });
  });

  group('sign in', () {
    test('signs in with valid credentials', () async {
      final AuthController controller =
          buildController((http.Request request) async {
        expect(request.url.path, '/doctor/auth/login');
        return json(authBody(code: null));
      });

      final bool ok = await controller.signIn(
        email: 'amara@clinic.example.com',
        password: 'pass',
      );

      expect(ok, isTrue);
      expect(controller.status, AuthStatus.signedIn);
      // A legacy doctor without a code still signs in; the code is null.
      expect(controller.doctor?.code, isNull);
    });

    test('shows the rejection message on bad credentials', () async {
      final AuthController controller = buildController(
        (http.Request request) async =>
            json(<String, dynamic>{'detail': 'Invalid email or password.'}, 401),
      );

      final bool ok = await controller.signIn(
        email: 'amara@clinic.example.com',
        password: 'wrong',
      );

      expect(ok, isFalse);
      expect(controller.errorMessage, 'Invalid email or password.');
      expect(controller.status, AuthStatus.signedOut);
    });
  });

  group('restoreSession', () {
    test('lands signed out when nothing is stored', () async {
      final AuthController controller =
          buildController((http.Request request) async => json(doctorJson()));

      await controller.restoreSession();

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.doctor, isNull);
    });

    test('verifies the stored token against /doctor/auth/me', () async {
      final AuthController controller = buildController(
        (http.Request request) async {
          expect(request.url.path, '/doctor/auth/me');
          expect(request.headers['Authorization'], 'Bearer stored-token');
          return json(doctorJson());
        },
        storedToken: 'stored-token',
      );

      await controller.restoreSession();

      expect(controller.status, AuthStatus.signedIn);
      expect(controller.doctor?.code, kDoctorCode);
    });

    test('clears an expired or revoked token', () async {
      final InMemorySessionTokenStore tokenStore = InMemorySessionTokenStore();
      await tokenStore.write('stale-token');
      final AuthController controller = AuthController(
        repository: AuthRepository(
          apiClient: ApiClient(
            baseUrl: 'http://api.test',
            httpClient: MockClient((http.Request request) async =>
                json(<String, dynamic>{'detail': 'Not authenticated.'}, 401)),
            sessionToken: SessionTokenCache(),
          ),
        ),
        tokenStore: tokenStore,
        tokenCache: SessionTokenCache(),
      );

      await controller.restoreSession();

      expect(controller.status, AuthStatus.signedOut);
      expect(await tokenStore.read(), isNull);
    });
  });

  group('signOut', () {
    test('clears the local session even if the server call fails', () async {
      final InMemorySessionTokenStore tokenStore = InMemorySessionTokenStore();
      final AuthController controller = AuthController(
        repository: AuthRepository(
          apiClient: ApiClient(
            baseUrl: 'http://api.test',
            httpClient: MockClient(
              (http.Request request) async => json(<String, dynamic>{}, 500),
            ),
            sessionToken: SessionTokenCache(),
          ),
        ),
        tokenStore: tokenStore,
        tokenCache: SessionTokenCache(),
      );
      await tokenStore.write('active-token');

      await controller.signOut();

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.doctor, isNull);
      expect(await tokenStore.read(), isNull);
    });
  });

  test('AuthResult parses the token and expiry', () {
    final AuthResult result = AuthResult.fromJson(authBody());

    expect(result.accessToken, 'test-session-token');
    expect(result.doctor.name, 'Dr. Amara Osei');
    expect(result.expiresAt, DateTime.parse('2026-10-07T09:00:00Z'));
  });
}
