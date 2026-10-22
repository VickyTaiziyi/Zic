import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/channel_client.dart';
import 'package:zic/protocol/off_peak.dart';

class FakeChannel {
  final calls = <(String, List<Object?>)>[];
  final dynamic Function(String method, List<Object?> args) responder;

  FakeChannel(this.responder);

  Future<dynamic> call(String method, List<Object?> args) {
    calls.add((method, args));
    return Future.sync(() => responder(method, args));
  }
}

ChannelRpcError missing(String method) =>
    ChannelRpcError('no such method: $method', null);

void main() {
  group('OffPeakPort.list', () {
    test('parses a plain list and tolerates status spellings', () async {
      final fake = FakeChannel((m, _) => [
            {
              'offPeakTaskId': 't1',
              'prompt': '跑测试',
              'status': 'waitingQueue',
              'queuePosition': 3,
            },
            {'offPeakTaskId': 't2', 'prompt': 'p', 'status': 'succeeded',
             'sessionId': 's-2'},
            {'offPeakTaskId': 't3', 'prompt': 'p', 'state': 'error',
             'error': 'boom'},
          ]);
      final port = OffPeakPort(fake.call);

      final tasks = await port.list();

      expect(fake.calls.first.$1, 'list');
      expect(tasks, hasLength(3));
      expect(tasks[0].queued, isTrue);
      expect(tasks[0].queuePosition, 3);
      expect(tasks[1].completed, isTrue);
      expect(tasks[1].sessionId, 's-2');
      expect(tasks[2].failed, isTrue);
      expect(tasks[2].error, 'boom');
    });

    test('unwraps {tasks: [...]} and tolerates id/taskId spellings',
        () async {
      final fake = FakeChannel((m, _) => {
            'tasks': [
              {'taskId': 'x', 'prompt': 'p', 'status': 'running'},
            ],
          });
      final port = OffPeakPort(fake.call);

      final tasks = await port.list();

      expect(tasks.single.id, 'x');
      expect(tasks.single.running, isTrue);
    });
  });

  group('OffPeakPort.submit', () {
    test('sends the documented off-peak-run shape', () async {
      final fake = FakeChannel((m, _) => {'ok': true, 'sessionId': 's-9'});
      final port = OffPeakPort(fake.call);

      final res = await port.submit(OffPeakSubmitInput(
        prompt: ' 修复 flaky 测试 ',
        workspacePath: '/repo',
        workspaceIdentity: 'repo-identity',
        permissionMode: 'yolo',
        model: 'glm-5.2',
      ));

      expect(fake.calls.single.$1, 'run');
      final wire = fake.calls.single.$2.single as Map<String, dynamic>;
      expect(wire['prompt'], '修复 flaky 测试');
      expect(wire['workspacePath'], '/repo');
      expect(wire['workspaceIdentity'], 'repo-identity');
      expect(wire['permissionMode'], 'yolo');
      expect(wire['model'], 'glm-5.2');
      expect(wire['offPeakTaskId'], isNotEmpty);
      // Optional empty fields stay off the wire.
      expect(wire.containsKey('thoughtLevel'), isFalse);
      expect(wire.containsKey('earliestAvailableAt'), isFalse);
      expect(res.ok, isTrue);
      expect(res.sessionId, 's-9');
    });

    test('empty workspaceIdentity is omitted', () async {
      final fake = FakeChannel((m, _) => null);
      final port = OffPeakPort(fake.call);

      await port.submit(OffPeakSubmitInput(
          prompt: 'p', workspacePath: '/w', workspaceIdentity: ''));

      final wire = fake.calls.single.$2.single as Map<String, dynamic>;
      expect(wire.containsKey('workspaceIdentity'), isFalse);
    });

    test('classifies codingPlanOnly failures', () async {
      final fake = FakeChannel(
          (m, _) => throw ChannelRpcError('codingPlanOnly', null));
      final port = OffPeakPort(fake.call);

      await expectLater(
        port.submit(OffPeakSubmitInput(prompt: 'p', workspacePath: '/w')),
        throwsA(isA<OffPeakError>()
            .having((e) => e.kind, 'kind', OffPeakError.codingPlanOnly)),
      );
    });

    test('classifies quota failures', () async {
      final fake = FakeChannel((m, _) =>
          throw ChannelRpcError('monthly quota exceeded', null));
      final port = OffPeakPort(fake.call);

      await expectLater(
        port.submit(OffPeakSubmitInput(prompt: 'p', workspacePath: '/w')),
        throwsA(isA<OffPeakError>()
            .having((e) => e.kind, 'kind', OffPeakError.quota)),
      );
    });

    test('feature-absent desktops classify as unavailable', () async {
      final fake = FakeChannel((m, _) => throw missing(m));
      final port = OffPeakPort(fake.call);

      await expectLater(
        port.submit(OffPeakSubmitInput(prompt: 'p', workspacePath: '/w')),
        throwsA(isA<OffPeakError>()
            .having((e) => e.kind, 'kind', OffPeakError.unavailable)),
      );
    });
  });

  group('OffPeakPort lifecycle + status', () {
    test('pause/resume/cancel hit the lifecycle methods with task ids',
        () async {
      final fake = FakeChannel((m, _) => null);
      final port = OffPeakPort(fake.call);

      await port.pause('t1');
      await port.resume('t1');
      await port.cancel('t2');
      await port.remove('t3');

      final methods = fake.calls.map((c) => c.$1).toList();
      expect(methods, ['pause', 'resume', 'cancel', 'delete']);
      expect(fake.calls[0].$2, [
        {'offPeakTaskId': 't1'}
      ]);
      expect(fake.calls[2].$2, [
        {'offPeakTaskId': 't2'}
      ]);
    });

    test('status parses quota minutes + earliest window; null when absent',
        () async {
      final fake = FakeChannel((m, _) => {
            'available': true,
            'quotaRemainingMinutes': 300,
            'quotaTotalMinutes': 600,
            'earliestAvailableAt': 1724400000000,
          });
      final port = OffPeakPort(fake.call);

      final status = await port.status();
      expect(status!.entitled, isTrue);
      expect(status.quotaRemainingMinutes, 300);
      expect(status.quotaTotalMinutes, 600);
      expect(status.earliestAvailableAt, 1724400000000);

      final old = FakeChannel((m, _) => throw missing(m));
      expect(await OffPeakPort(old.call).status(), isNull);
    });

    test('wake never throws', () async {
      final fake = FakeChannel((m, _) => throw missing(m));
      final port = OffPeakPort(fake.call);
      await port.wake(); // must not throw
    });
  });

  group('OffPeakRunResult', () {
    test('error field downgrades ok', () {
      final res = OffPeakRunResult.from(const {
        'ok': true,
        'error': 'quota',
        'sessionId': 's',
      });
      expect(res.ok, isFalse);
      expect(res.error, 'quota');
      expect(res.sessionId, 's');
    });

    test('echo fills session/conversation ids on void acks', () {
      final res = OffPeakRunResult.from(const {},
          echo: {'sessionId': 'e-s', 'conversationId': 'e-c'});
      expect(res.ok, isTrue); // no error field + no explicit ok → accepted
      expect(res.sessionId, 'e-s');
      expect(res.conversationId, 'e-c');
    });
  });

  group('OffPeakTask derived fields', () {
    test('durationMs from startedAt/finishedAt', () {
      final t = OffPeakTask({
        'startedAt': 1000000,
        'finishedAt': 1000000 + 90 * 60 * 1000,
      });
      expect(t.durationMs, 90 * 60 * 1000);
    });

    test('cancelled counts as terminal', () {
      expect(OffPeakTask({'status': 'cancelled'}).terminal, isTrue);
      expect(OffPeakTask({'status': 'running'}).terminal, isFalse);
    });
  });
}
