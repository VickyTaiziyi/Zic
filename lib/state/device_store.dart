import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../protocol/connection_params.dart';
import '../protocol/id.dart';
import 'app_kv.dart';

class Device {
  final String id;
  String label;
  final String url;
  final int addedAt;
  int? lastUsedAt;

  /// Times the device was opened (WebView or native actions). Purely local
  /// usage stats; absent in old backups and defaults to 0.
  int useCount;

  /// User-pinned devices float to the top of the list.
  bool pinned;

  /// Explicit order among siblings (lower = higher). Assigned on add /
  /// reorder; absent in old backups and back-filled from list index.
  int sortOrder;

  Device({
    required this.id,
    required this.label,
    required this.url,
    required this.addedAt,
    this.lastUsedAt,
    this.useCount = 0,
    this.pinned = false,
    this.sortOrder = 0,
  });

  factory Device.fromUrl(String url, {String? label, int sortOrder = 0}) {
    final params = RemoteConnectionParams.parse(url);
    return Device(
      id: generateUuid(),
      label: (label != null && label.trim().isNotEmpty)
          ? label.trim()
          : (params?.deviceName ??
              params?.source.host ??
              '未命名设备'),
      url: url.trim(),
      addedAt: DateTime.now().millisecondsSinceEpoch,
      sortOrder: sortOrder,
    );
  }

  RemoteConnectionParams? get params => RemoteConnectionParams.parse(url);

  /// Prefer the URL's `theme=dark|light` when present.
  ThemeModeHint? get themeHint {
    switch (params?.theme?.toLowerCase()) {
      case 'dark':
        return ThemeModeHint.dark;
      case 'light':
        return ThemeModeHint.light;
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'url': url,
        'addedAt': addedAt,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt,
        if (useCount > 0) 'useCount': useCount,
        if (pinned) 'pinned': true,
        'sortOrder': sortOrder,
      };

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: j['id'] as String? ?? generateUuid(),
        label: j['label'] as String? ?? '未命名设备',
        url: j['url'] as String? ?? '',
        addedAt: j['addedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        lastUsedAt: j['lastUsedAt'] as int?,
        useCount: j['useCount'] as int? ?? 0,
        pinned: j['pinned'] == true,
        sortOrder: j['sortOrder'] as int? ?? 0,
      );
}

/// Lightweight theme hint from a device URL (avoids importing Material here).
enum ThemeModeHint { dark, light }

class DeviceStore extends ChangeNotifier {
  static const _key = 'zic_devices_v1';
  final List<Device> _devices = [];
  bool _loaded = false;

  /// True only after a successful disk read. Saves refuse to run before
  /// that, so a timed-out load cannot overwrite a previously stored list
  /// with an empty one.
  bool _diskReady = false;

  /// Serializes disk reads and writes. A late read must not replace a list
  /// the user already edited, and two writes must not pass each other.
  Future<void> _diskQueue = Future<void>.value();

  /// Devices sorted for display: pinned first, then [Device.sortOrder].
  List<Device> get devices {
    final list = List<Device>.from(_devices);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final o = a.sortOrder.compareTo(b.sortOrder);
      if (o != 0) return o;
      return a.addedAt.compareTo(b.addedAt);
    });
    return List.unmodifiable(list);
  }

  bool get loaded => _loaded;

  /// True while running on the in-memory fallback (local storage could
  /// not be loaded); the UI shows a degraded-mode banner.
  bool degraded = false;

  /// Emergency entry for a storage layer that never finishes loading:
  /// mark the store loaded so the shell can render. Later [addUrl] still
  /// tries the disk; it will not wipe a list it has not successfully read.
  void forceLoadedInMemory() {
    if (_loaded) return;
    _loaded = true;
    degraded = true;
    notifyListeners();
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _diskQueue.then((_) => action());
    _diskQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> load() async {
    try {
      await _serialized(_applyDisk);
      degraded = false;
    } catch (_) {
      degraded = true;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Reads the saved list and merges anything already held in memory
  /// (a device added while this read was still waiting).
  Future<void> _applyDisk() async {
    await AppKv.instance.open();
    if (AppKv.instance.degraded) {
      throw StateError('local store unavailable');
    }
    final raw = await AppKv.instance.getString(_key);
    final fromDisk = <Device>[];
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List<dynamic>;
      fromDisk.addAll(list
          .whereType<Map>()
          .map((e) => Device.fromJson(Map<String, dynamic>.from(e)))
          .where((d) => d.url.isNotEmpty));
    }
    // Snapshot after the await: mutations during the read must win.
    final pending = List<Device>.from(_devices);
    _devices
      ..clear()
      ..addAll(mergeStoredDevices(fromDisk, pending));
    _backfillSortOrders();
    _diskReady = true;
    if (_loaded) {
      degraded = false;
      notifyListeners();
    }
  }

  /// Old backups lack sortOrder — assign contiguous indices once.
  void _backfillSortOrders() {
    var needs = false;
    for (var i = 0; i < _devices.length; i++) {
      if (_devices[i].sortOrder != i &&
          _devices.every((d) => d.sortOrder == 0)) {
        needs = true;
        break;
      }
    }
    if (!needs && _devices.length > 1) {
      final allZero = _devices.every((d) => d.sortOrder == 0);
      if (allZero) needs = true;
    }
    if (!needs) return;
    for (var i = 0; i < _devices.length; i++) {
      _devices[i].sortOrder = i;
    }
  }

  Future<void> _save() {
    // Queued behind any in-flight read. If that read has not finished, this
    // write reads first and merges, and it does not write when the read fails.
    return _serialized(() async {
      try {
        if (!_diskReady) await _applyDisk();
        if (!_diskReady) {
          degraded = true;
          return;
        }
        await AppKv.instance.setString(
          _key,
          jsonEncode(_devices.map((d) => d.toJson()).toList()),
        );
        degraded = false;
      } catch (_) {
        degraded = true;
      }
    });
  }

  /// Adds a device from a pasted/scanned URL. The same desktop (`sid`)
  /// updates the stored link in place, so a refreshed pairing URL does not
  /// create a second card and does not drop pin / use count.
  Future<Device> addUrl(String url, {String? label}) async {
    final trimmed = url.trim();
    final parsed = RemoteConnectionParams.parse(trimmed);
    final sid = parsed?.deviceSid;
    final existing = sid == null
        ? _devices.where((d) => d.url == trimmed).firstOrNull
        : _devices.where((d) => d.params?.deviceSid == sid).firstOrNull;
    if (existing != null) {
      if (existing.url == trimmed && (label == null || label.trim().isEmpty)) {
        return existing;
      }
      final nextLabel = (label != null && label.trim().isNotEmpty)
          ? label.trim()
          : (parsed?.deviceName != null &&
                  existing.label == (existing.params?.deviceName ?? existing.label))
              ? parsed!.deviceName!
              : existing.label;
      final index = _devices.indexWhere((d) => d.id == existing.id);
      final updated = Device(
        id: existing.id,
        label: nextLabel,
        url: trimmed,
        addedAt: existing.addedAt,
        lastUsedAt: existing.lastUsedAt,
        useCount: existing.useCount,
        pinned: existing.pinned,
        sortOrder: existing.sortOrder,
      );
      if (index >= 0) _devices[index] = updated;
      notifyListeners();
      await _save();
      return _storedAfterSave(updated);
    }
    final maxOrder = _devices.isEmpty
        ? -1
        : _devices.map((d) => d.sortOrder).reduce((a, b) => a > b ? a : b);
    final device = Device.fromUrl(trimmed, label: label, sortOrder: maxOrder + 1);
    _devices.add(device);
    notifyListeners();
    await _save();
    return _storedAfterSave(device);
  }

  Future<void> remove(String id) async {
    _devices.removeWhere((d) => d.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> rename(String id, String label) async {
    final d = _devices.firstWhere((e) => e.id == id, orElse: () => throw StateError('not found'));
    d.label = label.trim().isEmpty ? d.label : label.trim();
    notifyListeners();
    await _save();
  }

  Future<void> setPinned(String id, bool pinned) async {
    final d = _devices.where((e) => e.id == id).firstOrNull;
    if (d == null || d.pinned == pinned) return;
    d.pinned = pinned;
    notifyListeners();
    await _save();
  }

  /// Reorders within the currently displayed list. [oldIndex]/[newIndex]
  /// are indices into [devices] where [newIndex] is the destination after
  /// the item at [oldIndex] has been removed (ReorderableListView
  /// `onReorderItem` convention). Pin state is unchanged.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final visible = devices.toList();
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex < 0 || newIndex >= visible.length) return;
    if (oldIndex == newIndex) return;
    final item = visible.removeAt(oldIndex);
    visible.insert(newIndex, item);
    for (var i = 0; i < visible.length; i++) {
      visible[i].sortOrder = i;
    }
    notifyListeners();
    await _save();
  }

  Future<void> touch(String id) async {
    final d = _devices.where((d) => d.id == id).firstOrNull;
    if (d == null) return;
    d.lastUsedAt = DateTime.now().millisecondsSinceEpoch;
    d.useCount += 1;
    notifyListeners();
    await _save();
  }

  /// After a save, the queued disk merge may keep the on-disk id for this sid.
  Device _storedAfterSave(Device device) {
    final sid = device.params?.deviceSid;
    final stored = sid == null
        ? _devices.where((d) => d.id == device.id).firstOrNull
        : _devices.where((d) => d.params?.deviceSid == sid).firstOrNull;
    return stored ?? device;
  }

  /// Backup/export envelope.
  String exportJson() => jsonEncode({
        'app': 'zic',
        'format': 'devices',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'devices': _devices.map((d) => d.toJson()).toList(),
      });

  /// Imports devices from [exportJson] output. Skips duplicates and empty
  /// URLs. Returns the number of devices added.
  Future<int> importJson(String raw) async {
    final data = jsonDecode(raw);
    final list = (data is Map<String, dynamic> ? data['devices'] : data)
        as List<dynamic>;
    var added = 0;
    for (final item in list.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final url = (map['url'] as String? ?? '').trim();
      if (url.isEmpty) continue;
      final parsed = RemoteConnectionParams.parse(url);
      final sid = parsed?.deviceSid;
      final existingIndex = sid == null
          ? _devices.indexWhere((d) => d.url == url)
          : _devices.indexWhere((d) => d.params?.deviceSid == sid);
      if (existingIndex >= 0) {
        final existing = _devices[existingIndex];
        if (existing.url != url) {
          _devices[existingIndex] = overlayStoredDevice(
            existing,
            Device.fromJson(map),
          );
          added++;
        }
        continue;
      }
      _devices.add(Device.fromJson(map));
      added++;
    }
    if (added > 0) {
      _backfillSortOrders();
      notifyListeners();
      await _save();
    }
    return added;
  }
}

/// Collapses one desktop (`sid`) to one card. [pending] wins the URL and
/// label; the earlier id, pin, and the higher use count are kept.
List<Device> mergeStoredDevices(List<Device> disk, List<Device> pending) {
  final merged = <Device>[];
  final bySid = <String, int>{};
  final byUrl = <String, int>{};

  void put(Device device) {
    final sid = device.params?.deviceSid;
    final index = sid != null ? bySid[sid] : byUrl[device.url];
    if (index == null) {
      final i = merged.length;
      merged.add(device);
      if (sid != null) bySid[sid] = i;
      if (device.url.isNotEmpty) byUrl[device.url] = i;
      return;
    }
    final kept = merged[index];
    if (kept.url != device.url) byUrl.remove(kept.url);
    merged[index] = overlayStoredDevice(kept, device);
    if (sid != null) bySid[sid] = index;
    if (device.url.isNotEmpty) byUrl[device.url] = index;
  }

  for (final device in disk) {
    put(device);
  }
  for (final device in pending) {
    put(device);
  }
  return merged;
}

/// [newer] supplies the link and label. [kept] supplies the stable id.
Device overlayStoredDevice(Device kept, Device newer) {
  final keptUsed = kept.lastUsedAt;
  final newerUsed = newer.lastUsedAt;
  final int? lastUsed;
  if (keptUsed == null) {
    lastUsed = newerUsed;
  } else if (newerUsed == null) {
    lastUsed = keptUsed;
  } else {
    lastUsed = keptUsed > newerUsed ? keptUsed : newerUsed;
  }
  return Device(
    id: kept.id,
    label: newer.label,
    url: newer.url,
    addedAt: kept.addedAt < newer.addedAt ? kept.addedAt : newer.addedAt,
    lastUsedAt: lastUsed,
    useCount: kept.useCount > newer.useCount ? kept.useCount : newer.useCount,
    pinned: kept.pinned || newer.pinned,
    sortOrder: kept.sortOrder,
  );
}
