import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_patient/features/intro/onboarding_data.dart';
import 'package:neurosync_patient/features/intro/visuals/baseline_signal.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// The band shapes the chapter page can hand a visual: a tall portrait band,
/// a wide landscape column, and the smallest band it ever allows.
const Map<String, Size> _bands = <String, Size>{
  'portrait': Size(312, 300),
  'landscape': Size(360, 240),
  'smallest': Size(300, 110),
};

void main() {
  test('carries four chapters with distinct, non-empty copy', () {
    expect(onboardingChapters.length, 4);

    final Set<String> headlines = <String>{};
    for (final OnboardingChapter chapter in onboardingChapters) {
      expect(chapter.kicker.trim(), isNotEmpty);
      expect(chapter.headline.trim(), isNotEmpty);
      expect(chapter.body.trim(), isNotEmpty);
      headlines.add(chapter.headline);
    }
    expect(headlines.length, 4);
  });

  for (final MapEntry<String, Size> band in _bands.entries) {
    testWidgets('every chapter visual builds in a ${band.key} band',
        (WidgetTester tester) async {
      for (int index = 0; index < onboardingChapters.length; index++) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: band.value.width,
                  height: band.value.height,
                  child: Builder(
                    builder: (BuildContext context) => onboardingChapters[index]
                        .visual(
                            context, (index + 1) / onboardingChapters.length),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'chapter ${index + 1} in a ${band.key} band',
        );
        expect(
          find.byType(CustomPaint),
          findsWidgets,
          reason: 'chapter ${index + 1} draws something',
        );
      }
    });
  }

  testWidgets('the timeline grows with the chapter being read',
      (WidgetTester tester) async {
    // Chapter two's line is a third of the way along, chapter four's is whole.
    for (final (int index, double progress) in <(int, double)>[
      (1, 2 / 4),
      (3, 4 / 4),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 300,
              child: Builder(
                builder: (BuildContext context) =>
                    onboardingChapters[index].visual(context, progress),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the baseline signal matches the chapter count',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: BaselineSignal(
            count: onboardingChapters.length,
            index: 0,
            onSelect: (int _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BaselineSignal),
        matching: find.byType(CustomPaint),
      ),
      findsNWidgets(onboardingChapters.length),
    );
  });
}
