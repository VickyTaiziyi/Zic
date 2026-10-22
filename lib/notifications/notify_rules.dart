import '../protocol/automation.dart';
import '../protocol/off_peak.dart';

/// Pure derivations of notification events from before/after snapshots.
/// Dependency-free so they unit-test without any platform channel.

const runningPhases = {'running', 'prewarming'};
const terminalTaskPhases = {
  'completedSuccess',
  'completedInterrupted',
  'error',
};

/// A task reached a terminal phase since the last tick.
class TaskCompletionEvent {
  final String sessionId;
  final String title;
  final String phase; // completedSuccess | completedInterrupted | error

  const TaskCompletionEvent({
    required this.sessionId,
    required this.title,
    required this.phase,
  });

  bool get failed => phase == 'error';
}

/// [previousPhases] doubles as the de-dupe: a running→terminal transition
/// fires exactly once, and re-running a task fires again on its next
/// completion (mirrors the verified zemote notify-state derivation).
List<TaskCompletionEvent> taskCompletionEvents({
  required Map<String, String> previousPhases,
  required List<({String sessionId, String title, String phase})> sessions,
}) {
  final events = <TaskCompletionEvent>[];
  final nowPhases = {for (final s in sessions) s.sessionId: s.phase};
  final byId = {for (final s in sessions) s.sessionId: s};
  previousPhases.forEach((sessionId, wasPhase) {
    if (!runningPhases.contains(wasPhase)) return;
    final now = nowPhases[sessionId];
    if (now == null || !terminalTaskPhases.contains(now)) return;
    final entry = byId[sessionId]!;
    events.add(TaskCompletionEvent(
      sessionId: sessionId,
      title: entry.title.isEmpty ? sessionId : entry.title,
      phase: now,
    ));
  });
  return events;
}

/// An off-peak task reached completed/failed since the last tick.
class OffPeakEvent {
  final OffPeakTask task;
  final bool failed;

  const OffPeakEvent(this.task, {required this.failed});
}

List<OffPeakEvent> offPeakEvents({
  required Map<String, String> previousStatuses,
  required List<OffPeakTask> tasks,
}) {
  final events = <OffPeakEvent>[];
  for (final t in tasks) {
    if (!t.terminal) continue;
    final was = previousStatuses[t.id];
    // Only notify on the transition, not on every poll of an old entry.
    if (was == t.status) continue;
    if (was == null) {
      // First sight of a terminal task is HISTORY (app cold start, or the
      // per-device status cache was rebuilt after a reconnect): baseline
      // silently, like the task-phase snapshot. Without this, every
      // reconnect replayed completion notifications for all finished
      // off-peak tasks.
      continue;
    }
    if (t.completed) events.add(OffPeakEvent(t, failed: false));
    if (t.failed) events.add(OffPeakEvent(t, failed: true));
  }
  return events;
}

/// An automation fired since the last tick (lastRunAt bumped).
class AutomationRunEvent {
  final AutomationItem item;
  final bool failed;

  const AutomationRunEvent(this.item, {required this.failed});
}

List<AutomationRunEvent> automationRunEvents({
  required Map<String, int> previousLastRunAt,
  required List<AutomationItem> items,
}) {
  final events = <AutomationRunEvent>[];
  for (final item in items) {
    final lastRunAt = item.lastRunAt;
    if (lastRunAt == null) continue;
    final was = previousLastRunAt[item.id];
    if (was != null && lastRunAt <= was) continue;
    if (was == null && lastRunAt < DateTime.now().millisecondsSinceEpoch -
        const Duration(minutes: 10).inMilliseconds) {
      // First sight of an old run: silent (avoid replaying history).
      continue;
    }
    final failed = item.lastResult == 'error' ||
        (item.lastResult?.toLowerCase().contains('fail') ?? false);
    events.add(AutomationRunEvent(item, failed: failed));
  }
  return events;
}
