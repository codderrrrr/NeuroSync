import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrap({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('the mood bar', () {
    testWidgets('offers light, dark and the system', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          child: ThemeChoiceBar(
            mode: ThemeMode.system,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('choosing one reports it', (WidgetTester tester) async {
      ThemeMode chosen = ThemeMode.system;
      await tester.pumpWidget(
        wrap(
          child: ThemeChoiceBar(
            mode: ThemeMode.system,
            onChanged: (ThemeMode mode) => chosen = mode,
          ),
        ),
      );

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(chosen, ThemeMode.dark);
    });

    testWidgets('the chosen one is marked as chosen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          child: ThemeChoiceBar(
            mode: ThemeMode.dark,
            onChanged: (_) {},
          ),
        ),
      );

      final Semantics dark = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics &&
              widget.properties.label == 'Dark appearance',
        ),
      );
      expect(dark.properties.selected, isTrue);

      final Semantics light = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics &&
              widget.properties.label == 'Light appearance',
        ),
      );
      expect(light.properties.selected, isFalse);
    });

    testWidgets('it is one bar, not three stacked buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          child: ThemeChoiceBar(
            mode: ThemeMode.system,
            onChanged: (_) {},
          ),
        ),
      );

      // The three choices sit side by side on one row.
      final double light = tester.getCenter(find.text('Light')).dy;
      final double dark = tester.getCenter(find.text('Dark')).dy;
      final double auto = tester.getCenter(find.text('Auto')).dy;
      expect(light, dark);
      expect(dark, auto);
    });
  });

  group('the quiet loader', () {
    testWidgets('it shows and announces itself', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(child: const CalmLoader()));

      expect(find.byType(CalmLoader), findsOneWidget);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the reveal', () {
    testWidgets('it arrives rather than appearing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(child: const Reveal(child: Text('arrived'))),
      );

      // It starts out of place and settles.
      await tester.pump();
      expect(find.text('arrived'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('arrived'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the empty note', () {
    testWidgets('it says what is missing and what to do', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          child: const EmptyNote(
            icon: Icons.insights_outlined,
            title: 'No recordings yet',
            message: 'Your first test will appear here.',
          ),
        ),
      );

      expect(find.text('No recordings yet'), findsOneWidget);
      expect(find.text('Your first test will appear here.'), findsOneWidget);
      expect(find.byIcon(Icons.insights_outlined), findsOneWidget);
    });
  });
}
