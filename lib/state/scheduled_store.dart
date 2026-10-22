import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../protocol/id.dart';
import 'app_kv.dart';
import 'device_session.dart';
import 'device_store.dart';

/// One scheduled "send a message to a device" item. Minimal automation
/// built on the app-side timer plus createSession/sendText.
class ScheduledMessage {
  final String id;
  final String deviceId;

  /// Label snapshot for display (device may be renamed/deleted later).
  final String deviceLabel;
  final String text;

  /// Epoch ms when the message should be sent.
  final int fireAt;
  final bool sent;
  final int attempts;
  final String? lastError;

  const ScheduledMessage({
    required this.id,
    required this.deviceId,
    required this.deviceLabel,
    required this.text,
    required this.fireAt,
    this.sent = false,
    this.attempts = 0,
    this.lastError,
  });

  ScheduledMessage copyWith({
    bool? sent,
    int? attempts,
    String? lastError,
    bool clearError = false,
  }) =>
      ScheduledMessage(
        id: id,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
        text: text,
        fireAt: fireAt,
        sent: sent ?? this.sent,
        attempts: attempts ?? this.attempts,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'deviceLabel': deviceLabel,
        'text': text,
        'fireAt': fireAt,
        if (sent) 'sent': sent,
        if (attempts > 0) 'attempts': attempts,
        if (lastError != null) 'lastError': lastError,
      };

  factory ScheduledMessage.fromJson(Map<String, dynamic> j) =>
      ScheduledMessage(
        id: j['id'] as String? ?? generateUuid(),
        deviceId: j['deviceId'] as String? ?? '',
        deviceLabel: j['deviceLabel'] as String? ?? '?',
        text: j['text'] as String? ?? '',
        fireAt: j['fireAt'] as int? ?? 0,
        sent: j['sent'] == true,
        attempts: j['attempts'] as int? ?? 0,
        lastError: j['lastError'] as String?,
      );
}

class ScheduledStore extends ChangeNotifier {
  static const _key = 'zic_scheduled_v1';
  final List<ScheduledMessage> _items = [];
  bool _loaded = false;

  List<ScheduledMessage> get items => List.unmodifiable(_items);
  bool get loaded => _loaded;

  Future<void> load() async {
    final raw = await AppKv.instance.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _items
          ..clear()
          ..addAll(list
              .whereType<Map<String, dynamic>>()
              .map(ScheduledMessage.fromJson));
      } catch (_) {
        // Corrupt storage should not crash the app; start empty.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    await AppKv.instance.setString(
        _key, jsonEncode(_items.map((m) => m.toJson()).toList()));
  }

  Future<ScheduledMessage> add({
    required String deviceId,
    required String deviceLabel,
    required String text,
    required int fireAt,
  }) async {
    final m = ScheduledMessage(
      id: generateUuid(),
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      text: text,
      fireAt: fireAt,
    );
    _items.add(m);
    _items.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    notifyListeners();
    await _save();
    return m;
  }

  Future<void> remove(String id) async {
    _items.removeWhere((m) => m.id == id);
    notifyListeners();
    await _save();
  }

  /// Due = unsent, past fire time, and not exhausted.
  List<ScheduledMessage> due(int nowMs, {int maxAttempts = 3}) => _items
      .where((m) => !m.sent && m.fireAt <= nowMs && m.attempts < maxAttempts)
      .toList();

  void markSent(String id) {
    _update(id, (m) => m.copyWith(sent: true, clearError: true));
  }

  void markAttempt(String id) {
    _update(id, (m) => m.copyWith(attempts: m.attempts + 1));
  }

  void markFailed(String id, String error) {
    _update(id, (m) => m.copyWith(lastError: error));
  }

  void _update(String id, ScheduledMessage Function(ScheduledMessage) f) {
    final i = _items.indexWhere((m) => m.id == id);
    if (i == -1) return;
    _items[i] = f(_items[i]);
    notifyListeners();
    _save();
  }
}

/// Fires due [ScheduledMessage]s by creating a task on the target device
/// via the native protocol. App-lifetime service; delivery is best-effort
/// while the app is alive (foreground timer).
class MessageScheduler {
  final ScheduledStore store;
  final DeviceStore devices;
  final DeviceSessionHub hub;
  static const maxAttempts = 3;
  static const tickInterval = Duration(seconds: 15);

  Timer? _timer;
  bool _disposed = false;
  bool _sending = false;

  MessageScheduler({
    required this.store,
    required this.devices,
    required this.hub,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_disposed || _sending) return;
    _sending = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final m in store.due(now, maxAttempts: maxAttempts)) {
        await _trySend(m);
        if (_disposed) return;
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _trySend(ScheduledMessage m) async {
    final device =
        devices.devices.where((d) => d.id == m.deviceId).firstOrNull;
    if (device == null) {
      store.markAttempt(m.id);
      store.markFailed(m.id, 'device-removed');
      return;
    }
    store.markAttempt(m.id);
    final session = hub.ensure(device);
    if (session == null) {
      store.markFailed(m.id, 'native-list-disabled');
      return;
    }
    try {
      final deadline =
          DateTime.now().add(const Duration(seconds: 20));
      while (session.status != DeviceStatus.connected &&
          DateTime.now().isBefore(deadline) &&
          !_disposed) {
        if (session.status == DeviceStatus.error) {
          throw StateError(session.error ?? 'connection failed');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (session.status != DeviceStatus.connected) {
        throw TimeoutException('device not connected in time');
      }
      await session.createTaskWithMessage(m.text);
      store.markSent(m.id);
      debugPrint('[scheduler] delivered ${m.id}');
    } catch (e) {
      store.markFailed(m.id, '$e');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
