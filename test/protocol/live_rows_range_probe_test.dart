

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/connection_params.dart';
import 'package:zic/state/device_session.dart';

/// Live rowsRange probe (run with ZIC_PROBE_URL): connect, subscribe a
/// real session, then exercise the EXACT 加载更早消息 path — beforeRowId =
/// window head, parse the {rows, atSeq, atLogEpoch, hasMore} envelope,
/// epoch-guard, prepend — and print everything.
void main() {
  final url = Platform.environment['ZIC_PROBE_URL'];
  test('live rowsRange probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZIC_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe2', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      // Probe several tasks: rowsRange WITHOUT beforeRowId returns the
      // latest window + hasMore; if hasMore, the cursor path must return
      // strictly older rows.
      var verified = false;
      for (final t in session.relayTasks.take(10)) {
        final taskId = '${t['taskId']}';
        if (taskId.isEmpty) continue;
        final res = await session.callChannel('zcode-agent',
            'conversationRowsRangeV4', [
          {
            ...session.offPeakScope,
            'sessionId': taskId,
            'limit': 60,
          }
        ]);
        if (res is! Map) continue;
        final rows = res['rows'] as List? ?? const [];
        final hasMore = res['hasMore'] == true;
        final ids = [
          for (final r in rows.whereType<Map>())
            (r['rowId'] as num?)?.toInt() ?? -1,
        ]..sort();
        // ignore: avoid_print
        print('PROBE $taskId window=${rows.length} '
            'head=${ids.isEmpty ? '-' : ids.first} '
            'tail=${ids.isEmpty ? '-' : ids.last} hasMore=$hasMore');
        if (!hasMore || rows.isEmpty) continue;
        final head = ids.first;
        final res2 = await session.callChannel('zcode-agent',
            'conversationRowsRangeV4', [
          {
            ...session.offPeakScope,
            'sessionId': taskId,
            'beforeRowId': head,
            'limit': 60,
          }
        ]);
        final rows2 =
            res2 is Map ? (res2['rows'] as List? ?? const []) : const [];
        final hasMore2 = res2 is Map ? res2['hasMore'] : null;
        final epoch2 = res2 is Map ? res2['atLogEpoch'] : null;
        final ids2 = [
          for (final r in rows2.whereType<Map>())
            (r['rowId'] as num?)?.toInt() ?? -1,
        ]..sort();
        // ignore: avoid_print
        print('PROBE   older page: count=${rows2.length} '
            'max=${ids2.isEmpty ? '-' : ids2.last} hasMore=$hasMore2 '
            'epochMatch=${epoch2 == res['atLogEpoch']}');
        if (rows2.isNotEmpty) {
          expect(ids2.last, lessThan(head),
              reason: 'cursor page must be strictly older');
          verified = true;
        }
      }
      // ignore: avoid_print
      print('PROBE verified cursor paging on a real history: $verified');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
