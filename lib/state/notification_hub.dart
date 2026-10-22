import 'dart:async';

import '../notifications/notification_service.dart';
import '../notifications/notify_rules.dart';
import '../ui/ui_settings.dart';
import 'device_session.dart';

/// Bridges device sessions to local notifications:
/// - task events ride the live sessions-index stream (no extra RPC),
/// - off-peak results poll every 60s,
/// - automation runs poll every 120s,
/// all gated by the notification switches in settings. Errors are always
/// silent — notifications are an enhancement, never a failure surface.
class NotificationHub {
  final NotificationService service;
  final UiSettings ui;

  /// Resolves a device label for notification bodies.
  final String Function(String deviceId) deviceLabelOf;

  NotificationHub({
    required this.service,
    required this.ui,
    required this.deviceLabelOf,
  });

  static const offPeakPollInterval = Duration(seconds: 60);
  static const automationPollInterval = Duration(seconds: 120);

  final _tracked = <String, NotifiableSession>{};
  final _taskPhases = <String, Map<String, String>>{};
  final _offPeakStatuses = <String, Map<String, String>>{};
  final _autoLastRunAt = <String, Map<String, int>>{};
  Timer? _offPeakTimer;
  Timer? _autoTimer;
  bool _disposed = false;

  String _tr(String key) => trLocale(ui.locale, key);

  bool get _master => ui.notificationsEnabled && service.isReady;

  /// Reconciles tracked sessions with the live hub sessions (main wires
  /// this to hub changes).
  void syncWith(Iterable<NotifiableSession> sessions) {
    if (_disposed) return;
    final seen = <String>{};
    for (final session in sessions) {
      seen.add(session.deviceId);
      if (!_tracked.containsKey(session.deviceId)) {
        _tracked[session.deviceId] = session;
        session.addListener(() => _onSessionChanged(session));
        // Baseline the task phases so pre-existing running tasks don't
        // fire completion notifications on the first tick.
        _snapshotPhases(session);
      }
    }
    for (final id in _tracked.keys.toList()) {
      if (!seen.contains(id)) {
        _tracked.remove(id);
        _taskPhases.remove(id);
        // Off-peak statuses and automation lastRunAt are DEVICE facts:
        // keep them across reconnects so a WebView handover or relay flap
        // doesn't replay completion notifications for old tasks.
      }
    }
  }

  void start() {
    _offPeakTimer?.cancel();
    _autoTimer?.cancel();
    _offPeakTimer =
        Timer.periodic(offPeakPollInterval, (_) => pollOffPeakNow());
    _autoTimer =
        Timer.periodic(automationPollInterval, (_) => pollAutomationsNow());
  }

  void _snapshotPhases(NotifiableSession session) {
    final sessions = session.sessions;
    if (sessions == null) return;
    _taskPhases[session.deviceId] = {
      for (final e in sessions.list) e.sessionId: e.phase,
    };
  }

  void _onSessionChanged(NotifiableSession session) {
    if (_disposed) return;
    final sessions = session.sessions;
    if (sessions == null) return;
    final prev = _taskPhases.putIfAbsent(session.deviceId, () => {});
    final events = taskCompletionEvents(
      previousPhases: prev,
      sessions: [
        for (final e in sessions.list)
          (sessionId: e.sessionId, title: e.title, phase: e.phase),
      ],
    );
    // Track phases even while silenced so re-enabling doesn't replay
    // history.
    _snapshotPhases(session);
    if (!_master || !ui.notifyTasksEnabled) return;
    for (final e in events) {
      final title = switch (e.phase) {
        'error' => _tr('notify.task.failed'),
        'completedInterrupted' => _tr('notify.task.interrupted'),
        _ => _tr('notify.task.done'),
      };
      unawaited(service.show(
        NotifyChannel.tasks,
        NotificationService.stableId('${session.deviceId}:${e.sessionId}'),
        title,
        e.title,
        {
          'type': 'task',
          'deviceId': session.deviceId,
          'sessionId': e.sessionId,
          'title': e.title,
        },
      ));
    }
  }

  /// Polls off-peak tasks of every connected session (public so tests and
  /// manual refreshes can drive it).
  Future<void> pollOffPeakNow() async {
    if (_disposed || !_master || !ui.notifyOffPeakEnabled) return;
    for (final session in _tracked.values.toList()) {
      if (session.status != DeviceStatus.connected) continue;
      await _pollOffPeak(session);
      if (_disposed) return;
    }
  }

  Future<void> _pollOffPeak(NotifiableSession session) async {
    try {
      final tasks = await session.offPeak.list();
      if (_disposed) return;
      final prev = _offPeakStatuses.putIfAbsent(session.deviceId, () => {});
      final coldStart = prev.isEmpty && tasks.isNotEmpty;
      final events = offPeakEvents(previousStatuses: prev, tasks: tasks);
      _offPeakStatuses[session.deviceId] = {
        for (final t in tasks) t.id: t.status,
      };
      if (coldStart) return; // first sight baselines silently
      if (!_master || !ui.notifyOffPeakEnabled) return;
      for (final e in events) {
        final title =
            e.failed ? _tr('notify.offPeak.failed') : _tr('notify.offPeak.done');
        final body = e.task.title.isEmpty ? e.task.prompt : e.task.title;
        unawaited(service.show(
          NotifyChannel.offPeak,
          NotificationService.stableId(
              '${session.deviceId}:offpeak:${e.task.id}'),
          title,
          body,
          {
            'type': 'offPeak',
            'deviceId': session.deviceId,
            'sessionId': e.task.sessionId ?? e.task.conversationId,
            'title': body,
          },
        ));
      }
    } catch (_) {
      // Offline desktops / absent channels are expected on every poll.
    }
  }

  /// Polls automation runs of every connected session.
  Future<void> pollAutomationsNow() async {
    if (_disposed || !_master || !ui.notifyAutoEnabled) return;
    for (final session in _tracked.values.toList()) {
      if (session.status != DeviceStatus.connected) continue;
      await _pollAutomations(session);
      if (_disposed) return;
    }
  }

  Future<void> _pollAutomations(NotifiableSession session) async {
    try {
      final items = await session.automation.list();
      if (_disposed) return;
      final prev = _autoLastRunAt.putIfAbsent(session.deviceId, () => {});
      final events = automationRunEvents(
          previousLastRunAt: prev, items: items);
      _autoLastRunAt[session.deviceId] = {
        for (final item in items)
          if (item.lastRunAt != null) item.id: item.lastRunAt!,
      };
      // No cold-start baseline here (unlike off-peak): a new lastRunAt on
      // the first poll IS a fresh run worth notifying; replays are already
      // impossible because the per-device cache survives reconnects.
      if (!_master || !ui.notifyAutoEnabled) return;
      for (final e in events) {
        final title =
            e.failed ? _tr('notify.auto.failed') : _tr('notify.auto.done');
        final body = e.item.title.isEmpty ? e.item.id : e.item.title;
        unawaited(service.show(
          NotifyChannel.automations,
          NotificationService.stableId(
              '${session.deviceId}:auto:${e.item.id}:${e.item.lastRunAt}'),
          title,
          body,
          {
            'type': 'auto',
            'deviceId': session.deviceId,
            'sessionId': e.item.targetTaskId,
            'title': body,
          },
        ));
      }
    } catch (_) {
      // Older desktops without the automation port land here every poll.
    }
  }

  void dispose() {
    _disposed = true;
    _offPeakTimer?.cancel();
    _autoTimer?.cancel();
    _tracked.clear();
    _taskPhases.clear();
    _offPeakStatuses.clear();
    _autoLastRunAt.clear();
  }
}
