/// Parses a ZCode web-remote connection URL, e.g.
/// https://zcode.z.ai/remote/v4?sid=...&mid=...&name=...&app_version=...
///
/// Mirrors `zC()` in the web client bundle. Current desktop versions (v4)
/// only carry `sid`/`mid`/`name`/`app_version` — the `hash`/`t` proof pair is
/// a v3-era field and the v4 handshake never issues an `auth_challenge`.
/// Both shapes are accepted so older pairing links keep working. The URL also
/// derives the relay websocket endpoint; if the URL shape changes, the raw
/// URL is still stored verbatim by the device store and stays openable in
/// the WebView.
class RemoteConnectionParams {
  final String deviceSid;
  final String passHash;
  final int timestamp;
  final String? deviceMid;
  final String? deviceName;
  final String? appVersion;
  final String? theme;
  final Uri source;

  const RemoteConnectionParams({
    required this.deviceSid,
    required this.passHash,
    required this.timestamp,
    required this.source,
    this.deviceMid,
    this.deviceName,
    this.appVersion,
    this.theme,
  });

  static String? _get(Uri uri, String key) {
    final v = uri.queryParameters[key]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  static RemoteConnectionParams? parse(String raw) {
    Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    final sid = _get(uri, 'sid');
    if (sid == null) return null;
    // v4 links (current desktop) carry no proof pair at all; v3 links must
    // keep both `hash` and a numeric `t` to be accepted.
    final isV4 =
        uri.pathSegments.isNotEmpty && uri.pathSegments.last == 'v4';
    final hash = _get(uri, 'hash');
    final t = int.tryParse(_get(uri, 't') ?? '');
    if (!isV4 && (hash == null || t == null)) return null;
    return RemoteConnectionParams(
      deviceSid: sid,
      passHash: hash ?? '',
      timestamp: t ?? 0,
      deviceMid: _get(uri, 'mid'),
      deviceName: _get(uri, 'name'),
      appVersion: _get(uri, 'app_version'),
      theme: _get(uri, 'theme'),
      source: uri,
    );
  }

  /// Legacy relay websocket (`/ws`). v3 proof links still use this.
  /// Current desktop v2 links use [v2RelayWsUri] instead.
  Uri get relayWsUri {
    final scheme = uriSchemeIsSecure ? 'wss' : 'ws';
    final base = Uri(
      scheme: scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: '/ws',
    );
    if (deviceMid == null) return base;
    return base.replace(queryParameters: {'mid': deviceMid});
  }

  /// Relay v2 socket used by current desktop builds:
  /// `wss://<host>/api/v1/remote/ws2?token=…&mid=…`.
  /// [token] is the short-lived value from `POST /api/v1/remote/token`.
  Uri v2RelayWsUri(String token) {
    final scheme = uriSchemeIsSecure ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: '/api/v1/remote/ws2',
      queryParameters: {
        'token': token,
        if (deviceMid != null) 'mid': deviceMid!,
      },
    );
  }

  bool get uriSchemeIsSecure =>
      source.scheme == 'https' || source.scheme == 'wss';
}
