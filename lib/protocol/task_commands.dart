import 'method_probe.dart';

/// Task-level metadata commands (置顶 / 重命名 / 归档 / 标记未读 / 删除) for
/// the task list and the chat page's "更多" menu.
///
/// Method names **confirmed from the web client source** (2026-08-30,
/// `docs/parity/web-capabilities.md` §4): the desktop's `zcode-task` channel
/// exposes `renameTask`, `setTaskPinned`, `archiveTask`/`unarchiveTask`,
/// `setTaskUnread`, `deleteTask`, `listArchivedTasks` with the arg shape
/// `{taskId, workspacePath, workspaceIdentity?, title|pinned|unread}`.
/// Note the archive pair takes NO boolean field — two distinct methods.
/// Older fallbacks stay after the confirmed name so a divergent desktop
/// build still works through [MethodProbe]; the first rejection of the
/// confirmed name advances to them.
///
/// Every operation runs through [MethodProbe]: only "no such method" style
/// rejections advance to the next candidate, and the first accepted method
/// is remembered. If the desktop rejects every candidate the first error is
/// rethrown so the UI can surface the real reason instead of silently
/// no-oping.
class TaskCommandsPort {
  /// Binds one RPC: the channel is fixed by the port owner, method/args vary.
  final Future<dynamic> Function(String method, List<Object?> args) call;

  /// Workspace scope (workspacePath/identity) merged into every payload.
  final Map<String, dynamic> Function() scopeOf;

  TaskCommandsPort(this.call, {Map<String, dynamic> Function()? scope})
    : scopeOf = scope ?? (() => const {});

  late final MethodProbe _probe = MethodProbe(call);

  static const _renameMethods = [
    'renameTask',
    'updateTaskTitle',
    'setSessionTitle',
  ];
  static const _pinMethods = ['setTaskPinned', 'pinTask'];
  static const _unreadMethods = ['setTaskUnread', 'markTaskUnread'];

  Map<String, dynamic> _payload(String taskId) => {
    ...scopeOf(),
    'taskId': taskId,
  };

  Future<dynamic> _run(
    String op,
    List<String> methods,
    String taskId,
    Map<String, dynamic> fields,
  ) => _probe.run(
    op,
    methods,
    argsOf: (method) => <Object?>[
      {..._payload(taskId), ...fields},
    ],
  );

  /// Renames a task (chat page "更多 → 重命名", task list action sheet).
  Future<dynamic> rename(String taskId, String title) =>
      _run('rename', _renameMethods, taskId, {'title': title});

  /// Pins / unpins a task (置顶).
  Future<dynamic> setPinned(String taskId, bool pinned) =>
      _run('pin', _pinMethods, taskId, {'pinned': pinned});

  /// Archives / restores a task (归档). `archiveTask` and `unarchiveTask`
  /// are two distinct methods without a boolean field — sending
  /// `{archived: true}` to `archiveTask` is a shape error.
  Future<dynamic> setArchived(String taskId, bool archived) => _probe.run(
    // Distinct probe op keys: archiveTask/unarchiveTask are two methods, so
    // each direction caches its resolved method separately.
    archived ? 'archive' : 'unarchive',
    [archived ? 'archiveTask' : 'unarchiveTask'],
    argsOf: (method) => <Object?>[_payload(taskId)],
  );

  /// Marks a task unread (标记未读).
  Future<dynamic> setUnread(String taskId, bool unread) =>
      _run('unread', _unreadMethods, taskId, {'unread': unread});

  /// Deletes a task. Web copy: the task is removed from the workspace and
  /// existing records cannot be recovered — callers must confirm first.
  Future<dynamic> delete(String taskId) =>
      _run('delete', const ['deleteTask'], taskId, const {});

  /// Archived tasks of this workspace (the archive view's data source).
  Future<dynamic> listArchived() => call('listArchivedTasks', [scopeOf()]);
}
