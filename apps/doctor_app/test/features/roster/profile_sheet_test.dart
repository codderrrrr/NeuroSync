import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/app/portal_shell.dart';
import 'package:neurosync_doctor/features/auth/state/auth_controller.dart';
import 'package:neurosync_doctor/features/roster/presentation/profile_sheet.dart';

import '../../test_support.dart';

/// Clipboard writes go to a platform channel that has no binding under
/// `flutter test`; without this the sheet's copy button never completes.
void _mockClipboard() {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  messenger.setMockMethodCallHandler(SystemChannels.platform,
      (MethodCall call) async {
    if (call.method == 'Clipboard.getData') {
      return <String, dynamic>{'text': kDoctorCode};
    }
    return null;
  });
}

void _noop() {}

Future<http.Response> _dashboardHandler(http.Request request) async {
  if (request.url.path == '/doctor/patient-links/pending' ||
      request.url.path == '/doctor/patients') {
    return json(<dynamic>[]);
  }
  throw StateError('unexpected request: ${request.method} ${request.url.path}');
}

void main() {
  setUp(_mockClipboard);

  /// Pumps the real portal shell, then opens the profile sheet the way the
  /// shell's account row does. These tests are about the sheet itself, so the
  /// shell's callback is driven directly rather than through the rail.
  Future<AuthController> openProfileSheet(
    WidgetTester tester, {
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    final AuthController auth = await pumpDoctorScreen(
      tester,
      home: const PortalShell(
        doctorName: 'Dr. Amara Osei',
        onOpenProfile: _noop,
        onSignOut: _noop,
      ),
      handler: handler ?? _dashboardHandler,
    );
    showProfileSheet(tester.element(find.byType(PortalShell)));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('the profile sheet reveals the doctor link code',
      (WidgetTester tester) async {
    await openProfileSheet(tester);

    expect(find.text('YOUR LINK CODE'), findsOneWidget);
    expect(find.text(kDoctorCode), findsOneWidget);
  });

  testWidgets('copying the code confirms it in a snackbar',
      (WidgetTester tester) async {
    await openProfileSheet(tester);

    await tester.tap(find.byTooltip('Copy code'));
    // Bounded pumps: the copy awaits a platform channel, so pumpAndSettle
    // would wait on a frame that never arrives.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Link code copied.'), findsOneWidget);
  });

  testWidgets('signing out closes the sheet and returns to login',
      (WidgetTester tester) async {
    final AuthController auth = await openProfileSheet(
      tester,
      handler: (http.Request request) async {
        if (request.url.path == '/doctor/auth/logout') {
          return http.Response('', 204);
        }
        return _dashboardHandler(request);
      },
    );

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('YOUR LINK CODE'), findsNothing);
    expect(auth.status, AuthStatus.signedOut);
  });
}
