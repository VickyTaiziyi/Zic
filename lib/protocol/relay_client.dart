import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/relay_token.dart';
import 'connection_params.dart';
import 'device_info.dart';
import 'proof.dart';

enum RelayState {
  idle,
  connecting,
  authenticating,
  waiting,
  paired,
  reconnecting,
  error,
  kicked,
  closed,
}

class RelayFailure {
  final String reason;
  final String? message;
  const RelayFailure(this.reason, [this.message]);

  @override
  String toString() => message == null ? reason : '$reason: $message';
}

/// Close-code mapping, mirrors `VC()` / `BC` in the web client.
String? relayCloseReason(int code) {
  switch (code) {
    case 4001:
      return 'auth-required';
    case 4004:
      return 'session-not-found';
    case 4009:
      return 'session-conflict';
    case 4010:
      return 'desktop-disconnected';
    case 4011:
      return 'session-expired';
    case 4012:
      return 'workspace-closed';
    case 4013:
      return 'invalid-mobile-connection';
    default:
      return null;
  }
}

/// Reimplementation of the relay terminal socket (`pen` class in the web
/// client). JSON text frames over `wss://<host>/ws`.
class RelayClient {
  final RemoteConnectionParams params;
  final void Function(String line)? onLog;

  /// Extra HTTP headers for the WebSocket handshake (legacy v3 cookie
  /// path). Empty for the v2 token path and for proof-only links.
  final Map<String, String> handshakeHeaders;

  /// When set, every dial (including reconnects) exchanges nothing itself:
  /// the callback returns a fresh `POST /api/v1/remote/token` value and the
  /// socket goes to `/api/v1/remote/ws2`. Desktop does the same on each
  /// connect because the token expires.
  final Future<String?> Function()? accessTokenProvider;

  static const heartbeatInterval = Duration(seconds: 10);
  static const heartbeatAckTimeout = Duration(seconds: 30);
  static const waitingTimeout = Duration(seconds: 30);
  static const reconnectWaitTimeout = Duration(seconds: 20);

  WebSocketChannel? _socket;
  StreamSubscription? _socketSub;

  final _state = ValueNotifier<RelayState>(RelayState.idle);
  ValueListenable<RelayState> get stateListenable => _state;
  RelayState get state => _state.value;

  final _payloadController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get payloads => _payloadController.stream;

  final _failureController = StreamController<RelayFailure>.broadcast();
  Stream<RelayFailure> get failures => _failureController.stream;

  bool _wasPaired = false;
  bool _intentionallyClosed = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  int _connectGeneration = 0;
  DateTime _lastPairStatusAckAt = DateTime.now();

  Timer? _heartbeatTimer;
  Timer? _waitingTimer;
  Timer? _reconnectTimer;
  Timer? _rewaitTimer;

  RelayClient(
    this.params, {
    this.onLog,
    this.handshakeHeaders = const {},
    this.accessTokenProvider,
  });

  /// The official web client stamps every relay frame with wall-clock
  /// SECONDS (`Math.floor(Date.now()/1e3)`). Milliseconds break the
  /// desktop's staleness checks, which stops `pair_status_ack` replies and
  /// forces a heartbeat-timeout reconnect loop (~30s paired→drop cycle).
  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  void _log(String line) => onLog?.call(
        line.replaceAll(RegExp(r'token=[^&\s"]+'), 'token=redacted'),
      );

  void _setState(RelayState s) {
    _state.value = s;
    _log('[relay] state -> $s');
  }

  Future<void> start() async {
    _disposed = false;
    _intentionallyClosed = false;
    _reconnectAttempt = 0;
    _setState(RelayState.connecting);
    await _connect();
  }

  Future<void> _connect() async {
    // Serialize connects: heartbeat-timeout reconnects and scheduled
    // reconnects can fire back-to-back, and a stale in-flight socket must
    // never replace the current one (duplicate-socket storm).
    final generation = ++_connectGeneration;
    _socketSub?.cancel();
    _socket?.sink.close();
    String? accessToken;
    if (accessTokenProvider != null) {
      try {
        accessToken = await accessTokenProvider!().timeout(
          const Duration(seconds: 20),
        );
      } on RelayTokenException catch (e) {
        _log('[relay] token refresh failed: ${e.reason}');
        if (generation != _connectGeneration || _disposed) return;
        if (e.reason == 'auth-required') {
          _intentionallyClosed = true;
          _setState(RelayState.error);
          _failureController.add(RelayFailure(e.reason, e.message));
          return;
        }
        _handleSocketClosed(1006, e.reason);
        return;
      } catch (e) {
        _log('[relay] token refresh failed');
        if (generation == _connectGeneration) {
          _handleSocketClosed(1006, e.toString());
        }
        return;
      }
    }
    if (params.passHash.isEmpty &&
        (accessToken == null || accessToken.isEmpty)) {
      _log('[relay] v2 link without a relay token; auth required');
      _intentionallyClosed = true;
      _setState(RelayState.error);
      _failureController.add(const RelayFailure(
        'auth-required',
        'Sign in to ZCode to use v4 pairing links.',
      ));
      return;
    }
    final uri = (accessToken != null && accessToken.isNotEmpty)
        ? params.v2RelayWsUri(accessToken)
        : params.relayWsUri;
    final v2 = accessToken != null && accessToken.isNotEmpty;
    _log('[relay] connecting $uri (gen $generation)');
    WebSocketChannel socket;
    try {
      // IOWebSocketChannel carries extra handshake headers through the
      // HTTP upgrade request (the plain WebSocketChannel.connect factory
      // does not expose them). v2 auth is the token query param; cookies
      // are not attached on that path.
      socket = IOWebSocketChannel.connect(
        uri,
        headers: !v2 && handshakeHeaders.isNotEmpty ? handshakeHeaders : null,
      );
      await socket.ready;
    } catch (e) {
      _log('[relay] connect failed: $e');
      if (generation == _connectGeneration) {
        _handleSocketClosed(1006, e.toString());
      }
      return;
    }
    if (_disposed || generation != _connectGeneration) {
      try {
        await socket.sink.close();
      } catch (_) {}
      return;
    }
    _socket = socket;
    _socketSub = socket.stream.listen(
      _handleRawMessage,
      onError: (e) => _log('[relay] socket error: $e'),
      onDone: () =>
          _handleSocketClosed(socket.closeCode ?? 1006, socket.closeReason),
    );
    _setState(RelayState.authenticating);
    // v2 `auth_init` is a strict object: type, device_sid, optional meta,
    // optional client_ts. The role lives in the token (`terminal`), and an
    // extra `role` field is rejected. v3 still sends `role`.
    _send({
      'type': 'auth_init',
      if (!v2) 'role': 'terminal',
      'device_sid': params.deviceSid,
      'meta': {
        'platform': remotePlatformName(),
        'version': params.appVersion ?? 'web',
        'name': remoteAppName,
      },
      'client_ts': _nowSeconds(),
    });
  }

  void _send(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null) return;
    _log('[relay] >> ${jsonEncode(frame)}');
    socket.sink.add(jsonEncode(frame));
  }

  /// Outbound data payloads are queued while unpaired (reconnecting /
  /// waiting) and flushed once the relay reports `matched` — otherwise
  /// requests sent during a reconnect vanish into a dead socket and the
  /// caller hangs until timeout.
  final _outboundQueue = <Map<String, dynamic>>[];

  void sendPayload(Map<String, dynamic> payload) {
    if (state != RelayState.paired || _socket == null) {
      if (_outboundQueue.length < 100) {
        _log('[relay] queued (state=$state): ${payload['zcode_type']}');
        _outboundQueue.add(payload);
      }
      return;
    }
    _send({
      'type': 'data',
      'payload': payload,
      'client_ts': _nowSeconds(),
    });
  }

  void _flushOutboundQueue() {
    if (_outboundQueue.isEmpty) return;
    _log('[relay] flushing ${_outboundQueue.length} queued payload(s)');
    final queued = List<Map<String, dynamic>>.from(_outboundQueue);
    _outboundQueue.clear();
    for (final payload in queued) {
      _send({
        'type': 'data',
        'payload': payload,
        'client_ts': _nowSeconds(),
      });
    }
  }

  void _handleRawMessage(dynamic data) {
    Map<String, dynamic>? frame;
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);
      _log('[relay] << $text');
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded.containsKey('type')) {
        frame = decoded;
      }
    } catch (e) {
      _log('[relay] bad frame: $e');
      return;
    }
    if (frame == null) return;
    switch (frame['type']) {
      case 'auth_challenge':
        if (params.passHash.isEmpty) {
          // v4 links carry no HMAC key: a challenge we cannot answer means
          // the cookie session is missing or expired. Fail fast with a
          // reason the UI can act on (re-login) instead of waiting for the
          // relay's AUTH_FAILED drop.
          _log('[relay] challenged without a proof key; auth required');
          _intentionallyClosed = true;
          _setState(RelayState.error);
          _failureController.add(const RelayFailure(
            'auth-required',
            'Sign in to ZCode to use v4 pairing links.',
          ));
          _socket?.sink.close();
          return;
        }
        _send({
          'type': 'auth_response',
          'device_sid': params.deviceSid,
          'proof': calculateProof(
            passHash: params.passHash,
            nonce: frame['nonce'] as String? ?? '',
            role: 'terminal',
            deviceSid: params.deviceSid,
          ),
          'client_ts': _nowSeconds(),
        });
        break;
      case 'auth_ack':
      case 'pair_status_ack':
        _applyPairStatus(frame['pair_status'] as String?);
        break;
      case 'data':
        final payload = frame['payload'];
        if (payload is Map<String, dynamic>) {
          _payloadController.add(payload);
        }
        break;
      case 'error':
        _handleRelayError(
            frame['code'] as String?, frame['message'] as String?);
        break;
    }
  }

  void _applyPairStatus(String? status) {
    _lastPairStatusAckAt = DateTime.now();
    // Canonical v4 value is `waiting_terminal`; accept legacy `waiting` too.
    final isWaiting = status == 'waiting' || status == 'waiting_terminal';
    if (isWaiting) {
      if (_wasPaired) {
        _clearWaitingTimer();
        _setState(RelayState.waiting);
        _startHeartbeat();
        // A reconnecting mobile that was already paired should be matched
        // immediately; if the server keeps saying "waiting", force another
        // reconnect instead of hanging forever.
        _rewaitTimer?.cancel();
        _rewaitTimer = Timer(reconnectWaitTimeout, () {
          if (_wasPaired && state == RelayState.waiting && !_disposed) {
            _log('[relay] re-pair stuck in waiting, reconnecting');
            _reconnect();
          }
        });
      } else {
        _setState(RelayState.waiting);
        _startWaitingTimer();
      }
      return;
    }
    if (status == 'matched') {
      _rewaitTimer?.cancel();
      _reconnectAttempt = 0;
      _clearWaitingTimer();
      _setState(RelayState.paired);
      _wasPaired = true;
      _startHeartbeat();
      _flushOutboundQueue();
    }
  }

  void _handleRelayError(String? code, String? message) {
    _log('[relay] error frame: $code $message');
    if (code == 'KICKED') {
      _setState(RelayState.kicked);
      _intentionallyClosed = true;
      _failureController.add(RelayFailure('kicked', message));
      _socket?.sink.close();
    }
  }

  void _handleSocketClosed(int code, String? reason) {
    if (_disposed) return;
    _stopHeartbeat();
    _clearWaitingTimer();
    final mapped = relayCloseReason(code);
    _log('[relay] closed code=$code reason=$reason mapped=$mapped');
    if (_intentionallyClosed) return;
    if (_wasPaired || mapped == 'desktop-disconnected') {
      _scheduleReconnect();
      return;
    }
    _setState(RelayState.error);
    _failureController.add(RelayFailure(
      mapped ?? 'relay-unavailable',
      reason ?? 'connection closed ($code)',
    ));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (state != RelayState.paired && state != RelayState.waiting) return;
      if (DateTime.now().difference(_lastPairStatusAckAt) >
          heartbeatAckTimeout) {
        _log('[relay] heartbeat ack timeout, reconnecting');
        _reconnect();
        return;
      }
      _send({
        'type': 'pair_status_query',
        'client_ts': _nowSeconds(),
      });
    });
  }

  void _stopHeartbeat() => _heartbeatTimer?.cancel();

  void _startWaitingTimer() {
    _clearWaitingTimer();
    _waitingTimer = Timer(waitingTimeout, () {
      if (state == RelayState.waiting && !_wasPaired) {
        _setState(RelayState.error);
        _failureController.add(const RelayFailure(
          'invalid-mobile-connection',
          'Desktop did not match this mobile connection before the waiting timeout.',
        ));
      }
    });
  }

  void _clearWaitingTimer() {
    _waitingTimer?.cancel();
    _rewaitTimer?.cancel();
  }

  void _scheduleReconnect() {
    if (_disposed || _intentionallyClosed) return;
    _setState(RelayState.reconnecting);
    final delayMs =
        (1000 * (1 << _reconnectAttempt.clamp(0, 4))).clamp(1000, 15000);
    _reconnectAttempt += 1;
    _log('[relay] reconnect in ${delayMs}ms (attempt $_reconnectAttempt)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_disposed) _connect();
    });
  }

  Future<void> _reconnect() async {
    _reconnectTimer?.cancel();
    // Go through `reconnecting` so listeners (bridge recovery) know the
    // connection dropped — the heartbeat-timeout path used to skip this and
    // bridges were never recovered after re-pairing.
    _setState(RelayState.reconnecting);
    await _connect();
  }

  /// Diagnostics: forcefully drops the socket to exercise the
  /// reconnect/bridge-recovery path (used by integration probes).
  Future<void> debugDropSocket() async {
    _intentionallyClosed = false;
    await _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    try {
      await socket?.sink.close(3000, 'debug-drop');
    } catch (_) {}
    _handleSocketClosed(1006, 'debug-drop');
  }

  Future<void> dispose() async {
    _disposed = true;
    _intentionallyClosed = true;
    _stopHeartbeat();
    _clearWaitingTimer();
    _reconnectTimer?.cancel();
    _rewaitTimer?.cancel();
    await _socketSub?.cancel();
    _socket?.sink.close();
    _setState(RelayState.closed);
    await _payloadController.close();
    await _failureController.close();
  }
}
