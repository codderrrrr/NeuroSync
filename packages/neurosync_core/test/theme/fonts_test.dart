import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurosync_core/neurosync_core.dart';

/// The fonts are bundled, not fetched, so they are present on first frame.
///
/// A runtime fetch would mean the app reflows once the download lands, and
/// that the patient's data has already left the device to get a typeface.
void main() {
  testWidgets('the bundled families load and carry their weights', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Column(
            children: <Widget>[
              Text('Display',
                  style: TextStyle(fontFamily: 'Plus Jakarta Sans')),
              Text('Body', style: TextStyle(fontFamily: 'Inter')),
              Text(
                'SemiBold body',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // The families resolve, so the text lays out in the bundled face rather
    // than the platform fallback.
    for (final String family in <String>['Inter', 'Plus Jakarta Sans']) {
      expect(
        tester
            .widget<Text>(find.text(family == 'Inter' ? 'Body' : 'Display'))
            .style
            ?.fontFamily,
        family,
      );
    }

    expect(tester.takeException(), isNull);
  });
}
