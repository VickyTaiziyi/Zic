import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/connection_params.dart';
import 'package:zic/protocol/remote_client.dart';
import 'package:zic/state/device_session.dart';

/// Shrunken defence timings: lets the stall policy run against REAL
/// (millisecond) delays instead of a fake clock, whose microtask drainage
/// proved unreliable for suspend/dispose chains.
const StallTimings fastTimings = StallTimings(
  healthyWaitTimeout: Duration(milliseconds: 40),
  rpcTimeout: Duration(milliseconds: 70),
  dialTimeout: Duration(milliseconds: 60),
  listReadyTimeout: Duration(seconds: 300), // keep the watchdog out of the way
  minRebuildInterval: Duration(milliseconds: 5),
  retryBackoff: Duration(milliseconds: 60),
);

/// Relay-backed client replaced wholesale: every network step answers from
/// local knobs so the session policy (timeouts, escalation, rebuilds) can be
/// observed deterministically.
class StubRemoteClient extends RemoteClient {
  StubRemoteClient(super.params);

  bool hangConnect = false;
  bool failBootstrapOnce = false;
  int bootstrapCalls = 0;
  int disposeCount = 0;

  @override
  Future<void> connect() {
    if (hangConnect) return Completer<void>().future;
    return Future.value();
  }

  @override
  Future<void> waitPaired({Duration timeout = const Duration(seconds: 60)}) =>
      Future.value();

  @override
  Future<Map<String, dynamic>> bootstrap() {
    bootstrapCalls += 1;
    if (failBootstrapOnce) {
      failBootstrapOnce = false;
      throw StateError('bootstrap exploded');
    }
    return Future.value({
      'workspaces': [
        {'workspacePath': '/repo', 'workspaceIdentity': 'repo-id'},
      ],
    });
  }

  @override
  Future<BridgeSession> openBridge(
    String workspaceKey, {
    String? taskId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw StateError('workspace-bridge-error: stub has no bridges');
  }

  @override
  Future<void> dispose() {
    disposeCount += 1;
    // Skips RemoteClient.dispose on purpose: nothing real was ever opened.
    return Future.value();
  }
}

/// Gate standing in for the live workspace bridge.
class FakeGate implements WorkspaceGate {
  FakeGate({required this.healthy});

  /// When false, waitHealthy throws TimeoutException (simulating an expiry)
  /// immediately; when true RPCs are accepted but never answered.
  final bool healthy;
  int calls = 0;

  @override
  Future<void> waitHealthy({required Duration timeout}) {
    if (!healthy) {
      return Future.error(TimeoutException('degraded', timeout));
    }
    return Future.value();
  }

  @override
  Future<dynamic> call(String channel, String method, List<Object?> args) {
    calls += 1;
    return Completer<dynamic>().future; // healthy-but-deaf bridge
  }
}

RemoteConnectionParams paramsOf() => RemoteConnectionParams.parse(
      'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=123&mid=m&name=test',
    )!;

Future<void> until(bool Function() condition,
        {int maxMs = 2500, String? because}) =>
    () async {
      var waited = 0;
      while (!condition()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        waited += 10;
        if (waited > maxMs) break;
      }
      if (because != null && !condition()) {
        fail('condition not met within ${maxMs}ms: $because');
      }
    }();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hung relay dial is bounded and the failure retried', () async {
    var created = 0;
    final session = DeviceSession(
      deviceId: 'd1',
      params: paramsOf(),
      timings: fastTimings,
      clientFactory: () {
        created += 1;
        return StubRemoteClient(paramsOf())..hangConnect = true;
      },
    );
    unawaited(session.connect().catchError((Object _) {}));
    // Until dialTimeout the session parks in `connecting`; then the bound
    // converts the black-holed dial into a retryable failure and the backoff
    // dials a fresh client, which hangs and errors again.
    await until(() => session.status == DeviceStatus.error,
        because: 'first hung dial must time out');
    expect(created, 1);
    await until(() => created == 2, because: 'retry must redial');
    await until(() => session.status == DeviceStatus.error);
    await session.dispose();
  });

  test('unhealthy bridge stalls turn one channel call into a full rebuild',
      () async {
    var created = 0;
    final session = DeviceSession(
      deviceId: 'd1',
      params: paramsOf(),
      timings: fastTimings,
      clientFactory: () {
        created += 1;
        return StubRemoteClient(paramsOf());
      },
    );
    final badGate = FakeGate(healthy: false);
    session.debugAttachGateForTest(badGate);
    unawaited(session.connect());
    await until(() => session.status == DeviceStatus.connected);

    // The RPC surfaces its own TimeoutException; the session schedules one
    // suspension + fresh-connect behind the scenes.
    final before = created;
    unawaited(session
        .callChannel('zcode-agent', 'listAllAutomations')
        .catchError((Object _) {}));
    // Parallel duplicate failures must NOT stack rebuilds: this one lands
    // while the first rebuild is already in flight / debounced.
    unawaited(session
        .callChannel('off-peak-task', 'run')
        .catchError((Object _) {}));
    await until(() => created == before + 1, because: 'stall must rebuild');
    await until(() => session.status == DeviceStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(created, before + 1);
    await session.dispose();
  });

  test('repeat reload failures escalate into a connection rebuild', () async {
    final stubs = <StubRemoteClient>[];
    final session = DeviceSession(
      deviceId: 'd1',
      params: paramsOf(),
      timings: fastTimings,
      clientFactory: () {
        final stub = StubRemoteClient(paramsOf());
        stubs.add(stub);
        return stub;
      },
    );
    unawaited(session.connect());
    await until(() => session.status == DeviceStatus.connected);

    // First failing reload stays soft (error banner only, same client).
    stubs.first.failBootstrapOnce = true;
    unawaited(session.reloadTasks());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(stubs, hasLength(1));
    expect(session.status, DeviceStatus.connected);

    // Second consecutive failure escalates: full rebuild with a brand-new
    // client (the fix for "retry does nothing" over a wedged link).
    stubs.first.failBootstrapOnce = true;
    unawaited(session.reloadTasks());
    await until(() => stubs.length == 2, because: 'escalation must rebuild');
    await until(() => session.status == DeviceStatus.connected);
    await session.dispose();
  });

  test('healthy-but-deaf bridge RPC timeouts trigger the same rebuild',
      () async {
    var created = 0;
    final session = DeviceSession(
      deviceId: 'd1',
      params: paramsOf(),
      timings: fastTimings,
      clientFactory: () {
        created += 1;
        return StubRemoteClient(paramsOf());
      },
    );
    final gate = FakeGate(healthy: true);
    session.debugAttachGateForTest(gate);
    unawaited(session.connect());
    await until(() => session.status == DeviceStatus.connected);
    expect(gate.calls, 0);

    unawaited(
        session.callChannel('usage-stats', 'overview').catchError((_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(gate.calls, 1);
    // rpcTimeout fires against the never-answering bridge.
    await until(() => created == 2, because: 'RPC timeout must rebuild');
    await until(() => session.status == DeviceStatus.connected);
    await session.dispose();
  });

  test('a workspace miss does not rebuild the link', () async {
    var created = 0;
    final session = DeviceSession(
      deviceId: 'd1',
      params: paramsOf(),
      timings: const StallTimings(
        healthyWaitTimeout: Duration(milliseconds: 40),
        rpcTimeout: Duration(milliseconds: 70),
        dialTimeout: Duration(milliseconds: 60),
        listReadyTimeout: Duration(milliseconds: 30),
        minRebuildInterval: Duration(milliseconds: 5),
        retryBackoff: Duration(milliseconds: 60),
      ),
      clientFactory: () {
        created += 1;
        return StubRemoteClient(paramsOf());
      },
    );
    unawaited(session.connect());
    await until(() => session.status == DeviceStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(created, 1);
    expect(session.error, contains('workspace-bridge-error'));
    await session.dispose();
  });

  test('an open task keeps the link when a side call times out', () async {
    var created = 0;
    final session = DeviceSession(
      deviceId: 'd1',
      params: paramsOf(),
      timings: fastTimings,
      clientFactory: () {
        created += 1;
        return StubRemoteClient(paramsOf());
      },
    );
    session.debugAttachGateForTest(FakeGate(healthy: true));
    session.debugHoldTaskForTest();
    unawaited(session.connect());
    await until(() => session.status == DeviceStatus.connected);
    final before = created;
    unawaited(session
        .callChannel('usage-stats', 'overview')
        .catchError((Object _) {}));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(created, before);
    expect(session.status, DeviceStatus.connected);
    await session.dispose();
  });
}
