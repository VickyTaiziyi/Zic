import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/protocol/automation.dart';
import 'package:zic/state/device_session.dart';
import 'package:zic/state/device_store.dart';
import 'package:zic/ui/automations_page.dart';
import 'package:zic/ui/off_peak_page.dart';
import 'package:zic/ui/theme.dart';
import 'package:zic/ui/ui_settings.dart';

import '../helpers/fake_device_session.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      builder: (context, child) =>
          UiSettingsProvider(settings: UiSettings(), child: child!),
      home: child,
    );

Future<(DeviceStore, Device, FakeDeviceSession)> setupFake(
    WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final store = DeviceStore();
  await store.load();
  await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=abc&hash=xyz&t=123&mid=m1&name=dev-alpha&app_version=3.8.1');
  final device = store.devices.single;
  final session = FakeDeviceSession(
    deviceId: device.id,
    params: device.params!,
    workspaces: const [
      {'workspacePath': '/repo', 'workspaceIdentity': 'repo-id'},
    ],
    channelHandler: (channel, method, args) async {
      if (method.contains('list') || method.contains('List')) {
        return const <Map<String, dynamic>>[];
      }
      if (method == 'status' || method.startsWith('get')) {
        return {'available': true};
      }
      return null;
    },
  );
  return (store, device, session);
}

void main() {
  testWidgets('off-peak model field is a selector sourced from the device',
      (tester) async {
    final (store, device, session) = await setupFake(tester);
    await tester.pumpWidget(wrap(OffPeakPage(
      store: store,
      hub: DeviceSessionHub(nativeListEnabled: () => false),
      device: device,
      hostOverride: session,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建闲时任务'));
    await tester.pumpAndSettle();

    // Desktop parity: no unspecified choice — the field defaults to the
    // first available model.
    expect(find.text('GLM-5.2'), findsOneWidget);

    await tester.tap(find.text('GLM-5.2'));
    await tester.pumpAndSettle();
    expect(find.text('BigModel'), findsOneWidget); // provider subtitle
    expect(find.text('Moonshot V2'), findsOneWidget);
    expect(find.text('kimi_zz'), findsOneWidget);

    await tester.tap(find.text('Moonshot V2'));
    await tester.pumpAndSettle();
    expect(find.text('Moonshot V2'), findsOneWidget); // field now shows it

    await tester.enterText(
        find.widgetWithText(TextField, '任务指令'), '跑一次夜间分析');
    await tester.ensureVisible(find.text('创建闲时任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建闲时任务'));
    await tester.pumpAndSettle();

    final submit = session.channelCalls
        .where((c) => c.$2 == 'run' || c.$2 == 'submit')
        .toList();
    expect(submit, hasLength(1));
    final wire = submit.single.$3.single as Map<String, dynamic>;
    expect(wire['model'], 'kimi/moonshot-v2');
    expect(wire['prompt'], '跑一次夜间分析');
  });

  testWidgets('automation model/thought are selectors; wire splits provider',
      (tester) async {
    final (_, _, session) = await setupFake(tester);
    await tester.pumpWidget(wrap(
      Scaffold(body: AutomationsPane(session: session)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建定时任务'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '任务标题'), '晨报');
    await tester.enterText(
        find.widgetWithText(TextField, '指令'), '汇总昨日改动');

    await tester.tap(find.text('默认模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moonshot V2'));
    await tester.pumpAndSettle();

    // Advanced: thought level selector (枚举 → 选择器, desktop parity).
    await tester.tap(find.text('更多选项'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('默认（不指定）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认（不指定）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最高'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final create = session.channelCalls
        .where((c) => c.$3.any((a) => a is Map && a['title'] == '晨报'))
        .toList();
    expect(create, isNotEmpty);
    final wire = create.first.$3.whereType<Map>().first;
    expect(wire['model'], 'moonshot-v2');
    expect(wire['provider'], 'kimi');
    expect(wire['thoughtLevel'], 'max');
  });

  testWidgets('editing an automation reverse-displays the stored model',
      (tester) async {
    await tester.pumpWidget(wrap(Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => AutomationSheet(
                initial: const AutomationInput(
                  title: '旧任务',
                  prompt: 'p',
                  cronExpr: '0 9 * * *',
                  model: 'moonshot-v2',
                  provider: 'kimi',
                ),
                loadOptions: null,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // No options loader here; the stored composite resolves to the raw
    // provider/model string until options load (offline desktop parity).
    expect(find.text('kimi/moonshot-v2'), findsOneWidget);
    expect(find.text('最高'), findsNothing); // thought stays default
  });
}
