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
}) =>
    controllerWithStore(InMemorySessionTokenStore(storedToken), handler);

/// Builds an [AuthController] around an explicit [SessionTokenStore].
///
/// The API client and the controller must share one [SessionTokenCache], as
/// `main.dart` does: the controller writes the token into the cache and the
/// client reads it back to build the Authorization header. Two caches would
/// silently drop the Authorization header instead of failing loudly.
AuthController controllerWithStore(
  SessionTokenStore tokenStore,
  Future<http.Response> Function(http.Request) handler,
) {
  final SessionTokenCache tokenCache = SessionTokenCache();
  return AuthController(
    repository: AuthRepository(
      apiClient: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient(handler),
        sessionToken: tokenCache,
      ),
    ),
    tokenStore: tokenStore,
    tokenCache: tokenCache,
  );
}

/// A store that fails the way a platform keystore can: reading throws instead
/// of returning a token.
class _FailingSessionTokenStore implements SessionTokenStore {
  @override
  Future<String?> read() async => throw StateError('keystore unavailable');

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
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
        (http.Request request) async => json(
            <String, dynamic>{'detail': 'Invalid email or password.'}, 401),
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
      final InMemorySessionTokenStore tokenStore =
          InMemorySessionTokenStore('stale-token');
      final AuthController controller = controllerWithStore(
        tokenStore,
        (http.Request request) async =>
            json(<String, dynamic>{'detail': 'Not authenticated.'}, 401),
      );

      await controller.restoreSession();

      expect(controller.status, AuthStatus.signedOut);
      expect(await tokenStore.read(), isNull);
    });

    test('lands signed out when secure storage cannot be read', () async {
      // Regression: only ApiException used to be caught, so a keystore read
      // failure escaped restoreSession with the status still `checking`.
      // _RootView renders `checking` as the splash screen, so the app was
      // stuck on splash forever with no way to sign in.
      final AuthController controller = controllerWithStore(
        _FailingSessionTokenStore(),
        (http.Request request) async => json(doctorJson()),
      );

      await controller.restoreSession();

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.doctor, isNull);
    });

    test('lands signed out when the stored session cannot be parsed', () async {
      // Regression: a response missing a field the model requires throws a
      // TypeError, not an ApiException, which used to skip the status update
      // and hang the app on the splash screen.
      final AuthController controller = controllerWithStore(
        InMemorySessionTokenStore('stored-token'),
        (http.Request request) async => json(<String, dynamic>{'id': 3}),
      );

      await controller.restoreSession();

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.doctor, isNull);
    });
  });

  group('signOut', () {
    test('clears the local session even if the server call fails', () async {
      final InMemorySessionTokenStore tokenStore =
          InMemorySessionTokenStore('active-token');
      final AuthController controller = controllerWithStore(
        tokenStore,
        (http.Request request) async => json(<String, dynamic>{}, 500),
      );

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
