import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/ui/ui_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UiSettings persistence', () {
    test('locale and nativeListEnabled round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final s = UiSettings();
      await s.load();
      expect(s.locale, 'zh-CN');
      expect(s.nativeListEnabled, isTrue);

      await s.setLocale('en-US');
      await s.setNativeListEnabled(false);

      final s2 = UiSettings();
      await s2.load();
      expect(s2.locale, 'en-US');
      expect(s2.nativeListEnabled, isFalse);
    });
  });

  group('tr lookup', () {
    Widget host(UiSettings settings) => UiSettingsProvider(
          settings: settings,
          child: Builder(builder: (context) => const SizedBox()),
        );

    testWidgets('zh table by default, en when locale switches',
        (WidgetTester tester) async {
      final s = UiSettings();
      await tester.pumpWidget(host(s));
      final ctx = tester.element(find.byType(SizedBox));
      expect(tr(ctx, 'status.online'), '在线');

      s.locale = 'en-US';
      await tester.pump();
      expect(tr(ctx, 'status.online'), 'Online');
    });

    testWidgets('unknown key falls back to itself', (WidgetTester tester) async {
      final s = UiSettings();
      await tester.pumpWidget(host(s));
      final ctx = tester.element(find.byType(SizedBox));
      expect(tr(ctx, 'no.such.key'), 'no.such.key');
    });

    testWidgets('trP substitutes positional args', (WidgetTester tester) async {
      final s = UiSettings();
      await tester.pumpWidget(host(s));
      final ctx = tester.element(find.byType(SizedBox));
      expect(trP(ctx, 'devices.import.done', ['2']), '已导入 2 台设备');
    });
  });
}
