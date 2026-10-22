import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/app_kv.dart';

enum ProbeState { pending, ok, timeout, error }

/// One startup probe's outcome. Rendered with zero platform calls so the
/// panel works even when the platform thread is wedged.
class ProbeResult {
  final String label;
  final ProbeState state;
  final int elapsedMs;
  final String? detail;

  const ProbeResult(this.label, this.state, this.elapsedMs, [this.detail]);

  String get stateLabel => switch (state) {
        ProbeState.ok => 'OK',
        ProbeState.timeout => '超时',
        ProbeState.error => '错误',
        ProbeState.pending => '检测中…',
      };
}

/// Isolated, timeout-bounded platform probes for the startup-blocked card.
/// Every probe gets its own timeout so one wedged subsystem cannot stall
/// the others; the user photographs the results and we pinpoint the
/// blocking component without adb.
class StartupDiagnostics extends ChangeNotifier {
  final List<ProbeResult> _results = [];
  List<ProbeResult> get results => List.unmodifiable(_results);
  bool get running => _running;
  bool _running = false;

  Future<void> _probe(
    String label,
    Future<void> Function() body, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final sw = Stopwatch()..start();
    try {
      await body().timeout(timeout);
      _results.add(ProbeResult(label, ProbeState.ok, sw.elapsedMilliseconds));
    } on TimeoutException {
      _results
          .add(ProbeResult(label, ProbeState.timeout, sw.elapsedMilliseconds));
    } catch (e) {
      _results.add(ProbeResult(
          label, ProbeState.error, sw.elapsedMilliseconds, '$e'.split('\n').first));
    }
    notifyListeners();
  }

  /// Runs every probe independently; hangs do not propagate.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    _results.clear();
    notifyListeners();

    // ① The storage lifeline itself — write+read-back distinguishes a full
    //    or failing disk (reads may hit cache, writes fail) from a wedged
    //    channel.
    await _probe('① 本地文件存储', () async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await AppKv.instance.setInt('zic.probe.ts', stamp);
      if (await AppKv.instance.getInt('zic.probe.ts') != stamp) {
        throw StateError('写入后读回失败（磁盘空间不足？）');
      }
    });
    // ② Lightest possible channel call.
    await _probe('② 剪贴板 Clipboard', () async {
      await Clipboard.getData(Clipboard.kTextPlain);
    });
    // ③ package_info_plus.
    await _probe('③ 应用信息 PackageInfo', () async {
      await PackageInfo.fromPlatform();
    });
    // ④ app_links liveness (a raw ping on its method channel).
    await _probe('④ 深链 AppLinks', () async {
      try {
        await const MethodChannel('com.llfbandit.app_links/status')
            .invokeMethod<String>('ping');
      } on MissingPluginException {
        // The channel not existing is itself an answer — thread alive.
      }
    });
    // ⑤ flutter_inappwebview liveness — the prime suspect on OEM wedges
    //    (plugin registration resolves the system WebView provider).
    await _probe('⑤ WebView 服务 InAppWebView', () async {
      try {
        await const MethodChannel(
                'com.pichillilorenzo/flutter_inappwebview_1_1')
            .invokeMethod('ping');
      } on MissingPluginException {
        // fine — handler answered "no such method"
      }
    });

    _running = false;
    notifyListeners();
  }
}
