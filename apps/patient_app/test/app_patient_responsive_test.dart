import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_patient/features/auth/presentation/splash_screen.dart';
import 'package:neurosync_patient/features/intro/onboarding_screen.dart';
import 'package:neurosync_patient/features/monitoring/models/session_result.dart';
import 'package:neurosync_patient/features/monitoring/presentation/session_result_screen.dart';
import 'package:neurosync_patient/features/shell/presentation/main_shell.dart';
import 'package:neurosync_core/neurosync_core.dart';

import 'test_support.dart';

/// A small phone, a normal phone and a tall phone.
const List<Size> _viewports = <Size>[
  Size(360, 640),
  Size(393, 852),
  Size(412, 915),
];

const String _patientJson =
    '{"id": 1, "email": "ada@example.com", "name": "Ada Lovelace", '
    '"created_at": "2026-01-01T10:00:00Z"}';

Map<String, dynamic> _planJson() => <String, dynamic>{
      'id': 1,
      'title': 'Daily motor check-in',
      'status': 'active',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 11,
          'position': 0,
          'completed_today': 0,
          'duration_seconds': 60,
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

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Widget _scope(Widget home, {Size? viewport, WidgetTester? tester}) {
  final PatientControllers controllers = controllersWith(
    (http.Request request) async {
      if (request.url.path == '/auth/me') {
        return http.Response(_patientJson, 200);
      }
      if (request.url.path == '/monitoring/plan') {
        return _json(_planJson());
      }
      if (request.url.path == '/monitoring/sessions') {
        return _json(<dynamic>[
          <String, dynamic>{
            'id': 31,
            'status': 'completed',
            'assessment': _planJson()['items'][0]['assessment'],
            'started_at': '2026-06-18T10:00:00Z',
            'completed_at': '2026-06-18T10:01:00Z',
            'result': <String, dynamic>{
              'quality': 'valid',
              'taps': <String, dynamic>{
                'total_taps': 61,
                'duration_ms': 60000,
                'mean_inter_tap_interval_ms': 980,
                'inter_tap_variability_ms': 120,
                'longest_pause_ms': 2400,
                'taps_per_second': 1.0,
              },
              'canvas': null,
            },
          }
        ]);
      }
      return _json(<dynamic>[]);
    },
    storedToken: 'token',
  );

  if (tester != null && viewport != null) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);
  }

  return patientScope(
    controllers: controllers,
    child: MaterialApp(theme: AppTheme.dark(), home: home),
  );
}

void main() {
  group('the signed-in shell holds together on every phone', () {
    for (final Size size in _viewports) {
      testWidgets(
          'all three tabs at ${size.width.toInt()}x${size.height.toInt()}',
          (WidgetTester tester) async {
        await tester.pumpWidget(
            _scope(const MainShell(), viewport: size, tester: tester));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Begin test'), findsOneWidget);
        // The bottom navigation and today's action both fit at every width.
        expect(find.byType(NavigationBar), findsOneWidget);

        await tester.tap(find.text('Check-ins'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Doctors'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('first-run screens hold together on every phone', () {
    for (final Size size in _viewports) {
      testWidgets('splash at ${size.width.toInt()}x${size.height.toInt()}',
          (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const SplashScreen()),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('NeuroSync'), findsOneWidget);
      });

      testWidgets('onboarding at ${size.width.toInt()}x${size.height.toInt()}',
          (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: OnboardingScreen(onFinished: () {}),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Continue'), findsOneWidget);
      });
    }
  });

  group('the session result fits its viewport', () {
    for (final Size size in _viewports) {
      testWidgets('result at ${size.width.toInt()}x${size.height.toInt()}',
          (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _scope(
            SessionResultScreen(
              assessmentTitle: 'Finger Tapping',
              completedAt: DateTime.parse('2026-06-18T10:01:00Z'),
              result: SessionResult.fromJson(<String, dynamic>{
                'quality': 'valid',
                'taps': <String, dynamic>{
                  'total_taps': 61,
                  'duration_ms': 60000,
                  'mean_inter_tap_interval_ms': 980,
                  'inter_tap_variability_ms': 120,
                  'longest_pause_ms': 2400,
                  'taps_per_second': 1.0,
                },
                'canvas': null,
              }),
              onDone: () {},
            ),
            tester: tester,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Session complete'), findsOneWidget);
        expect(find.text('TAPS RECORDED'), findsOneWidget);
        // The result is taller than a phone screen, so the primary action is
        // reached by scrolling rather than being pinned.
        await tester.scrollUntilVisible(find.text('Done'), 200);
        expect(find.text('Done'), findsOneWidget);
      });
    }
  });
}
