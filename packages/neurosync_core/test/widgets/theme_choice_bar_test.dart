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

    testWidgets('the chosen portion is filled, not a sliver of it', (
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
      await tester.pumpAndSettle();

      // The raised card that marks the choice has to cover the whole of the
      // portion it is over. A sliver of a portion reads as a stray mark, and
      // the patient cannot tell which mood is chosen.
      final Finder thumb = find.byWidgetPredicate(
        (Widget widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).boxShadow != null,
      );
      expect(thumb, findsOneWidget);

      final Rect card = tester.getRect(thumb);
      final double chosenCentre = tester.getCenter(find.text('Dark')).dx;
      final double lightCentre = tester.getCenter(find.text('Light')).dx;
      final double darkCentre = tester.getCenter(find.text('Dark')).dx;
      final double autoCentre = tester.getCenter(find.text('Auto')).dx;

      // As wide as one portion, less the hairline of gutter either side of
      // the raised card. A sliver - a ninth of the portion, say - would be a
      // stray mark rather than a choice.
      final double portion = darkCentre - lightCentre;
      expect(card.width, greaterThan(portion * 0.9));
      expect(card.width, lessThanOrEqualTo(portion));
      // And centred over the choice.
      expect(card.center.dx, moreOrLessEquals(chosenCentre, epsilon: 2));
      // The three portions are the same width, so the thumb fills one of them.
      expect(autoCentre - darkCentre, moreOrLessEquals(portion, epsilon: 1));
    });
    testWidgets('the thumb travels to the whole of the next portion', (
      WidgetTester tester,
    ) async {
      ThemeMode chosen = ThemeMode.system;

      Future<void> pump() => tester.pumpWidget(
            wrap(
              child: ThemeChoiceBar(
                mode: chosen,
                onChanged: (ThemeMode mode) => chosen = mode,
              ),
            ),
          );

      await pump();
      await tester.pumpAndSettle();

      final Finder thumb = find.byWidgetPredicate(
        (Widget widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).boxShadow != null,
      );

      final double lightCentre = tester.getCenter(find.text('Light')).dx;
      final double darkCentre = tester.getCenter(find.text('Dark')).dx;

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(chosen, ThemeMode.light);

      // The app rebuilds the bar with the new mood, and the thumb travels
      // to the Light portion, still a whole portion wide.
      await pump();
      await tester.pumpAndSettle();

      final Rect moved = tester.getRect(thumb);
      expect(moved.center.dx, moreOrLessEquals(lightCentre, epsilon: 2));
      expect(moved.width, greaterThan((darkCentre - lightCentre) * 0.9));
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
