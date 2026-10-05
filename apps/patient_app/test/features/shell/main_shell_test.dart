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
import 'package:neurosync_patient/features/check_ins/state/check_in_controller.dart';
import 'package:neurosync_patient/features/doctor_links/data/doctor_link_repository.dart';
import 'package:neurosync_patient/features/doctor_links/state/doctor_link_controller.dart';
import 'package:neurosync_patient/features/medication/data/medication_repository.dart';
import 'package:neurosync_patient/features/medication/state/medication_controller.dart';
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
    medications: MedicationController(
      repository: MedicationRepository(apiClient: apiClient),
    ),
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const MainShell(),
    ),
  );
}

/// An API whose answers can be changed while the shell is running, so a test
/// can play the doctor acting on the other side of the connection.
class ScriptedApi {
  /// The plan the next read returns, or null for "no plan yet".
  Map<String, dynamic>? plan;
  List<Map<String, dynamic>> links = <Map<String, dynamic>>[];

  int planReads = 0;
  int linkReads = 0;

  Future<http.Response> call(http.Request request) async {
    switch (request.url.path) {
      case '/monitoring/plan':
        planReads++;
        final Map<String, dynamic>? body = plan;
        if (body == null) {
          return http.Response(
            jsonEncode(<String, String>{'detail': 'No plan.'}),
            404,
          );
        }
        return http.Response(jsonEncode(body), 200);
      case '/doctor-links':
        linkReads++;
        return http.Response(jsonEncode(links), 200);
      default:
        return http.Response('[]', 200);
    }
  }
}

Map<String, dynamic> planJson() => <String, dynamic>{
      'id': 1,
      'title': 'Daily motor check-in',
      'status': 'active',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 11,
          'position': 0,
          'completed_today': 0,
          'assessment': <String, dynamic>{
            'id': 1,
            'slug': 'finger_tapping',
            'title': 'Finger Tapping',
            'description': 'Tap as regularly as you can.',
            'instructions': 'Tap the pad at a steady pace.',
            'execution_type': 'tap_task',
            'default_duration_seconds': 30,
            'is_supported': true,
          },
        },
      ],
    };

Map<String, dynamic> pendingLinkJson() => <String, dynamic>{
      'doctor_id': 7,
      'status': 'pending',
      'created_at': '2026-06-18T10:00:00Z',
    };

/// A shell wired to [api], for tests that change the answers mid-run.
Widget wrapShellWith(ScriptedApi api) {
  final SessionTokenCache tokenCache = SessionTokenCache();
  final ApiClient apiClient = ApiClient(
    baseUrl: 'http://api.test',
    httpClient: MockClient(api.call),
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
    medications: MedicationController(
      repository: MedicationRepository(apiClient: apiClient),
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

  testWidgets('an exercise assigned while the app is open shows up by itself',
      (WidgetTester tester) async {
    // The complaint this covers: a doctor assigns something, and the patient
    // only finds out by killing and reopening the app.
    final ScriptedApi api = ScriptedApi();
    await tester.pumpWidget(wrapShellWith(api));
    await tester.pumpAndSettle();

    // Nothing assigned yet.
    expect(find.text('Finger Tapping'), findsNothing);

    // The doctor assigns one on their own machine.
    api.plan = planJson();

    // The shell re-reads on its own timer, with no patient action.
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();

    expect(api.planReads, greaterThan(1));
    expect(find.text('Finger Tapping'), findsWidgets);
  });

  testWidgets('a link the doctor accepts shows up by itself',
      (WidgetTester tester) async {
    final ScriptedApi api = ScriptedApi();
    await tester.pumpWidget(wrapShellWith(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Doctors'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pending'), findsNothing);

    // The doctor accepts the patient's request from their side.
    api.links = <Map<String, dynamic>>[pendingLinkJson()];

    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();

    expect(api.linkReads, greaterThan(1));
  });

  testWidgets('coming back to the foreground re-reads immediately',
      (WidgetTester tester) async {
    // A patient who backgrounds the app and comes back should not wait out the
    // rest of the poll interval.
    final ScriptedApi api = ScriptedApi();
    await tester.pumpWidget(wrapShellWith(api));
    await tester.pumpAndSettle();

    final int readsBeforeLeaving = api.planReads;
    api.plan = planJson();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.planReads, greaterThan(readsBeforeLeaving));
    expect(find.text('Finger Tapping'), findsWidgets);
  });

  testWidgets('switching tabs re-reads rather than replaying stale data',
      (WidgetTester tester) async {
    final ScriptedApi api = ScriptedApi();
    await tester.pumpWidget(wrapShellWith(api));
    await tester.pumpAndSettle();

    final int readsBefore = api.planReads;
    api.plan = planJson();

    await tester.tap(find.text('Doctors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(api.planReads, greaterThan(readsBefore));
    expect(find.text('Finger Tapping'), findsWidgets);
  });
}
