import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrap({required Widget child, double width = 900}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('lays the cells out in columns', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        child: BentoGrid(
          columns: 2,
          cells: <Widget>[
            for (final String label in <String>['a', 'b', 'c', 'd'])
              BentoCell(child: Text(label)),
          ],
        ),
      ),
    );

    // Two across: a and b share a row, c and d share the next.
    final double a = tester.getTopLeft(find.text('a')).dy;
    final double b = tester.getTopLeft(find.text('b')).dy;
    final double c = tester.getTopLeft(find.text('c')).dy;
    expect(b, a);
    expect(c, greaterThan(a));
  });

  testWidgets('becomes one column when there is no room for two', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        width: 320,
        child: BentoGrid(
          columns: 2,
          cells: <Widget>[
            for (final String label in <String>['a', 'b'])
              BentoCell(child: Text(label)),
          ],
        ),
      ),
    );

    final double a = tester.getTopLeft(find.text('a')).dy;
    final double b = tester.getTopLeft(find.text('b')).dy;
    expect(b, greaterThan(a));
  });

  testWidgets('a cell carries a label and a value', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        child: const BentoCell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              BentoLabel('Exercises'),
              SizedBox(height: 8),
              BentoStat(value: '3', caption: 'exercises assigned'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('EXERCISES'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('exercises assigned'), findsOneWidget);
  });

  testWidgets('a cell with a signal is marked with it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        child: BentoCell(
          accent: const Color(0xFFB3261E),
          child: const Text('flagged'),
        ),
      ),
    );

    expect(find.text('flagged'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
