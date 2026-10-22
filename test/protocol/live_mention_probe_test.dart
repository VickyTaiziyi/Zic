import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/connection_params.dart';
import 'package:zic/state/device_session.dart';

/// Live probe for @-mention data sources (ZIC_PROBE_URL):
/// file.listWorkspaceFiles, subagents.list, skills.list shapes.
void main() {
  final url = Platform.environment['ZIC_PROBE_URL'];
  test('live mention data probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZIC_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(deviceId: 'probe3', params: params);
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected, reason: session.error);
      final root = session.workspacePath;
      // ignore: avoid_print
      print('PROBE root=$root');

      final files = await session.callChannel(
          'file', 'listWorkspaceFiles', [
        {'rootPath': root}
      ]);
      // ignore: avoid_print
      print('PROBE files type=${files.runtimeType}');
      if (files is List) {
        // ignore: avoid_print
        print('PROBE files count=${files.length} first3='
            '${files.take(3).map((e) => '$e (${e.runtimeType})').toList()}');
      } else if (files is Map) {
        // ignore: avoid_print
        print('PROBE files keys=${files.keys.toList()}');
      }

      try {
        final agents = await session.callChannel('subagents', 'list', []);
        // ignore: avoid_print
        print('PROBE subagents: ${agents is Map ? agents.keys.toList() : agents.runtimeType}');
        if (agents is Map && agents['agents'] is List) {
          final l = agents['agents'] as List;
          // ignore: avoid_print
          print('PROBE subagents count=${l.length} '
              'first=${l.isEmpty ? '-' : '${(l.first as Map).keys.toList()}'}');
        }
      } catch (e) {
        // ignore: avoid_print
        print('PROBE subagents failed: $e');
      }

      try {
        final skills = await session.callChannel('skills', 'list', [
          {
            'workspacePath': root,
            'provider': 'glm',
          }
        ]);
        // ignore: avoid_print
        print('PROBE skills: ${skills is Map ? skills.keys.toList() : skills.runtimeType}');
        if (skills is Map && skills['skills'] is List) {
          final l = skills['skills'] as List;
          // ignore: avoid_print
          print('PROBE skills count=${l.length} '
              'first=${l.isEmpty ? '-' : '${(l.first as Map).keys.toList()}'}');
        }
      } catch (e) {
        // ignore: avoid_print
        print('PROBE skills failed: $e');
      }
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
