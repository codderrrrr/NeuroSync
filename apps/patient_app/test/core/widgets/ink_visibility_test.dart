import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';
import 'package:neurosync_patient/core/widgets/floating_tab_bar.dart';
import 'package:neurosync_patient/core/widgets/soft_panel.dart';

/// Whether the ink of a press lands somewhere the patient can see.
///
/// An `InkWell` prints its splash into the ink layer of the nearest `Material`
/// above it. When that material is a bare wrapper around an opaque
/// `Container` - a panel, a bar, a track - the splash is painted over and the
/// press leaves no mark at all. The control still works; it just looks like
/// nothing happened, which for a patient with a tremor is the difference
/// between "it registered" and "did I miss it?".
///
/// The rule: the material the ink lands on is either opaque itself, or it sits
/// inside one that is. Either way the mark has a visible surface to show on.
///
/// The controls are pumped without a `Scaffold`, so the only materials in the
/// tree are the control's own. A `Scaffold` would put an opaque material
/// above everything and quietly pass a control that shows nothing.
void main() {
  /// The materials above [inkWell], nearest first.
  List<Material> materialsAbove(Finder inkWell) => find
      .ancestor(of: inkWell, matching: find.byType(Material))
      .evaluate()
      .map((Element element) => element.widget as Material)
      .toList();

  bool isOpaque(Material material) => (material.color?.a ?? 0) >= 1;

  void expectInkIsVisible(Finder inkWell) {
    final List<Material> materials = materialsAbove(inkWell);

    expect(
      materials,
      isNotEmpty,
      reason: 'An InkWell with no Material above it has nowhere to print.',
    );

    expect(
      isOpaque(materials.first) || materials.skip(1).any(isOpaque),
      isTrue,
      reason: 'The ink lands on a translucent material with no visible '
          'surface above it, so the press leaves no mark.',
    );
  }

  Future<void> pump(WidgetTester tester, Widget control) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(metrics: AppMetrics.compact),
        home: Center(
          child: SizedBox(width: 320, child: control),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a panel shows the mark of a press', (WidgetTester tester) async {
    await pump(
      tester,
      SoftPanel(
        onTap: () {},
        child: const Text('Sign out'),
      ),
    );

    expectInkIsVisible(find.byType(InkWell));
  });

  testWidgets('the two-way toggle shows the mark of a press',
      (WidgetTester tester) async {
    await pump(
      tester,
      SegmentedToggle(
        labels: const <String>['Tests', 'Check-ins'],
        selectedIndex: 0,
        onChanged: (int _) {},
      ),
    );

    // The chosen side is the one under the sliding capsule, so its mark is
    // the one that has to survive the capsule.
    expectInkIsVisible(
      find.ancestor(
        of: find.text('Tests'),
        matching: find.byType(InkWell),
      ),
    );
  });

  testWidgets('the tab bar shows the mark of a press on the chosen tab',
      (WidgetTester tester) async {
    await pump(
      tester,
      FloatingTabBar(
        destinations: const <TabDestination>[
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
        ],
        selectedIndex: 0,
        onSelected: (int _) {},
      ),
    );

    expectInkIsVisible(
      find.ancestor(
        of: find.text('Home'),
        matching: find.byType(InkWell),
      ),
    );
  });
}
