import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/intro/visuals/baseline_signal.dart';
import 'package:neurosync_core/neurosync_core.dart';

Widget wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
  );
}

void main() {
  testWidgets('draws one segment per chapter', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(BaselineSignal(count: 4, index: 1, onSelect: (int _) {})),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BaselineSignal),
        matching: find.byType(CustomPaint),
      ),
      findsNWidgets(4),
    );
  });

  testWidgets('announces the chapter in reading order',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(BaselineSignal(count: 4, index: 1, onSelect: (int _) {})),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(BaselineSignal)).label,
      'Chapter 2 of 4',
    );
    handle.dispose();
  });

  testWidgets('tapping an already read chapter returns to it',
      (WidgetTester tester) async {
    final List<int> selected = <int>[];
    await tester.pumpWidget(
      wrap(BaselineSignal(count: 4, index: 2, onSelect: selected.add)),
    );
    await tester.pumpAndSettle();

    final Rect signal = tester.getRect(find.byType(BaselineSignal));
    await tester
        .tapAt(Offset(signal.left + signal.width * 0.05, signal.center.dy));
    await tester.pumpAndSettle();

    expect(selected, <int>[0]);
  });

  testWidgets('tapping the current or a later chapter does nothing',
      (WidgetTester tester) async {
    final List<int> selected = <int>[];
    await tester.pumpWidget(
      wrap(BaselineSignal(count: 4, index: 1, onSelect: selected.add)),
    );
    await tester.pumpAndSettle();

    final Rect signal = tester.getRect(find.byType(BaselineSignal));
    await tester
        .tapAt(Offset(signal.left + signal.width * 0.55, signal.center.dy));
    await tester
        .tapAt(Offset(signal.right - signal.width * 0.03, signal.center.dy));
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
  });
}
