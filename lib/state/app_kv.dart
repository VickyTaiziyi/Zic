import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-private key-value store.
///
/// On a device this is one JSON file in the application files directory.
/// Reads and writes go through `dart:io`. The SharedPreferences plugin is
/// not on this path: on some phones its channel never answers, the home
/// screen drops into temporary mode, and the login dies with the process.
///
/// `flutter test` keeps the SharedPreferences mock so existing tests that
/// call [SharedPreferences.setMockInitialValues] still seed this store.
class AppKv {
  AppKv._();

  static final AppKv instance = AppKv._();

  static const _channel = MethodChannel('dev.zic.remote/store');
  static const _fileName = 'zic_kv.json';

  Map<String, Object>? _memory;
  Directory? _dir;
  Future<void>? _opening;
  bool _usingPrefs = false;
  Future<void> _writeQueue = Future<void>.value();

  /// True after [open] when the file (or the test mock) could not be used.
  /// Writes then stay in memory and the home screen shows temporary mode.
  bool degraded = false;

  /// Forces the file backend onto [dir]. Takes precedence over the test mock.
  @visibleForTesting
  void debugUseDirectory(Directory dir) {
    _forcedDir = dir;
    _usingPrefs = false;
    _memory = null;
    _dir = null;
    _opening = null;
    degraded = false;
  }

  Directory? _forcedDir;

  @visibleForTesting
  void debugReset() {
    _forcedDir = null;
    _usingPrefs = false;
    _memory = null;
    _dir = null;
    _opening = null;
    degraded = false;
    _writeQueue = Future<void>.value();
  }

  /// Drops the in-memory copy so the next read comes back from disk.
  @visibleForTesting
  void debugForgetMemory() {
    _memory = null;
    _opening = null;
  }

  Future<void> open() {
    return _opening ??= _open();
  }

  Future<void> _open() async {
    if (_forcedDir != null) {
      _dir = _forcedDir;
      _usingPrefs = false;
      _memory = _readFile();
      degraded = false;
      return;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _usingPrefs = true;
      await SharedPreferences.getInstance();
      degraded = false;
      return;
    }
    try {
      final path = await _channel
          .invokeMethod<String>('filesDir')
          .timeout(const Duration(seconds: 3));
      if (path == null || path.isEmpty) {
        throw StateError('empty filesDir');
      }
      final dir = Directory(path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      _usingPrefs = false;
      _memory = _readFile();
      degraded = false;
    } catch (_) {
      _memory = {};
      _usingPrefs = false;
      degraded = true;
    }
  }

  Map<String, Object> _readFile() {
    final file = File('${_dir!.path}/$_fileName');
    if (!file.existsSync()) return {};
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return decoded.map((k, v) => MapEntry('$k', v as Object));
  }

  Future<void> _flush() {
    final run = _writeQueue.then((_) async {
      if (_usingPrefs || _dir == null || _memory == null) return;
      final file = File('${_dir!.path}/$_fileName');
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(_memory), flush: true);
      if (file.existsSync()) file.deleteSync();
      tmp.renameSync(file.path);
    });
    _writeQueue = run.then((_) {}, onError: (_, __) {});
    return run;
  }

  Future<void> _retryOpen() async {
    if (!degraded) return;
    _opening = null;
    _memory = null;
    await open();
  }

  Future<String?> getString(String key) async {
    await open();
    if (_usingPrefs) {
      return (await SharedPreferences.getInstance()).getString(key);
    }
    final value = _memory?[key];
    return value is String ? value : null;
  }

  Future<bool?> getBool(String key) async {
    await open();
    if (_usingPrefs) {
      return (await SharedPreferences.getInstance()).getBool(key);
    }
    final value = _memory?[key];
    return value is bool ? value : null;
  }

  Future<int?> getInt(String key) async {
    await open();
    if (_usingPrefs) {
      return (await SharedPreferences.getInstance()).getInt(key);
    }
    final value = _memory?[key];
    return value is int ? value : null;
  }

  Future<Set<String>> getKeys() async {
    await open();
    if (_usingPrefs) {
      return (await SharedPreferences.getInstance()).getKeys();
    }
    return Set<String>.from(_memory!.keys);
  }

  Future<void> setString(String key, String value) async {
    await open();
    if (degraded) await _retryOpen();
    if (_usingPrefs) {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(key, value);
      if (!ok) throw StateError('prefs write failed');
      return;
    }
    if (degraded || _memory == null) {
      throw StateError('local store unavailable');
    }
    _memory![key] = value;
    await _flush();
    degraded = false;
  }

  Future<void> setBool(String key, bool value) async {
    await open();
    if (degraded) await _retryOpen();
    if (_usingPrefs) {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setBool(key, value);
      if (!ok) throw StateError('prefs write failed');
      return;
    }
    if (degraded || _memory == null) {
      throw StateError('local store unavailable');
    }
    _memory![key] = value;
    await _flush();
    degraded = false;
  }

  Future<void> setInt(String key, int value) async {
    await open();
    if (degraded) await _retryOpen();
    if (_usingPrefs) {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setInt(key, value);
      if (!ok) throw StateError('prefs write failed');
      return;
    }
    if (degraded || _memory == null) {
      throw StateError('local store unavailable');
    }
    _memory![key] = value;
    await _flush();
    degraded = false;
  }

  Future<void> remove(String key) async {
    await open();
    if (degraded) await _retryOpen();
    if (_usingPrefs) {
      await (await SharedPreferences.getInstance()).remove(key);
      return;
    }
    if (degraded || _memory == null) {
      throw StateError('local store unavailable');
    }
    _memory!.remove(key);
    await _flush();
    degraded = false;
  }
}
