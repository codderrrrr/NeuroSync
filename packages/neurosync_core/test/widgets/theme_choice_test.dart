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
  testWidgets('offers light, dark and the system', (
    WidgetTester tester,
  ) async {
    ThemeMode chosen = ThemeMode.system;

    await tester.pumpWidget(
      wrap(
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return ThemeChoice(
              mode: chosen,
              onChanged: (ThemeMode mode) => setState(() => chosen = mode),
            );
          },
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
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return ThemeChoice(
              mode: chosen,
              onChanged: (ThemeMode mode) => setState(() => chosen = mode),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(chosen, ThemeMode.dark);
  });

  testWidgets('the current choice is marked as chosen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        child: ThemeChoice(
          mode: ThemeMode.dark,
          onChanged: (ThemeMode _) {},
        ),
      ),
    );

    final Semantics dark = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.label == 'Dark appearance',
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
}
