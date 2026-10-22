import 'package:flutter_test/flutter_test.dart';
import 'package:zic/protocol/connection_params.dart';
import 'package:zic/state/device_session.dart';

void main() {
  test('v4 link without a stored login fails fast with auth-required',
      () async {
    final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=abc&mid=m1&name=dev-alpha')!;
    expect(params.passHash, isEmpty,
        reason: 'v4 links carry no HMAC key by design');

    var dialed = false;
    final session = DeviceSession(
      deviceId: 'd1',
      params: params,
      handshakeHeaderProvider: () async => const {'Cookie': 'acw_tc=junk'},
      relayTokenProvider: () async => null,
      clientFactory: () {
        dialed = true;
        throw StateError('the relay must not be dialed without credentials');
      },
    );

    await session.connect();

    expect(dialed, isFalse, reason: 'cookies alone must not dial a v4 link');
    expect(session.status, DeviceStatus.error);
    expect(session.failureReason, 'auth-required');
    await session.dispose();
  });

  test('v4 link with a relay token proceeds to the dial', () async {
    final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=abc&mid=m1&name=dev-alpha')!;
    var dialed = false;
    final session = DeviceSession(
      deviceId: 'd2',
      params: params,
      relayTokenProvider: () async => 'aaaaaaaaaaaaaaaaaaaaaA',
      clientFactory: () {
        dialed = true;
        // Fail the dial immediately so the test stays offline.
        throw StateError('stop after dial');
      },
    );

    // The factory throws right after marking the dial — connect surfaces
    // the error, the point here is only that the dial was attempted.
    await session.connect().catchError((_) {});

    expect(dialed, isTrue,
        reason: 'a relay v2 token unblocks the native dial path');
    await session.dispose();
  });
}
