import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/channel_client.dart';
import 'package:zic/protocol/task_commands.dart';

void main() {
  test('remembers the first accepted candidate and reuses it', () async {
    final calls = <(String, List<Object?>)>[];
    final port = TaskCommandsPort(
      (method, args) async {
        calls.add((method, args));
        if (method == 'renameTask') return {'ok': true};
        throw ChannelRpcError('no such method: $method', null);
      },
      scope: () => {'workspacePath': '/repo'},
    );

    final res = await port.rename('s1', '新标题');
    expect(res, {'ok': true});
    // only the first candidate was tried
    expect(calls.map((c) => c.$1).toList(), ['renameTask']);
    // payload merges scope + taskId + fields
    expect(calls.single.$2.single, {
      'workspacePath': '/repo',
      'taskId': 's1',
      'title': '新标题',
    });

    calls.clear();
    await port.rename('s1', 'again');
    expect(calls.map((c) => c.$1).toList(), ['renameTask']);
  });

  test('confirmed schema: payloads always key the id as taskId', () async {
    // Source-confirmed (web client, docs/parity/web-capabilities.md §4):
    // zcode-task metadata commands take one object merging the workspace
    // scope + taskId; no *Session* variants on this channel.
    Map? seen;
    final port = TaskCommandsPort(
      (method, args) async {
        seen = (args.single as Map).cast<String, Object?>();
        return null;
      },
    );
    await port.rename('s1', 't');
    expect(seen!['taskId'], 's1');
    expect(seen!.containsKey('sessionId'), isFalse);

    await port.setPinned('s1', true);
    expect(seen!['taskId'], 's1');
    expect(seen!['pinned'], true);
  });

  test('archive is two distinct methods without a boolean field', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final port = TaskCommandsPort(
      (method, args) async {
        calls.add((method, (args.single as Map).cast<String, Object?>()));
        return null;
      },
      scope: () => {'workspacePath': '/repo'},
    );

    await port.setArchived('s1', true);
    await port.setArchived('s1', false);
    expect(calls.map((c) => c.$1).toList(), ['archiveTask', 'unarchiveTask']);
    // the confirmed arg shape: scope + taskId only
    for (final (_, payload) in calls) {
      expect(payload, {'workspacePath': '/repo', 'taskId': 's1'});
      expect(payload.containsKey('archived'), isFalse);
    }
  });

  test('delete + listArchived use the confirmed method names', () async {
    final methods = <String>[];
    final port = TaskCommandsPort(
      (method, args) async {
        methods.add(method);
        return null;
      },
      scope: () => {'workspacePath': '/repo'},
    );
    await port.delete('s1');
    await port.listArchived();
    expect(methods, ['deleteTask', 'listArchivedTasks']);
  });

  test('every candidate missing → first error rethrown', () async {
    final port = TaskCommandsPort(
      (method, args) async =>
          throw ChannelRpcError('no such method: $method', null),
    );
    expect(
      () => port.setArchived('s1', true),
      throwsA(isA<ChannelRpcError>()),
    );
  });

  test('validation errors do not advance to the next candidate', () async {
    final tried = <String>[];
    final port = TaskCommandsPort(
      (method, args) async {
        tried.add(method);
        throw ChannelRpcError('validation failed: title required', null);
      },
    );
    expect(
      () => port.rename('s1', 'x'),
      throwsA(isA<ChannelRpcError>()),
    );
    expect(tried, hasLength(1));
  });
}
