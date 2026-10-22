import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zic/auth/session_auth.dart';
import 'package:zic/state/app_kv.dart';
import 'package:zic/state/device_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zic_kv_test');
    AppKv.instance.debugUseDirectory(dir);
  });

  tearDown(() {
    AppKv.instance.debugReset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('login and devices survive a process restart', () async {
    const jwt = 'aaa.bbb.ccc';
    final auth = SessionAuth();
    await auth.saveJwt('zcode.z.ai', jwt);

    final store = DeviceStore();
    await store.load();
    await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=abc&mid=m1&name=Desk',
    );
    expect(store.degraded, isFalse);
    expect(store.devices, hasLength(1));

    // Same directory, empty memory: what a cold start does.
    AppKv.instance.debugForgetMemory();
    AppKv.instance.debugUseDirectory(dir);

    final auth2 = SessionAuth();
    expect(await auth2.jwtFor('zcode.z.ai'), jwt);
    expect(await auth2.hasSession('zcode.z.ai'), isTrue);

    final store2 = DeviceStore();
    await store2.load();
    expect(store2.degraded, isFalse);
    expect(store2.devices, hasLength(1));
    expect(store2.devices.single.label, 'Desk');
    expect(store2.devices.single.params?.deviceSid, 'abc');
  });
}
