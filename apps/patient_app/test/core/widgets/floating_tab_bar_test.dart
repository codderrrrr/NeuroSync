import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/core/widgets/floating_tab_bar.dart';

const List<TabDestination> _destinations = <TabDestination>[
  TabDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
  ),
  TabDestination(
    icon: Icons.medication_outlined,
    selectedIcon: Icons.medication_rounded,
    label: 'Medicine',
  ),
  TabDestination(
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
    label: 'Tests',
  ),
  TabDestination(
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    label: 'Doctors',
  ),
  TabDestination(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: 'Account',
  ),
];

Widget wrap({
  required Widget child,
  double width = 400,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every destination keeps its label', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        child: FloatingTabBar(
          destinations: _destinations,
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );

    // Five icons without words would be a puzzle for the person using the
    // app, so every one of them is named.
    for (final TabDestination destination in _destinations) {
      expect(find.text(destination.label), findsOneWidget);
    }
  });

  testWidgets('choosing a destination reports it', (WidgetTester tester) async {
    int chosen = 0;
    await tester.pumpWidget(
      wrap(
        child: FloatingTabBar(
          destinations: _destinations,
          selectedIndex: 0,
          onSelected: (int index) => chosen = index,
        ),
      ),
    );

    await tester.tap(find.text('Tests'));
    await tester.pumpAndSettle();

    expect(chosen, 2);
  });

  testWidgets('the chosen one is marked as chosen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        child: FloatingTabBar(
          destinations: _destinations,
          selectedIndex: 3,
          onSelected: (_) {},
        ),
      ),
    );

    final Semantics doctors = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.label == 'Doctors',
      ),
    );
    expect(doctors.properties.selected, isTrue);

    final Semantics home = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.label == 'Home',
      ),
    );
    expect(home.properties.selected, isFalse);
  });

  testWidgets('it fits a narrow phone without overflowing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        width: 320,
        child: FloatingTabBar(
          destinations: _destinations,
          selectedIndex: 1,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
