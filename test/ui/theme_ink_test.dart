import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zic/ui/theme.dart';

/// Regression tests for the theme-aware surface helpers (`ZInk.card` /
/// `ZInk.surface`) introduced to fix dark-on-dark text in light mode.
void main() {
  Future<void> pumpInk(
    WidgetTester tester,
    ThemeData theme,
    void Function(BuildContext context) check,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            check(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  testWidgets('light theme resolves card/surface to light values',
      (tester) async {
    await pumpInk(tester, buildLightTheme(), (context) {
      expect(Theme.of(context).brightness, Brightness.light);
      expect(ZInk.card(context), ZColors.lightCard);
      expect(ZInk.surface(context), ZColors.lightBackground);
      expect(ZInk.tile(context), ZColors.lightSecondary);
    });
  });

  testWidgets('dark theme keeps the official dark values', (tester) async {
    await pumpInk(tester, buildDarkTheme(), (context) {
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(ZInk.card(context), ZColors.darkCard);
      expect(ZInk.surface(context), ZColors.darkBackground);
      expect(ZInk.tile(context), ZColors.darkSecondary);
    });
  });
}
