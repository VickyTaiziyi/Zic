import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/main.dart';
import 'package:zic/state/app_kv.dart';
import 'package:zic/state/device_session.dart';
import 'package:zic/state/device_store.dart';
import 'package:zic/state/scheduled_store.dart';
import 'package:zic/ui/devices_page.dart';
import 'package:zic/ui/theme.dart';
import 'package:zic/ui/ui_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppKv.instance.debugReset();
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(DevicesPage page) => MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        builder: (context, child) =>
            UiSettingsProvider(settings: UiSettings(), child: child!),
        home: page,
      );

  testWidgets('DevicesPage shows empty state with no devices',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    final theme = ThemeController();
    final ui = UiSettings();
    final hub = DeviceSessionHub(nativeListEnabled: () => ui.nativeListEnabled);
    await tester.pumpWidget(wrap(DevicesPage(
      store: store,
      theme: theme,
      ui: ui,
      hub: hub,
      scheduled: ScheduledStore(),
    )));
    await tester.pumpAndSettle();

    // Zic home: brand header title + empty state with scan/paste actions.
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('还没有设备'), findsOneWidget);
    expect(find.text('扫码添加'), findsOneWidget);
    expect(find.text('粘贴链接添加'), findsOneWidget);
  });

  testWidgets('DevicesPage renders a device card',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    await store.load();
    await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=abc&hash=xyz&t=123&mid=m1&name=dev-alpha&app_version=3.8.1');

    final theme = ThemeController();
    final ui = UiSettings();
    final hub = DeviceSessionHub(nativeListEnabled: () => false);
    await tester.pumpWidget(wrap(DevicesPage(
      store: store,
      theme: theme,
      ui: ui,
      hub: hub,
      scheduled: ScheduledStore(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('dev-alpha'), findsOneWidget);
    // Status and host share one caption line in the Zic card anatomy.
    expect(find.textContaining('zcode.z.ai'), findsWidgets);
    // No native connection is attempted with the switch off.
    expect(find.textContaining('离线'), findsOneWidget);
  });

  testWidgets('App boots', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZicApp());
    await tester.pumpAndSettle();
    expect(find.text('设备'), findsOneWidget);
  });
}
