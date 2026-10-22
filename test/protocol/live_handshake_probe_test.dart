import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/connection_params.dart';
import 'package:zic/protocol/remote_client.dart';
import 'package:zic/state/device_session.dart';

/// Live handshake probe against a real remote-control URL (read-only:
/// bootstrap → bridge-open → sessions-index subscribe → view-state →
/// dispose). Skipped unless ZIC_PROBE_URL is set.
///
/// Verifies protocol compatibility with the live desktop and prints the
/// sent zcode_type sequence for parity comparison against the web client.
void main() {
  final url = Platform.environment['ZIC_PROBE_URL'];
  test('live handshake probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZIC_PROBE_URL not set — skipping live probe');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('unparseable probe URL');
    final sent = <String>[];
    final client = RemoteClient(params, onLog: (line) {
      if (line.contains('>>') && line.contains('zcode_type')) {
        final m = RegExp(r'zcode_type[=": ]+([a-z-]+)').firstMatch(line);
        if (m != null) sent.add(m.group(1)!);
      }
      // ignore: avoid_print
      print(line);
    });

    final session = DeviceSession(
      deviceId: 'probe',
      params: params,
      clientFactory: () => client,
    );
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected,
          reason: 'session error: ${session.error}');
      expect(session.workspaces, isNotEmpty,
          reason: 'desktop reported no workspaces');
      // ignore: avoid_print
      print('PROBE workspaces: '
          '${session.workspaces.map(workspaceTitleOf).toList()}');
      expect(session.relayTasks, isNotEmpty,
          reason: 'relay task overview should not be empty');
      // ignore: avoid_print
      print('PROBE relay tasks: ${session.relayTasks.length}');

      // let mobile-view-state / subscriptions flush
      await Future<void>.delayed(const Duration(seconds: 2));
      // ignore: avoid_print
      print('PROBE sent sequence: $sent');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

String workspaceTitleOf(Map<String, dynamic> w) =>
    '${w['label'] ?? w['workspacePath']}';
