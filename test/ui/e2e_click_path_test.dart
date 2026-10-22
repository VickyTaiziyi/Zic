import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/state/device_session.dart';
import 'package:zic/state/device_store.dart';
import 'package:zic/state/scheduled_store.dart';
import 'package:zic/ui/chat/chat_page.dart';
import 'package:zic/ui/devices_page.dart';
import 'package:zic/ui/task_list_page.dart';
import 'package:zic/ui/theme.dart';
import 'package:zic/ui/ui_settings.dart';

import '../helpers/fake_device_session.dart';

/// End-to-end click path against the real widget tree with a FakeDeviceSession
/// installed in the hub: devices → task list → task chat → back → back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(DeviceStore, DeviceSessionHub, FakeDeviceSession)> setup(
      WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    await store.load();
    await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=abc&hash=xyz&t=123&mid=m1&name=dev-alpha&app_version=3.8.1');
    final device = store.devices.single;
    final session = FakeDeviceSession(
      deviceId: device.id,
      params: device.params!,
      entries: [
        {
          'sessionId': 's1',
          'title': '端到端任务',
          'phase': 'completedSuccess',
          'lastActivityAt': DateTime.now().millisecondsSinceEpoch,
        },
      ],
      workspaces: const [
        {'workspacePath': '/repo/app', 'workspaceIdentity': 'app-id'},
      ],
    );
    final hub = DeviceSessionHub(nativeListEnabled: () => true)
      ..installForTesting(session);
    return (store, hub, session);
  }

  Widget wrap(Widget child, UiSettings ui) => MaterialApp(
        theme: buildDarkTheme(),
        darkTheme: buildDarkTheme(),
        builder: (context, child) =>
            UiSettingsProvider(settings: ui, child: child!),
        home: child,
      );

  testWidgets('devices → task list → task chat → back → back', (tester) async {
    final (store, hub, _) = await setup(tester);
    final ui = UiSettings();
    await tester.pumpWidget(wrap(
      DevicesPage(
        store: store,
        theme: ThemeController(),
        ui: ui,
        hub: hub,
        scheduled: ScheduledStore(),
      ),
      ui,
    ));
    await tester.pumpAndSettle();

    // 1. Devices home lists the device; tapping its card opens the native
    //    task list (the hub resolves the installed fake session).
    expect(find.text('dev-alpha'), findsWidgets);
    await tester.tap(find.text('dev-alpha').first);
    await tester.pumpAndSettle();
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.text('当前设备上的工作区和任务'), findsOneWidget);
    // Default collapse model: only the active workspace expanded → the
    // task row of the active workspace is visible.
    expect(find.text('端到端任务'), findsOneWidget);

    // 2. Tapping the task opens the native chat page.
    await tester.tap(find.text('端到端任务'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.text('任务会话'), findsOneWidget);
    expect(find.text('端到端任务'), findsOneWidget);

    // 3. Back returns to the list (still connected, task row intact)…
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    expect(find.text('当前设备上的工作区和任务'), findsOneWidget);
    expect(find.text('端到端任务'), findsOneWidget);

    // 4. …and back again lands on the devices home.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TaskListPage), findsNothing);
    expect(find.text('dev-alpha'), findsWidgets);
  });
}
