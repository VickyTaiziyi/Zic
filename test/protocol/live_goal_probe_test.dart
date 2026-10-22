import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/connection_params.dart';
import 'package:zic/state/device_session.dart';

/// Live probe (ZIC_PROBE_URL): dumps the raw goal + backgroundWorks
/// snapshot shapes so the goal panel can be built against real fields.
void main() {
  final url = Platform.environment['ZIC_PROBE_URL'];
  test('live goal snapshot probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZIC_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe4', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      // probe the newest tasks until one carries an active goal
      final tasks = [
        for (final t in session.relayTasks)
          if ('${t['taskId']}'.isNotEmpty) '${t['taskId']}',
      ];
      for (final taskId in tasks.take(6)) {
        final handle = await session.subscribe(taskId);
        for (var i = 0; i < 12 && handle.state.snapshot == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final snap = handle.state.snapshot ?? const {};
        // ignore: avoid_print
        print('PROBE task=$taskId goal=${snap['goal']} '
            'subagents=${snap['subagents']} plan=${snap['plan']}');
        await handle.close();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
