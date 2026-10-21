import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_core/neurosync_core.dart';
import 'package:neurosync_patient/features/home/presentation/home_screen.dart';

import '../../test_support.dart';

/// The home screen has to hold its words on a phone.
///
/// The three numbers, the plan card and the recent recordings all sit in the
/// same column, and a caption that will not fit is a caption the patient
/// cannot read. This is the check that they all fit.
void main() {
  for (final double width in <double>[320, 360, 393, 412]) {
    testWidgets('the home screen holds together at ${width.toInt()}px', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 2400);
      addTearDown(tester.view.reset);

      final PatientControllers controllers = controllersWith(
        (http.Request request) async => http.Response(
          '{"id":1,"title":"Daily motor check-in","status":"active",'
          '"items":[{"id":11,"position":0,"completed_today":0,'
          '"assessment":{"id":1,"slug":"finger_tapping",'
          '"title":"Finger Tapping",'
          '"description":"Tap as regularly as you can.",'
          '"instructions":"Tap the pad.","execution_type":"tap_task",'
          '"default_duration_seconds":30,"is_supported":true}}]}',
          200,
        ),
      );

      await tester.pumpWidget(
        patientScope(
          controllers: controllers,
          child: MaterialApp(
            theme: AppTheme.light(metrics: AppMetrics.compact),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing overflowed and nothing was laid out wrong.
      expect(tester.takeException(), isNull);

      // Every word the patient needs is shown in full.
      for (final String word in <String>[
        'Hi, there',
        'DAILY MOTOR CHECK-IN',
        'Finger Tapping',
        'Tap as regularly as you can.',
        'Begin test',
      ]) {
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(word),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"$word" does not fit',
        );
      }
    });
  }
}
