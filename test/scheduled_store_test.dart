import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zic/state/scheduled_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScheduledStore', () {
    test('add / remove round-trips through persistence', () async {
      final a = ScheduledStore();
      await a.load();
      await a.add(
        deviceId: 'd1',
        deviceLabel: 'home-pc',
        text: 'hello\n"world"',
        fireAt: 12345,
      );
      expect(a.items, hasLength(1));

      final b = ScheduledStore();
      await b.load();
      expect(b.items, hasLength(1));
      expect(b.items.first.text, 'hello\n"world"');
      expect(b.items.first.deviceLabel, 'home-pc');
      expect(b.items.first.sent, isFalse);

      await b.remove(b.items.first.id);
      expect(b.items, isEmpty);

      final c = ScheduledStore();
      await c.load();
      expect(c.items, isEmpty);
    });

    test('due filters unsent, past-due, under-attempt items', () async {
      final s = ScheduledStore();
      await s.load();
      final now = DateTime.now().millisecondsSinceEpoch;
      await s.add(
          deviceId: 'a', deviceLabel: 'a', text: 'past', fireAt: now - 1000);
      await s.add(
          deviceId: 'b', deviceLabel: 'b', text: 'future', fireAt: now + 60000);
      final id = s.items.first.id;

      final due = s.due(now);
      expect(due, hasLength(1));
      expect(due.first.text, 'past');

      // Sent items drop out of due.
      s.markSent(id);
      expect(s.due(now), isEmpty);
      expect(s.items.first.sent, isTrue);
    });

    test('attempts cap stops retries', () async {
      final s = ScheduledStore();
      await s.load();
      final now = DateTime.now().millisecondsSinceEpoch;
      await s.add(
          deviceId: 'a', deviceLabel: 'a', text: 'x', fireAt: now - 1);
      final id = s.items.first.id;

      for (var i = 0; i < MessageScheduler.maxAttempts; i++) {
        s.markAttempt(id);
        s.markFailed(id, 'boom');
      }
      expect(s.items.first.attempts, MessageScheduler.maxAttempts);
      expect(s.items.first.lastError, 'boom');
      expect(s.due(now), isEmpty);
    });

    test('items stay sorted by fire time', () async {
      final s = ScheduledStore();
      await s.load();
      await s.add(deviceId: 'a', deviceLabel: 'a', text: '1', fireAt: 300);
      await s.add(deviceId: 'b', deviceLabel: 'b', text: '2', fireAt: 100);
      await s.add(deviceId: 'c', deviceLabel: 'c', text: '3', fireAt: 200);
      expect(s.items.map((m) => m.fireAt).toList(), [100, 200, 300]);
    });
  });
}
