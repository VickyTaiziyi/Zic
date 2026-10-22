import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_auth.dart';

/// The relay rejected the account JWT (expired, wrong host, logged out).
class RelayTokenException implements Exception {
  final String reason;
  final String message;
  const RelayTokenException(this.reason, this.message);

  @override
  String toString() => '$reason: $message';
}

/// POST `/api/v1/remote/token` as the desktop does (`createWebRemoteControlV2Http`),
/// but with `role: terminal`. The returned token is a query credential for
/// `wss://<host>/api/v1/remote/ws2`, not a cookie.
Future<String> issueTerminalRelayToken({
  required Uri origin,
  required String jwt,
  http.Client? client,
}) async {
  if (origin.scheme != 'https') {
    throw const RelayTokenException(
      'relay-unavailable',
      'Relay token endpoint requires HTTPS.',
    );
  }
  final endpoint = origin.replace(path: '/api/v1/remote/token', query: '');
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $jwt'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json'
      ..body = jsonEncode({'role': 'terminal'});
    final streamed = await httpClient.send(request).timeout(
          const Duration(seconds: 15),
        );
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const RelayTokenException(
        'auth-required',
        'Sign in to ZCode to use v4 pairing links.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RelayTokenException(
        'relay-unavailable',
        'Relay token request failed (${response.statusCode}).',
      );
    }
    final token = parseRelayTokenResponse(response.body);
    if (token == null) {
      throw const RelayTokenException(
        'relay-unavailable',
        'Relay token response was not usable.',
      );
    }
    return token;
  } on RelayTokenException {
    rethrow;
  } catch (e) {
    throw RelayTokenException('relay-unavailable', 'Relay token request failed.');
  } finally {
    if (ownsClient) httpClient.close();
  }
}

/// Reads the stored ZCode JWT and exchanges it for a terminal relay token.
/// Returns null when this host has no JWT yet (the UI should offer login).
Future<String?> issueTerminalRelayTokenForHost({
  required String host,
  required bool secure,
  SessionAuth? auth,
  http.Client? client,
}) async {
  if (!secure) {
    throw const RelayTokenException(
      'relay-unavailable',
      'Relay requires TLS.',
    );
  }
  final jwt = await (auth ?? sessionAuth).jwtFor(host);
  if (jwt == null || jwt.isEmpty) return null;
  return issueTerminalRelayToken(
    origin: Uri(scheme: 'https', host: host),
    jwt: jwt,
    client: client,
  );
}

/// `{code:0, data:{token}}` from the v2 relay HTTP API.
/// The token alphabet matches the desktop schema
/// (`/^[A-Za-z0-9_-]{21}[AQgw]$/`).
String? parseRelayTokenResponse(String body) {
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final code = decoded['code'];
  if (code != 0 && code != '0') return null;
  final data = decoded['data'];
  if (data is! Map) return null;
  final token = data['token'];
  if (token is! String) return null;
  if (!RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]$').hasMatch(token)) return null;
  return token;
}
