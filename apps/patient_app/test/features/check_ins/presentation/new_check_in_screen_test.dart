import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurosync_patient/app_scope.dart';
import 'package:neurosync_patient/core/network/api_client.dart';
import 'package:neurosync_patient/core/storage/session_token_store.dart';
import 'package:neurosync_patient/core/theme/app_theme.dart';
import 'package:neurosync_patient/features/auth/data/auth_repository.dart';
import 'package:neurosync_patient/features/auth/state/auth_controller.dart';
import 'package:neurosync_patient/features/check_ins/data/check_in_repository.dart';
import 'package:neurosync_patient/features/check_ins/presentation/new_check_in_screen.dart';
import 'package:neurosync_patient/features/check_ins/state/check_in_controller.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';

/// The check-in form on a route that can actually be popped, so the
/// save-and-return journey is exercised end to end.
///
/// The surface is a tall phone so the whole form (ratings, note, save) is on
/// one screen and the list never lazily drops a field out of the tree.
Future<void> pumpNewCheckIn(WidgetTester tester, MockClient mockClient) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1400);
  addTearDown(tester.view.reset);

  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: mockClient,
    sessionToken: tokenCache,
  );

  await tester.pumpWidget(
    AppScope(
      auth: AuthController(
        repository: AuthRepository(apiClient: apiClient),
        tokenStore: InMemorySessionTokenStore(),
        tokenCache: tokenCache,
      ),
      doctorLinks: DoctorLinkController(
        repository: DoctorLinkRepository(apiClient: apiClient),
      ),
      checkIns: CheckInController(
        repository: CheckInRepository(apiClient: apiClient),
      ),
      monitoring: MonitoringController(
        repository: MonitoringRepository(apiClient: apiClient),
      ),
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const NewCheckInScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'saving posts the chosen ratings and returns to the previous screen',
      (WidgetTester tester) async {
    late http.Request captured;
    await pumpNewCheckIn(
      tester,
      MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 4,
            'recorded_at': '2026-06-18T10:30:00Z',
            'tremor': 3,
            'stiffness': 0,
            'slowness': 0,
            'balance': 0,
            'note': 'worse after lunch',
            'created_at': '2026-06-18T10:30:00Z',
          }),
          201,
        );
      }),
    );

    // The first rating row is tremor; its dots read 0-4.
    await tester.tap(find.text('3').first);
    await tester.enterText(find.byType(TextFormField), 'worse after lunch');
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();

    expect(captured.url.path, '/check-ins');
    final Map<String, dynamic> body =
        jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['tremor'], 3);
    expect(body['stiffness'], 0);
    expect(body['slowness'], 0);
    expect(body['balance'], 0);
    expect(body['note'], 'worse after lunch');
    // The form popped back to the launcher route after saving.
    expect(find.text('Rate what you notice right now.'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a rejected save keeps the form and shows the API message',
      (WidgetTester tester) async {
    await pumpNewCheckIn(
      tester,
      MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'detail': 'recorded_at cannot be in the future.',
          }),
          422,
        ),
      ),
    );

    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();

    expect(
      find.text('recorded_at cannot be in the future.'),
      findsOneWidget,
    );
    expect(find.text('Rate what you notice right now.'), findsOneWidget);
  });
}
