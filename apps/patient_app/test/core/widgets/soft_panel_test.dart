import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/core/widgets/soft_panel.dart';

Widget wrap({required Widget child}) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('a stat shows its number and what the number means', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        child: const StatTile(
          value: '3',
          caption: 'tests done today',
          icon: Icons.timelapse_outlined,
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.text('tests done today'), findsOneWidget);
    expect(find.byIcon(Icons.timelapse_outlined), findsOneWidget);
  });

  testWidgets('a stat that answers to a tap reports it', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      wrap(
        child: StatTile(
          value: 'Done',
          caption: "today's test",
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('a panel with a signal is marked with it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        child: SoftPanel(
          accent: const Color(0xFFB3261E),
          child: const Text('flagged'),
        ),
      ),
    );

    expect(find.text('flagged'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a state pill shows its label', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        child: StatePill(
          label: 'SIGNED IN',
          color: const Color(0xFF2D784C),
          tint: const Color(0x1A2D784C),
        ),
      ),
    );

    expect(find.text('SIGNED IN'), findsOneWidget);
  });

  testWidgets('a segmented toggle reports the choice', (
    WidgetTester tester,
  ) async {
    int chosen = 0;
    await tester.pumpWidget(
      wrap(
        child: SegmentedToggle(
          labels: const <String>['Tests', 'Check-ins'],
          selectedIndex: 0,
          onChanged: (int index) => chosen = index,
        ),
      ),
    );

    expect(find.text('Tests'), findsOneWidget);
    expect(find.text('Check-ins'), findsOneWidget);

    await tester.tap(find.text('Check-ins'));
    await tester.pumpAndSettle();

    expect(chosen, 1);
  });
}
