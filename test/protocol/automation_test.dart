import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/automation.dart';
import 'package:zic/protocol/channel_client.dart';

/// Fake automation channel: answers from a method table, records every
/// call, and can be tuned to reject method names with "no such method".
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
  group('AutomationPort.list', () {
    test('uses listAllAutomations and parses a plain list', () async {
      final fake = FakeChannel((m, _) => [
            {
              'automationId': 'a1',
              'title': '日报',
              'prompt': '写日报',
              'cronExpr': '0 9 * * *',
              'enabled': true,
            },
            {'automationId': 'a2', 'title': '备份数据库', 'interval': 6,
              'intervalUnit': 'hour', 'recurring': true},
          ]);
      final port = AutomationPort(fake.call);

      final items = await port.list();

      expect(fake.calls.single.$1, 'listAllAutomations');
      expect(fake.calls.single.$2, isEmpty);
      expect(items, hasLength(2));
      expect(items[0].id, 'a1');
      expect(items[0].trigger, AutomationInput.triggerCron);
      expect(items[1].trigger, AutomationInput.triggerInterval);
      expect(items[1].intervalUnit, 'hour');
    });

    test('unwraps {automations: [...]} responses', () async {
      final fake = FakeChannel((m, _) => {
            'automations': [
              {'id': 'x', 'title': 'T', 'prompt': 'P', 'relativeDelayMinutes': 30},
            ],
          });
      final port = AutomationPort(fake.call);

      final items = await port.list();

      expect(items, hasLength(1));
      expect(items[0].id, 'x'); // id fallback shape
      expect(items[0].trigger, AutomationInput.triggerOneShot);
    });

    test('falls back to listAutomations and remembers the winner',
        () async {
      var probe = 0;
      final fake = FakeChannel((m, _) {
        probe++;
        if (m == 'listAllAutomations' && probe == 1) throw missing(m);
        return const [];
      });
      final port = AutomationPort(fake.call);

      await port.list();
      await port.list();

      final methods =
          fake.calls.map((c) => c.$1).toList();
      // First call probes both; second goes straight to the resolved one.
      expect(methods, [
        'listAllAutomations',
        'listAutomations',
        'listAutomations',
      ]);
    });

    test('non-missing-method errors surface verbatim', () async {
      final fake = FakeChannel((m, _) =>
          throw ChannelRpcError('cronExpr is required', null));
      final port = AutomationPort(fake.call);

      await expectLater(
          port.list(), throwsA(isA<ChannelRpcError>()));
      expect(fake.calls, hasLength(1));
    });
  });

  group('AutomationPort.create wire shapes', () {
    test('cron trigger', () async {
      final fake = FakeChannel((m, _) => {'automationId': 'new'});
      final port = AutomationPort(fake.call);

      await port.create(const AutomationInput(
        title: '站会总结',
        prompt: '总结昨天的 git 提交',
        cronExpr: '30 9 * * 1-5',
      ));

      final (method, args) = fake.calls.single;
      expect(method, 'createAutomation');
      expect(args, [
        {
          'title': '站会总结',
          'prompt': '总结昨天的 git 提交',
          'cronExpr': '30 9 * * 1-5',
        },
      ]);
    });

    test('interval trigger with cap', () async {
      final fake = FakeChannel((m, _) => null);
      final port = AutomationPort(fake.call);

      await port.create(const AutomationInput(
        title: 't',
        prompt: 'p',
        trigger: AutomationInput.triggerInterval,
        interval: 2,
        intervalUnit: 'day',
        recurring: false,
        maxRuns: 10,
        model: 'glm-5.2',
      ));

      expect(fake.calls.single.$2, [
        {
          'title': 't',
          'prompt': 'p',
          'interval': 2,
          'intervalUnit': 'day',
          'recurring': false,
          'maxRuns': 10,
          'model': 'glm-5.2',
        },
      ]);
    });

    test('one-shot trigger emits relativeDelayMinutes + single run',
        () async {
      final fake = FakeChannel((m, _) => null);
      final port = AutomationPort(fake.call);

      await port.create(const AutomationInput(
        title: 't',
        prompt: 'p',
        trigger: AutomationInput.triggerOneShot,
        relativeDelayMinutes: 90,
      ));

      expect(fake.calls.single.$2, [
        {
          'title': 't',
          'prompt': 'p',
          'relativeDelayMinutes': 90,
          'recurring': false,
          'maxRuns': 1,
        },
      ]);
    });

    test('empty optional fields are omitted', () async {
      final fake = FakeChannel((m, _) => null);
      final port = AutomationPort(fake.call);

      await port.create(const AutomationInput(
        title: 't',
        prompt: 'p',
        cronExpr: '* * * * *',
        model: '',
        provider: null,
      ));

      final wire = fake.calls.single.$2.first as Map<String, dynamic>;
      expect(wire.containsKey('model'), isFalse);
      expect(wire.containsKey('provider'), isFalse);
    });
  });

  group('AutomationPort.update', () {
    test('probes methods and shapes, remembers the accepted pair',
        () async {
      final fake = FakeChannel((m, args) {
        // Only automationUpdate with positional args is accepted.
        if (m == 'automationUpdate' && args.first is String) return null;
        throw missing(m);
      });
      final port = AutomationPort(fake.call);

      await port.update('a1',
          const AutomationInput(title: 't', prompt: 'p', cronExpr: '* * * * *'));

      // Shape 0 probes all methods, then shape 1 does: the accepted call is
      // automationUpdate with positional args (id carried positionally, so
      // the fields map omits automationId).
      expect(fake.calls, hasLength(6));
      expect(fake.calls.last.$1, 'automationUpdate');
      expect(fake.calls.last.$2, [
        'a1',
        {'title': 't', 'prompt': 'p', 'cronExpr': '* * * * *'},
      ]);

      fake.calls.clear();
      await port.update(
          'a2', const AutomationInput(title: 't', prompt: 'p', cronExpr: '* * * * *'));
      // Resolved method+shape go straight through without probing.
      expect(fake.calls.single.$1, 'automationUpdate');
      expect(fake.calls.single.$2.first, 'a2');
    });

    test('validation errors are not treated as missing methods', () async {
      final fake = FakeChannel(
          (m, _) => throw ChannelRpcError('title required', null));
      final port = AutomationPort(fake.call);

      await expectLater(
        port.update('a1',
            const AutomationInput(title: 't', prompt: 'p', cronExpr: '* * * * *')),
        throwsA(isA<ChannelRpcError>()),
      );
      expect(fake.calls, hasLength(1));
    });

    test('setEnabled sends a flag-only update', () async {
      final fake = FakeChannel((m, _) => null);
      final port = AutomationPort(fake.call);

      await port.setEnabled('a1', false);

      expect(fake.calls.single.$2, [
        {'automationId': 'a1', 'enabled': false},
      ]);
    });
  });

  group('AutomationPort.remove', () {
    test('deleteAutomation gets an id object; automationDelete gets the id',
        () async {
      final fake = FakeChannel((m, _) {
        if (m == 'deleteAutomation') return null;
        throw missing(m);
      });
      final port = AutomationPort(fake.call);

      await port.remove('a1');
      expect(fake.calls.single.$2, [
        {'automationId': 'a1'}
      ]);

      final fake2 = FakeChannel((m, _) {
        if (m == 'automationDelete') return null;
        throw missing(m);
      });
      final port2 = AutomationPort(fake2.call);

      await port2.remove('a2');
      expect(fake2.calls.last.$1, 'automationDelete');
      expect(fake2.calls.last.$2, ['a2']);
    });
  });

  group('AutomationInput.validate', () {
    test('requires title, prompt and trigger fields', () {
      expect(const AutomationInput().validate(), 'auto.err.title');
      expect(
          const AutomationInput(title: 't').validate(), 'auto.err.prompt');
      expect(
          const AutomationInput(title: 't', prompt: 'p').validate(),
          'auto.err.cron');
      expect(
          const AutomationInput(title: 't', prompt: 'p', cronExpr: '')
              .validate(),
          'auto.err.cron');
      expect(
          const AutomationInput(
                  title: 't',
                  prompt: 'p',
                  trigger: AutomationInput.triggerInterval)
              .validate(),
          'auto.err.interval');
      expect(
          const AutomationInput(
                  title: 't',
                  prompt: 'p',
                  trigger: AutomationInput.triggerOneShot,
                  relativeDelayMinutes: 0)
              .validate(),
          'auto.err.delay');
      expect(
          const AutomationInput(
                  title: 't',
                  prompt: 'p',
                  trigger: AutomationInput.triggerOneShot,
                  relativeDelayMinutes: 60 * 24 * 365 + 1)
              .validate(),
          'auto.err.delay');
      expect(
          const AutomationInput(
                  title: 't',
                  prompt: 'p',
                  cronExpr: '0 9 * * *',
                  enabledOnly: null)
              .validate(),
          isNull);
    });

    test('flag-only updates skip validation', () {
      expect(
          const AutomationInput(enabledOnly: true, existingId: 'a')
              .validate(),
          isNull);
    });
  });

  group('AutomationItem', () {
    test('field tolerances and trigger derivation', () {
      final item = AutomationItem({
        'id': 'i1', // id fallback shape
        'name': '周报', // name fallback shape
        'instruction': '写周报', // instruction fallback shape
        'interval': 1,
        'intervalUnit': 'week',
      });
      expect(item.id, 'i1');
      expect(item.title, '周报');
      expect(item.prompt, '写周报');
      expect(item.trigger, AutomationInput.triggerInterval);
      expect(item.enabled, isTrue); // absent enabled defaults to on
    });

    test('enabled=false / paused=true both count as disabled', () {
      expect(
          AutomationItem({'enabled': false}).enabled, isFalse);
      expect(AutomationItem({'paused': true}).enabled, isFalse);
    });

    test('toInput round-trips the edit form', () {
      final item = AutomationItem({
        'automationId': 'a9',
        'title': '日报',
        'prompt': '写日报',
        'cronExpr': '0 9 * * *',
        'model': 'glm-5.2',
        'mode': 'build',
        'targetTaskId': 'task-7',
      });
      final input = item.toInput();
      expect(input.title, '日报');
      expect(input.cronExpr, '0 9 * * *');
      expect(input.model, 'glm-5.2');
      expect(input.targetTaskId, 'task-7');
      expect(input.toWire()['cronExpr'], '0 9 * * *');
    });

    test('run bookkeeping getters', () {
      final item = AutomationItem({
        'lastRunAt': 1724400000000,
        'lastResult': 'success',
      });
      expect(item.lastRunAt, 1724400000000);
      expect(item.lastResult, 'success');
    });
  });
}
