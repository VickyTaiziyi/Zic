import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zic/auth/session_auth.dart';
import 'package:zic/protocol/relay_client.dart';

void main() {
  // The has-login mirror lives in plain SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('buildCookieHeader', () {
    test('joins valid cookies', () {
      final header = buildCookieHeader([
        (name: 'session', value: 'abc', expiresAtMs: null),
        (name: 'theme', value: 'dark', expiresAtMs: null),
      ]);
      expect(header, 'session=abc; theme=dark');
    });

    test('drops WAF/analytics junk cookies', () {
      final header = buildCookieHeader([
        (name: 'acw_tc', value: 'waf', expiresAtMs: null),
        (name: 'cdn_sec_tc', value: 'cdn', expiresAtMs: null),
        (name: 'zcode_locale', value: 'cn', expiresAtMs: null),
        (name: 'sensorsdata2015jssdkcross', value: 'x', expiresAtMs: null),
        (name: '_ga', value: 'GA1.x', expiresAtMs: null),
        (name: 'session', value: 'real', expiresAtMs: null),
      ]);
      expect(header, 'session=real');
    });

    test('junk-only harvest stays empty (no false capture)', () {
      final header = buildCookieHeader([
        (name: 'acw_tc', value: 'waf', expiresAtMs: null),
        (name: 'cdn_sec_tc', value: 'cdn', expiresAtMs: null),
      ]);
      expect(header, isEmpty);
    });

    test('drops empty names/values', () {
      final header = buildCookieHeader([
        (name: '', value: 'x', expiresAtMs: null),
        (name: 'y', value: '', expiresAtMs: null),
        (name: 'ok', value: '1', expiresAtMs: null),
      ]);
      expect(header, 'ok=1');
    });

    test('drops expired cookies, keeps fresh and session ones', () {
      final now = 1700000000000;
      final header = buildCookieHeader([
        (name: 'dead', value: 'x', expiresAtMs: now - 1),
        (name: 'alive', value: 'y', expiresAtMs: now + 60000),
        (name: 'forever', value: 'z', expiresAtMs: null),
        (name: 'epoch0', value: 'w', expiresAtMs: 0),
      ], nowMs: now);
      expect(header, 'alive=y; forever=z; epoch0=w');
    });
  });

  group('SessionAuth.handshakeHeaders', () {
    test('attaches stored cookies to the same host over wss', () async {
      final auth = SessionAuth(store: MemoryCredentialStore());
      await auth.saveCookies('zcode.z.ai', 'session=abc');
      final headers =
          await auth.handshakeHeaders(Uri.parse('wss://zcode.z.ai/ws'));
      expect(headers['Cookie'], 'session=abc');
      expect(headers['Origin'], 'https://zcode.z.ai');
      expect(headers['User-Agent'], isNotEmpty);
    });

    test('never attaches credentials to a different host', () async {
      final auth = SessionAuth(store: MemoryCredentialStore());
      await auth.saveCookies('zcode.z.ai', 'session=abc');
      final headers =
          await auth.handshakeHeaders(Uri.parse('wss://evil.example/ws'));
      expect(headers, isEmpty);
    });

    test('never sends credentials over plaintext ws', () async {
      final auth = SessionAuth(store: MemoryCredentialStore());
      await auth.saveCookies('zcode.z.ai', 'session=abc');
      final headers =
          await auth.handshakeHeaders(Uri.parse('ws://zcode.z.ai/ws'));
      expect(headers, isEmpty);
    });

    test('empty when no session stored', () async {
      final auth = SessionAuth(store: MemoryCredentialStore());
      final headers =
          await auth.handshakeHeaders(Uri.parse('wss://zcode.z.ai/ws'));
      expect(headers, isEmpty);
    });

    test('stores and reloads the ZCode JWT, not a cookie', () async {
      final auth = SessionAuth(store: MemoryCredentialStore());
      const jwt = 'e30.e30.e30';
      await auth.saveJwt('zcode.z.ai', '"$jwt"');
      expect(await auth.jwtFor('zcode.z.ai'), jwt);
      expect(await auth.hasSession('zcode.z.ai'), isTrue);
      expect(
        await auth.handshakeHeaders(Uri.parse('wss://zcode.z.ai/ws')),
        isEmpty,
        reason: 'a JWT must not be sent as a Cookie header',
      );
    });

    test('clear removes stored sessions', () async {
      final auth = SessionAuth(store: MemoryCredentialStore());
      await auth.saveJwt('zcode.z.ai', 'e30.e30.e30');
      expect(await auth.hasSession('zcode.z.ai'), isTrue);
      await auth.clear();
      expect(await auth.hasSession('zcode.z.ai'), isFalse);
    });
  });

  group('auth failure mapping', () {
    test('close code 4001 maps to auth-required', () {
      expect(relayCloseReason(4001), 'auth-required');
    });

    test('isAuthFailure covers credential-loss reasons', () {
      expect(isAuthFailure('auth-required'), isTrue);
      expect(isAuthFailure('session-expired'), isTrue);
      expect(isAuthFailure('invalid-mobile-connection'), isTrue);
      expect(isAuthFailure('desktop-disconnected'), isFalse);
      expect(isAuthFailure(null), isFalse);
    });
  });

  group('jwt probe', () {
    test('reads zcodejwttoken and rejects WAF crumbs', () {
      expect(
        jwtFromStorageProbe('{"zcodejwttoken":"e30.e30.e30","acw_tc":"waf"}'),
        'e30.e30.e30',
      );
      expect(jwtFromStorageProbe('{"zcodejwttoken":"acw_tc"}'), isNull);
      expect(jwtFromStorageProbe(''), isNull);
      expect(
        jwtFromStorageProbe('"{\\"zcodejwttoken\\":\\"e30.e30.e30\\"}"'),
        'e30.e30.e30',
      );
    });
  });

  group('login host allowlist', () {
    test('official hosts pass, everything else is external', () {
      expect(SessionAuth.isAllowedLoginHost('zcode.z.ai'), isTrue);
      expect(SessionAuth.isAllowedLoginHost('login.z.ai'), isTrue);
      // True subdomains of the registrable domains are org-controlled and
      // pass; lookalike suffixes under OTHER registries must not.
      expect(SessionAuth.isAllowedLoginHost('evilzcode.z.ai'), isTrue);
      expect(SessionAuth.isAllowedLoginHost('z.ai.evil.com'), isFalse);
      expect(SessionAuth.isAllowedLoginHost('zcode.z.ai.evil.net'), isFalse);
      expect(SessionAuth.isAllowedLoginHost('example.com'), isFalse);
    });
  });
}
