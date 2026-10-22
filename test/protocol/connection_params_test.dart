import 'package:flutter_test/flutter_test.dart';

import 'package:zic/protocol/connection_params.dart';

void main() {
  group('uriSchemeIsSecure', () {
    test('https → secure', () {
      final params = RemoteConnectionParams(
        deviceSid: 'sid',
        passHash: 'hash',
        timestamp: 1,
        source: Uri.parse('https://zcode.z.ai/remote'),
      );
      expect(params.uriSchemeIsSecure, isTrue);
    });

    test('wss → secure', () {
      final params = RemoteConnectionParams(
        deviceSid: 'sid',
        passHash: 'hash',
        timestamp: 1,
        source: Uri.parse('wss://zcode.z.ai/ws'),
      );
      expect(params.uriSchemeIsSecure, isTrue);
    });

    test('http → not secure', () {
      final params = RemoteConnectionParams(
        deviceSid: 'sid',
        passHash: 'hash',
        timestamp: 1,
        source: Uri.parse('http://zcode.z.ai/remote'),
      );
      expect(params.uriSchemeIsSecure, isFalse);
    });

    test('ws → not secure', () {
      final params = RemoteConnectionParams(
        deviceSid: 'sid',
        passHash: 'hash',
        timestamp: 1,
        source: Uri.parse('ws://zcode.z.ai/ws'),
      );
      expect(params.uriSchemeIsSecure, isFalse);
    });

    test('ftp → not secure (was bug)', () {
      final params = RemoteConnectionParams(
        deviceSid: 'sid',
        passHash: 'hash',
        timestamp: 1,
        source: Uri.parse('ftp://bad.example.com/remote'),
      );
      expect(params.uriSchemeIsSecure, isFalse);
    });

    test('unknown scheme → not secure', () {
      final params = RemoteConnectionParams(
        deviceSid: 'sid',
        passHash: 'hash',
        timestamp: 1,
        source: Uri.parse('file:///etc/passwd'),
      );
      expect(params.uriSchemeIsSecure, isFalse);
    });
  });

  group('relayWsUri', () {
    test('https → wss', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=1&mid=m',
      );
      expect(params!.relayWsUri.toString(), 'wss://zcode.z.ai/ws?mid=m');
    });

    test('http → ws', () {
      final params = RemoteConnectionParams.parse(
        'http://localhost:3000/remote/v4?sid=s&hash=h&t=1',
      );
      expect(params!.relayWsUri.toString(), 'ws://localhost:3000/ws');
    });

    test('port is preserved', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai:8443/remote/v4?sid=s&hash=h&t=1',
      );
      expect(params!.relayWsUri.toString(), 'wss://zcode.z.ai:8443/ws');
    });

    test('no mid → no query params', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=1',
      );
      expect(params!.relayWsUri.toString(), 'wss://zcode.z.ai/ws');
    });

    test('v4 link without hash still parses and builds the v2 socket', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=desk&mid=11111111-1111-4111-8111-111111111111&name=desk&app_version=3.16.2',
      );
      expect(params, isNotNull);
      expect(params!.passHash, isEmpty);
      expect(params.deviceSid, 'desk');
      expect(
        params.v2RelayWsUri('aaaaaaaaaaaaaaaaaaaaaA').toString(),
        'wss://zcode.z.ai/api/v1/remote/ws2?token=aaaaaaaaaaaaaaaaaaaaaA&mid=11111111-1111-4111-8111-111111111111',
      );
    });
  });

  group('parse edge cases', () {
    test('missing sid returns null', () {
      expect(
        RemoteConnectionParams.parse(
            'https://zcode.z.ai/remote/v4?hash=h&t=1'),
        isNull,
      );
    });

    test('missing hash returns null on non-v4 link', () {
      expect(
        RemoteConnectionParams.parse(
            'https://zcode.z.ai/remote/v3?sid=s&t=1'),
        isNull,
      );
    });

    test('missing t returns null on non-v4 link', () {
      expect(
        RemoteConnectionParams.parse(
            'https://zcode.z.ai/remote/v3?sid=s&hash=h'),
        isNull,
      );
    });

    test('invalid timestamp returns null on non-v4 link', () {
      expect(
        RemoteConnectionParams.parse(
            'https://zcode.z.ai/remote/v3?sid=s&hash=h&t=abc'),
        isNull,
      );
    });

    test('v4 link without hash/t parses with empty proof fields', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s&mid=m&name=N&app_version=3.16.2',
      );
      expect(params, isNotNull);
      expect(params!.deviceSid, 's');
      expect(params.passHash, '');
      expect(params.timestamp, 0);
      expect(params.deviceMid, 'm');
      expect(params.deviceName, 'N');
      expect(params.appVersion, '3.16.2');
      expect(params.relayWsUri.toString(), 'wss://zcode.z.ai/ws?mid=m');
    });

    test('v4 link tolerates a stray invalid t', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=abc',
      );
      expect(params, isNotNull);
      expect(params!.timestamp, 0);
    });

    test('trimmed query values', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid= SID &hash= HASH &t=1',
      );
      expect(params, isNotNull);
      expect(params!.deviceSid, 'SID');
      expect(params.passHash, 'HASH');
    });

    test('empty optional fields are null', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=1&mid=&name=',
      );
      expect(params!.deviceMid, isNull);
      expect(params.deviceName, isNull);
    });

    test('theme is parsed', () {
      final params = RemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=1&theme=dark',
      );
      expect(params!.theme, 'dark');
    });
  });
}
