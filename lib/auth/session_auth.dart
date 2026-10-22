import 'dart:async';
import 'dart:convert';

import '../state/app_kv.dart';

/// Terminal-side authentication for the ZCode relay.
///
/// Desktop builds that speak relay v2 delete `hash` and `t` from the
/// pairing link and admit sockets on
/// `wss://<host>/api/v1/remote/ws2?token=…&mid=…`. The token is minted by
/// `POST /api/v1/remote/token` with `Authorization: Bearer <jwt>` and
/// `{"role":"terminal"}`. The JWT is `localStorage["zcodejwttoken"]` after
/// the official login page finishes — not the WAF cookies set on first paint.
///
/// v3 links that still carry `hash` keep the HMAC proof path. Cookies, when
/// present, stay host-scoped and TLS-only for that legacy handshake.
///
/// The JWT is an ACCOUNT CREDENTIAL:
///  - stored in the app-private files directory (sandbox, backups off),
///  - only ever sent to the exact host they were captured for, and only
///    over TLS (wss/https) (MASVS-NETWORK-1/2),
///  - never written to logs or diagnostics.
class SessionAuth {
  SessionAuth({CredentialStore? store})
      : _store = store ?? const SharedPrefsCredentialStore();

  final CredentialStore _store;

  /// Hosts the WebView login flow may navigate to (official Z.ai pages
  /// only; everything else opens externally). Suffix-matched.
  static const _allowedLoginHostSuffixes = [
    'zcode.z.ai',
    'z.ai',
    'zhipuaish.com',
    'open.bigmodel.cn',
  ];

  static bool isAllowedLoginHost(String host) {
    final h = host.toLowerCase();
    // Exact match or a true subdomain (`.` boundary) — a bare suffix match
    // would also admit lookalikes like `evilzcode.z.ai`.
    for (final suffix in _allowedLoginHostSuffixes) {
      if (h == suffix) return true;
      if (h.endsWith('.$suffix')) return true;
    }
    return false;
  }

  /// Extra headers for the relay WebSocket handshake, replicating a browser
  /// session: `Cookie` + `Origin` (+ a browser-shaped `User-Agent` so the
  /// upgrade request matches what the relay expects from the web client).
  /// Empty map when no session is stored for this host — the v3 proof path
  /// (links that still carry `hash`) then applies.
  ///
  /// Process-level credential memory. If the file store cannot be opened
  /// (degraded/in-memory mode), the current run still connects. The file
  /// is what survives a swipe-away. Memory first, then the store.
  final Map<String, String> _memory = {};
  final Map<String, String> _jwtMemory = {};

  static const _jwtPrefix = 'zic.auth.jwt.';

  Future<Map<String, String>> handshakeHeaders(Uri wsUri) async {
    if (wsUri.scheme != 'wss' && wsUri.scheme != 'https') return const {};
    final host = wsUri.host;
    final remembered = _memory[host];
    if (remembered != null && remembered.isNotEmpty) {
      return {
        'Cookie': remembered,
        'Origin': 'https://$host',
        'User-Agent': browserUserAgent,
      };
    }
    if (!await _flagHasSession(host)) return const {};
    final cookie = await _store.cookieFor(host);
    if (cookie == null || cookie.isEmpty) return const {};
    return {
      'Cookie': cookie,
      'Origin': 'https://$host',
      'User-Agent': browserUserAgent,
    };
  }

  /// Plain-prefs mirror of "a login was captured for this host" — NOT a
  /// credential, safe to read on the startup path.
  static const _flagPrefix = 'zic.auth.flag.';

  Future<bool> _flagHasSession(String host) async {
    try {
      return await AppKv.instance.getBool('$_flagPrefix$host') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _flagSet(String host, bool value) async {
    try {
      await AppKv.instance.setBool('$_flagPrefix$host', value);
    } catch (_) {
      // The mirror is best-effort; the store stays authoritative.
    }
  }

  Future<bool> hasSession(String host) async {
    final jwt = await jwtFor(host);
    return jwt != null && jwt.isNotEmpty;
  }

  /// ZCode account JWT for [host], if a login was captured. Never logged.
  Future<String?> jwtFor(String host) async {
    final remembered = _jwtMemory[host];
    if (remembered != null && remembered.isNotEmpty) return remembered;
    try {
      final stored = await AppKv.instance.getString('$_jwtPrefix$host');
      if (stored != null && stored.isNotEmpty && looksLikeJwt(stored)) {
        _jwtMemory[host] = stored;
        return stored;
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveJwt(String host, String jwt) async {
    final normalized = normalizeStoredJwt(jwt);
    if (!looksLikeJwt(normalized)) {
      throw ArgumentError('refusing to store a value that is not a JWT');
    }
    _jwtMemory[host] = normalized;
    try {
      await AppKv.instance.setString('$_jwtPrefix$host', normalized);
      await _flagSet(host, true);
    } catch (_) {
      // Degraded storage: the memory layer still carries this session.
    }
  }

  Future<void> saveCookies(String host, String cookieHeader) async {
    // Memory layer first: the CURRENT app run must be able to connect even
    // when persistence is unavailable (degraded mode).
    _memory[host] = cookieHeader;
    try {
      await _store.saveCookie(host, cookieHeader);
      await _flagSet(host, true);
    } catch (_) {
      // Degraded storage: the memory layer still carries this session.
    }
  }

  Future<void> clear() async {
    _memory.clear();
    _jwtMemory.clear();
    try {
      await _store.clearAll();
    } catch (_) {}
    try {
      final keys = (await AppKv.instance.getKeys())
          .where((k) => k.startsWith(_flagPrefix) || k.startsWith(_jwtPrefix));
      for (final k in keys) {
        await AppKv.instance.remove(k);
      }
    } catch (_) {}
  }

  /// The moment a capture is considered stable (auto-accept in the login
  /// page): two consecutive identical harvests after the set grew.
  static const captureStabilityDelay = Duration(seconds: 2);
}

const browserUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, '
    'like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

/// Credential persistence. [SharedPrefsCredentialStore] is the production
/// file-backed impl; tests inject [MemoryCredentialStore].
abstract interface class CredentialStore {
  Future<String?> cookieFor(String host);
  Future<void> saveCookie(String host, String cookieHeader);
  Future<void> clearAll();
}

/// Cookies live in the same app-private file as the device list: sandbox
/// plus `allowBackup=false` (no cloud backup / no device transfer).
///
/// Deliberately not the SharedPreferences plugin and not
/// flutter_secure_storage. Both have wedged the Android platform thread
/// on some OEM stacks, which showed up as temporary mode and a login
/// that vanished when the app was swiped away.
class SharedPrefsCredentialStore implements CredentialStore {
  const SharedPrefsCredentialStore();

  static const _keyPrefix = 'zic.auth.cookie.';

  @override
  Future<String?> cookieFor(String host) async {
    return AppKv.instance.getString('$_keyPrefix$host');
  }

  @override
  Future<void> saveCookie(String host, String cookieHeader) async {
    await AppKv.instance.setString('$_keyPrefix$host', cookieHeader);
  }

  @override
  Future<void> clearAll() async {
    final keys = (await AppKv.instance.getKeys())
        .where((k) => k.startsWith(_keyPrefix));
    for (final k in keys) {
      await AppKv.instance.remove(k);
    }
  }
}

class MemoryCredentialStore implements CredentialStore {
  final Map<String, String> _cookies = {};

  @override
  Future<String?> cookieFor(String host) async => _cookies[host];

  @override
  Future<void> saveCookie(String host, String cookieHeader) async {
    _cookies[host] = cookieHeader;
  }

  @override
  Future<void> clearAll() async => _cookies.clear();
}

/// `localStorage["zcodejwttoken"]` as written by the official login page.
/// The value is sometimes JSON-stringified (extra quotes). Returns null
/// when the probe has no usable JWT yet.
String? jwtFromStorageProbe(Object? raw) {
  if (raw == null) return null;
  if (raw is Map) {
    return _validJwt(raw['zcodejwttoken']);
  }
  if (raw is! String || raw.isEmpty) return null;
  final trimmed = raw.trim();
  if (trimmed.startsWith('{') ||
      trimmed.startsWith('[') ||
      trimmed.startsWith('"')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return _validJwt(decoded['zcodejwttoken']);
      // Android WebView sometimes JSON-encodes the JS string a second time.
      if (decoded is String) return jwtFromStorageProbe(decoded);
    } catch (_) {}
  }
  return _validJwt(trimmed);
}

String normalizeStoredJwt(String raw) {
  var s = raw.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is String) s = decoded.trim();
    } catch (_) {
      s = s.substring(1, s.length - 1).trim();
    }
  }
  return s;
}

/// Three base64url segments. Deliberately strict so a WAF cookie or an
/// HTML snippet can never be sent as `Authorization: Bearer`.
bool looksLikeJwt(String value) => RegExp(
      r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
    ).hasMatch(value);

String? _validJwt(Object? value) {
  if (value is! String) return null;
  final normalized = normalizeStoredJwt(value);
  if (!looksLikeJwt(normalized)) return null;
  return normalized;
}

/// Joins harvested cookies into a request header value, dropping expired
/// and empty entries. Pure function — unit tested.
/// CDN/WAF/analytics crumbs the official site sets on first load. They
/// are NOT sessions — treating them as "captured" produced the false
/// 会话已捕获 that shipped junk cookies to the relay.
const _junkCookieNames = {
  'acw_tc',
  'cdn_sec_tc',
  'cdn_sec_tc2',
  'zcode_locale',
  '_ga',
  '_gid',
  '_gat',
  '_gat_gtag',
  'sensorsdata2015jssdkcross',
};

bool isJunkCookieName(String name) {
  final n = name.toLowerCase();
  if (_junkCookieNames.contains(n)) return true;
  // Sensors/aliyun trackers all carry telltale prefixes.
  return n.startsWith('sensors') || n.startsWith('aliyun') || n.startsWith('_gtag');
}

String buildCookieHeader(Iterable<({String name, String value, int? expiresAtMs})> cookies,
    {int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final pairs = <String>[];
  for (final c in cookies) {
    if (c.name.isEmpty || c.value.isEmpty) continue;
    if (isJunkCookieName(c.name)) continue;
    if (c.expiresAtMs != null && c.expiresAtMs! > 0 && c.expiresAtMs! <= now) {
      continue;
    }
    pairs.add('${c.name}=${c.value}');
  }
  return pairs.join('; ');
}

/// Relay close codes and error reasons that mean "the session credential is
/// missing/expired" — the UI offers a re-login when it sees one of these.
bool isAuthFailure(String? reason) {
  switch (reason) {
    case 'auth-required':
    case 'session-expired':
    case 'invalid-mobile-connection':
      return true;
    default:
      return false;
  }
}

/// Process-wide instance shared by the login page and the relay dial path.
final sessionAuth = SessionAuth();
