import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/state/app_kv.dart';
import 'package:zic/state/device_store.dart';
import 'package:zic/ui/about_page.dart';
import 'package:zic/ui/settings_page.dart';
import 'package:zic/ui/theme.dart';
import 'package:zic/ui/ui_settings.dart';
import 'package:zic/ui/usage_stats_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // AppKv remembers the first open for the whole isolate. A settings
    // test can leave that future unfinished, and the next load waits on it.
    AppKv.instance.debugReset();
    SharedPreferences.setMockInitialValues({});
  });

  Widget host(Widget page, UiSettings ui) => MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        builder: (context, child) =>
            UiSettingsProvider(settings: ui, child: child!),
        home: page,
      );

  group('SettingsPage', () {
    testWidgets('theme segmented control switches mode',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore();
      final theme = ThemeController();
      final ui = UiSettings();
      await tester.pumpWidget(
          host(SettingsPage(store: store, theme: theme, ui: ui), ui));
      await tester.pumpAndSettle();

      expect(theme.mode, ThemeMode.system); // Zic default: follow the OS
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(theme.mode, ThemeMode.light);
    });

    testWidgets('native list switch toggles the setting',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore();
      final theme = ThemeController();
      final ui = UiSettings();
      await tester.pumpWidget(
          host(SettingsPage(store: store, theme: theme, ui: ui), ui));
      await tester.pumpAndSettle();

      expect(ui.nativeListEnabled, isTrue);
      await tester
          .tap(find.widgetWithText(SwitchListTile, '原生任务列表'));
      await tester.pumpAndSettle();
      expect(ui.nativeListEnabled, isFalse);
    });

    testWidgets('notification switches toggle master and channels',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore();
      final theme = ThemeController();
      final ui = UiSettings();
      await tester.pumpWidget(
          host(SettingsPage(store: store, theme: theme, ui: ui), ui));
      await tester.pumpAndSettle();

      // Channel rows are visible while the master switch is on (the
      // account section above may require scrolling on small viewports).
      await tester.scrollUntilVisible(
          find.text('自动化结果'), 120,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('任务事件'), findsOneWidget);
      expect(find.text('闲时事件'), findsOneWidget);
      expect(find.text('自动化结果'), findsOneWidget);

      await tester.scrollUntilVisible(
          find.widgetWithText(SwitchListTile, '任务事件'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester
          .tap(find.widgetWithText(SwitchListTile, '任务事件'));
      await tester.pumpAndSettle();
      expect(ui.notifyTasksEnabled, isFalse);
      expect(ui.notificationsEnabled, isTrue);

      // Master off hides the channel rows.
      await tester.scrollUntilVisible(
          find.widgetWithText(SwitchListTile, '通知'), -120,
          scrollable: find.byType(Scrollable).first);
      await tester
          .tap(find.widgetWithText(SwitchListTile, '通知'));
      await tester.pumpAndSettle();
      expect(ui.notificationsEnabled, isFalse);
      expect(find.text('任务事件'), findsNothing);
    });

    testWidgets('language switches texts live', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore();
      final theme = ThemeController();
      final ui = UiSettings();
      await tester.pumpWidget(
          host(SettingsPage(store: store, theme: theme, ui: ui), ui));
      await tester.pumpAndSettle();

      expect(find.text('外观'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(ui.locale, 'en-US');
    });
  });

  group('UsageStatsPage', () {
    testWidgets('shows summary and per-device stats',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore();
      await store.load();
      final d = await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1&name=work-pc');
      await store.touch(d.id);
      await store.touch(d.id);

      final ui = UiSettings();
      await tester.pumpWidget(
          host(UsageStatsPage(store: store, ui: ui), ui));
      await tester.pumpAndSettle();

      expect(find.text('work-pc'), findsOneWidget);
      expect(find.text('2 次'), findsOneWidget);
      expect(find.text('设备数'), findsOneWidget);
    });

    testWidgets('empty list says the counts stay on the phone',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore();
      await store.load();
      final ui = UiSettings();
      await tester.pumpWidget(host(UsageStatsPage(store: store, ui: ui), ui));
      await tester.pumpAndSettle();

      expect(find.textContaining('只留在本机'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
    });
  });

  group('AboutPage', () {
    testWidgets('privacy, rights, and notices open in the app',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final ui = UiSettings();
      await tester.pumpWidget(host(const AboutPage(), ui));
      await tester.pumpAndSettle();

      expect(find.text('GitHub 主页'), findsOneWidget);
      expect(find.text('博客'), findsOneWidget);
      expect(find.text('vicyi.com'), findsOneWidget);
      expect(find.text('支持 Android 8.0 及以上'), findsOneWidget);

      await tester.tap(find.text('隐私政策'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不会发给开发者'), findsOneWidget);
      expect(find.textContaining('api.github.com'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('权利声明'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保留所有权利'), findsWidgets);
      expect(find.textContaining('并不收回这些许可'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('开源致谢'), 200);
      await tester.tap(find.text('开源致谢'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ZLinker'), findsWidgets);
      expect(find.text('flutter_secure_storage'), findsNothing);
      expect(find.textContaining('MIT'), findsWidgets);
    });
  });
}
