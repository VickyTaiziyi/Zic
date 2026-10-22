import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/protocol/connection_params.dart';
import 'package:zic/state/device_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteConnectionParams.parse', () {
    test('parses a full official URL', () {
      final p = RemoteConnectionParams.parse(
          'https://zcode.z.ai/remote/v4?sid=d_FZ1&hash=abc%2Fdef&t=1787477536440&mid=e54d&name=dev-alpha&app_version=3.8.1');
      expect(p, isNotNull);
      expect(p!.deviceSid, 'd_FZ1');
      expect(p.timestamp, 1787477536440);
      expect(p.deviceMid, 'e54d');
      expect(p.deviceName, 'dev-alpha');
      expect(p.appVersion, '3.8.1');
      expect(p.source.host, 'zcode.z.ai');
    });

    test('returns null when required params are missing', () {
      // v4 links only require sid (hash/t are v3-era proof fields); the
      // older link shape must still carry both hash and a numeric t.
      expect(RemoteConnectionParams.parse('https://zcode.z.ai/remote/v4'),
          isNull);
      expect(
          RemoteConnectionParams.parse(
              'https://zcode.z.ai/remote/v3?sid=a&hash=b'),
          isNull);
      expect(
          RemoteConnectionParams.parse(
              'https://zcode.z.ai/remote/v3?sid=a&hash=b&t=notanumber'),
          isNull);
      expect(RemoteConnectionParams.parse('not a url'), isNull);
      expect(RemoteConnectionParams.parse(''), isNull);
    });

    test('trims surrounding whitespace', () {
      final p = RemoteConnectionParams.parse(
          '  https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1  ');
      expect(p, isNotNull);
    });
  });

  group('DeviceStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('addUrl derives label from device name', () async {
      final store = DeviceStore();
      await store.load();
      final d = await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1&name=home-pc');
      expect(d.label, 'home-pc');
      expect(store.devices.length, 1);
    });

    test('addUrl falls back to host when no name', () async {
      final store = DeviceStore();
      await store.load();
      final d = await store
          .addUrl('https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1');
      expect(d.label, 'zcode.z.ai');
    });

    test('addUrl dedupes identical URLs', () async {
      final store = DeviceStore();
      await store.load();
      const url = 'https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1&name=x';
      final d1 = await store.addUrl(url);
      final d2 = await store.addUrl(url);
      expect(d1.id, d2.id);
      expect(store.devices.length, 1);
    });

    test('persists across reload', () async {
      var store = DeviceStore();
      await store.load();
      await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1&name=persisted');

      store = DeviceStore();
      await store.load();
      expect(store.devices.length, 1);
      expect(store.devices.first.label, 'persisted');
    });

    test('rename and touch update the device', () async {
      final store = DeviceStore();
      await store.load();
      final d = await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1&name=old');
      await store.rename(d.id, 'new-name');
      await store.touch(d.id);
      expect(store.devices.first.label, 'new-name');
      expect(store.devices.first.lastUsedAt, isNotNull);
    });

    test('remove deletes the device', () async {
      final store = DeviceStore();
      await store.load();
      final d = await store
          .addUrl('https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1');
      await store.remove(d.id);
      expect(store.devices, isEmpty);
    });

    test('export then import round-trips and dedupes', () async {
      final a = DeviceStore();
      await a.load();
      await a.addUrl(
          'https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1&name=one');
      await a.addUrl(
          'https://zcode.z.ai/remote/v4?sid=c&hash=d&t=2&name=two');
      final backup = a.exportJson();

      SharedPreferences.setMockInitialValues({});
      final b = DeviceStore();
      await b.load();
      final added = await b.importJson(backup);
      expect(added, 2);
      expect(b.devices.length, 2);

      // Re-importing the same backup adds nothing.
      final again = await b.importJson(backup);
      expect(again, 0);
    });

    test('unparseable URL is still stored with fallback label', () async {
      final store = DeviceStore();
      await store.load();
      final d = await store.addUrl('totally-bogus');
      expect(d.params, isNull);
      expect(store.devices.length, 1);
    });
  });
}
