import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrap({required Widget child, bool reduceMotion = false}) {
  return MaterialApp(
    home: Builder(
      builder: (BuildContext context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

double currentScale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

void main() {
  testWidgets('sinks while it is held and recovers on release',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(child: const TactileButton(enabled: true, child: Text('Continue'))),
    );

    expect(currentScale(tester), 1);

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(currentScale(tester), lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(currentScale(tester), 1);
  });

  testWidgets('sinks far enough to see through a tremor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(child: const TactileButton(enabled: true, child: Text('Continue'))),
    );

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump(const Duration(milliseconds: 300));

    // A 1.5% change is invisible to a hand that is not steady.
    expect(currentScale(tester), lessThanOrEqualTo(0.96));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('drops the motion when the system asks for reduced animation',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        reduceMotion: true,
        child: const TactileButton(enabled: true, child: Text('Continue')),
      ),
    );

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump(const Duration(milliseconds: 150));

    expect(currentScale(tester), 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('reports one tick for a press that was held', (
    WidgetTester tester,
  ) async {
    int ticks = 0;
    await tester.pumpWidget(
      wrap(
        child: TactileButton(
          enabled: true,
          onHaptic: () async => ticks++,
          child: const Text('Continue'),
        ),
      ),
    );

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(ticks, 1);
  });

  testWidgets('stays silent for a graze that was not a press', (
    WidgetTester tester,
  ) async {
    int ticks = 0;
    await tester.pumpWidget(
      wrap(
        child: TactileButton(
          enabled: true,
          onHaptic: () async => ticks++,
          child: const Text('Continue'),
        ),
      ),
    );

    // A brush of the finger: down and up inside the threshold.
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(ticks, 0);
  });

  testWidgets('stays silent when it cannot be used', (
    WidgetTester tester,
  ) async {
    int ticks = 0;
    await tester.pumpWidget(
      wrap(
        child: TactileButton(
          enabled: false,
          onHaptic: () async => ticks++,
          child: const Text('Continue'),
        ),
      ),
    );

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(ticks, 0);
    expect(currentScale(tester), 1);
  });
}
