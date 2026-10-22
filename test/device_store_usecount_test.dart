import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/state/device_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Device.useCount', () {
    test('touch increments useCount and sets lastUsedAt', () async {
      final store = DeviceStore();
      await store.load();
      final d = await store.addUrl('https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1');
      expect(store.devices.first.useCount, 0);

      await store.touch(d.id);
      await store.touch(d.id);
      expect(store.devices.first.useCount, 2);
      expect(store.devices.first.lastUsedAt, isNotNull);
    });

    test('old JSON without useCount defaults to 0', () {
      final d = Device.fromJson({
        'id': 'x',
        'label': 'legacy',
        'url': 'https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1',
        'addedAt': 123,
        'lastUsedAt': 456,
        // no useCount key
      });
      expect(d.useCount, 0);
      expect(d.lastUsedAt, 456);
    });

    test('same sid updates the stored link and keeps the card', () async {
      final store = DeviceStore();
      await store.load();
      final first = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=desk&mid=m1&name=old&app_version=3.16.2',
      );
      await store.touch(first.id);
      await store.setPinned(first.id, true);

      final again = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=desk&mid=m2&name=old&app_version=3.16.2',
      );

      expect(store.devices, hasLength(1));
      expect(again.id, first.id);
      expect(again.pinned, isTrue);
      expect(again.useCount, 1);
      expect(again.params!.deviceMid, 'm2');

      final reloaded = DeviceStore();
      await reloaded.load();
      expect(reloaded.devices, hasLength(1));
      expect(reloaded.devices.single.params!.deviceSid, 'desk');
      expect(reloaded.devices.single.params!.deviceMid, 'm2');
    });

    test('a disk read keeps a device added while storage was still loading', () {
      final disk = Device(
        id: 'disk-id',
        label: 'old',
        url: 'https://zcode.z.ai/remote/v4?sid=desk&mid=m1&name=old&app_version=3.16.2',
        addedAt: 10,
        useCount: 2,
        pinned: true,
      );
      final pending = Device(
        id: 'memory-id',
        label: 'old',
        url: 'https://zcode.z.ai/remote/v4?sid=desk&mid=m2&name=old&app_version=3.16.2',
        addedAt: 20,
        useCount: 4,
      );
      final extra = Device(
        id: 'other-id',
        label: 'phone',
        url: 'https://zcode.z.ai/remote/v4?sid=other&mid=m9&name=phone&app_version=3.16.2',
        addedAt: 30,
      );
      final merged = mergeStoredDevices([disk], [pending, extra]);
      expect(merged, hasLength(2));
      final desktop = merged.firstWhere((d) => d.params!.deviceSid == 'desk');
      expect(desktop.id, 'disk-id');
      expect(desktop.pinned, isTrue);
      expect(desktop.useCount, 4);
      expect(desktop.params!.deviceMid, 'm2');
      expect(merged.any((d) => d.id == 'other-id'), isTrue);
    });

    test('useCount survives export/import round-trip', () async {
      final a = DeviceStore();
      await a.load();
      final d = await a.addUrl('https://zcode.z.ai/remote/v4?sid=a&hash=b&t=1&name=x');
      await a.touch(d.id);
      await a.touch(d.id);
      await a.touch(d.id);
      final backup = a.exportJson();

      SharedPreferences.setMockInitialValues({});
      final b = DeviceStore();
      await b.load();
      await b.importJson(backup);
      expect(b.devices.first.useCount, 3);
    });
  });
}
