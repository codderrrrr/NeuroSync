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
import 'package:neurosync_patient/features/check_ins/state/check_in_controller.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';
import 'package:neurosync_patient/features/monitoring/data/monitoring_repository.dart';
import 'package:neurosync_patient/features/monitoring/state/monitoring_controller.dart';
import 'package:neurosync_patient/features/shell/presentation/main_shell.dart';

Widget wrapShell() {
  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    // Every list endpoint answers with an empty list, so the tabs settle.
    httpClient: MockClient(
      (http.Request request) async => http.Response('[]', 200),
    ),
    sessionToken: tokenCache,
  );

  return AppScope(
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
      home: const MainShell(),
    ),
  );
}

int? selectedTab(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index;

void main() {
  testWidgets('opens on the home tab with the account summary',
      (WidgetTester tester) async {
    // A tall viewport so the whole home list, including the log-out button,
    // is on screen at once.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrapShell());
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 0);
    expect(find.text('Hi, there'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    // The home tab no longer carries the doctor-linking module.
    expect(find.text('Add your doctor'), findsNothing);
  });

  testWidgets('check-ins live on their own tab', (WidgetTester tester) async {
    await tester.pumpWidget(wrapShell());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check-ins'));
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 1);
    expect(find.text('Record a check-in'), findsOneWidget);
    expect(find.text('No check-ins yet'), findsOneWidget);
  });

  testWidgets('doctor linking lives on its own tab',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrapShell());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Doctors'));
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 2);
    expect(find.text('Care team'), findsOneWidget);
    expect(find.text('Add your doctor'), findsOneWidget);
  });

  testWidgets('switching tabs returns to home with its state kept',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrapShell());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Doctors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 0);
    expect(find.text('Hi, there'), findsOneWidget);
  });
}
