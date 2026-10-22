import 'channel_client.dart';
import 'method_probe.dart';

/// Server-side automations (定时任务, the `zcode-cron-scheduler` subsystem
/// on the desktop). CRUD mirrors the official web remote's automation port.
///
/// Method-name status (2026-08, confirmed against a live desktop where noted):
/// - `listAllAutomations` []  → CONFIRMED via the zemote channel explorer
///   probing (zcode-agent channel returns a list of automation objects).
/// - `createAutomation` / `updateAutomation` / `deleteAutomation` → best
///   effort per the web client's naming convention; NOT yet live-confirmed.
///   Each operation tries candidates in order (see [MethodProbe]) and
///   remembers the first method the desktop accepts; if every candidate is
///   rejected the FIRST error is rethrown so validation/permission failures
///   surface verbatim.
///
/// Wire schema of one automation item (zod-style, for protocol upgrades):
/// ```text
/// automationItem = {
///   automationId: string,            // stable id (also accepted: id)
///   title: string,
///   prompt: string,                  // instruction sent on each trigger
///   cronExpr?: string,               // 5-field cron, cron trigger
///   interval?: number(1..200),       // with intervalUnit, interval trigger
///   intervalUnit?: 'minute'|'hour'|'day'|'week'|'month'|'year',
///   recurring?: boolean,             // true = repeat forever
///   maxRuns?: number,                // finite cap when recurring=false
///   relativeDelayMinutes?: number,   // one-shot delay, max 1 year
///   model?: string, provider?: string, mode?: string, thoughtLevel?: string,
///   targetTaskId?: string,           // bind to an existing task/session
///   enabled?: boolean,               // list results carry 启用/停用
///   // run bookkeeping (present once the scheduler has fired):
///   lastRunAt?: number, lastResult?: 'success'|'error'|string,
/// }
/// ```
/// Trigger kinds are mutually exclusive: cronExpr (cron) / interval+intervalUnit
/// (repeat, optionally capped by maxRuns when recurring=false) /
/// relativeDelayMinutes (one-shot, mutually exclusive with an existing
/// automationId on create).
class AutomationPort {
  /// Binds one RPC: the channel is fixed by the port owner, method/args vary.
  final Future<dynamic> Function(String method, List<Object?> args) call;

  AutomationPort(this.call) : _probe = MethodProbe(call);

  static const _listMethods = ['listAllAutomations', 'listAutomations'];
  static const _createMethods = [
    'createAutomation',
    'upsertAutomation',
    'automationCreate',
  ];
  static const _updateMethods = [
    'updateAutomation',
    'upsertAutomation',
    'automationUpdate',
  ];
  static const _deleteMethods = [
    'deleteAutomation',
    'automationDelete',
    'removeAutomation',
  ];

  /// Run-now (立即运行). The desktop's own port method is
  /// `runAutomationNow({workspacePath, workspaceIdentity?, automationId})`;
  /// the others keep MethodProbe-style fallbacks for older builds.
  static const _runNowMethods = [
    'runAutomationNow',
    'triggerAutomation',
    'automationRunNow',
    'runNow',
  ];

  /// `updateAutomation` arg shapes: 0 = `[{automationId, ...fields}]`,
  /// 1 = `[automationId, fields]`.
  static const _updateShapes = 2;

  final MethodProbe _probe;
  int _updateShape = 0;

  // ------------------------------------------------------------------ list

  /// Lists every automation of the connected desktop.
  Future<List<AutomationItem>> list() async {
    final res = await _probe.run('list', _listMethods);
    dynamic items = res;
    if (res is Map) {
      // Some ports wrap the list: {automations: [...]} / {items: [...]}.
      items = res['automations'] ?? res['items'] ?? res['list'];
    }
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map) AutomationItem(item.cast<String, dynamic>()),
    ];
  }

  // ---------------------------------------------------------------- create

  Future<AutomationItem> create(AutomationInput input) async {
    final res = await _probe.run('create', _createMethods,
        argsOf: (_) => [input.toWire()]);
    if (res is Map) return AutomationItem(res.cast<String, dynamic>());
    // Void-ish ack: echo the input back so the UI can refresh from list().
    return AutomationItem(input.toWire());
  }

  // ---------------------------------------------------------------- update

  /// Full update. Shape probing mirrors the create probing but also tries
  /// the positional `(id, fields)` form for update-family methods. The
  /// resolved method+shape go first on subsequent calls.
  Future<void> update(String id, AutomationInput input) async {
    Object? firstError;
    for (var shape = _updateShape; shape < _updateShapes; shape++) {
      final args = switch (shape) {
        0 => <Object?>[{'automationId': id, ...input.toWire()}],
        _ => <Object?>[id, input.toWire()],
      };
      try {
        await _probe.run('update:$shape', _updateMethods, argsOf: (_) => args);
        _updateShape = shape;
        return;
      } on ChannelRpcError catch (e) {
        if (!MethodProbe.missingMethod(e.message)) rethrow;
        firstError ??= e;
      }
    }
    throw firstError ?? StateError('update: no candidate methods left');
  }

  /// Enable/disable (启停开关). Implemented as a flag-only update; no
  /// separate pauseAutomation/resumeAutomation method is confirmed, and if
  /// the desktop rejects flag-only updates the caller surfaces the error.
  Future<void> setEnabled(String id, bool enabled) async {
    await update(id, AutomationInput(enabledOnly: enabled, existingId: id));
  }

  // ---------------------------------------------------------------- delete

  Future<void> remove(String id) async {
    await _probe.run('delete', _deleteMethods, argsOf: (method) {
      // deleteAutomation([automationId]) vs automationDelete([id])
      return [
        if (method.startsWith('automation')) id else {'automationId': id},
      ];
    });
  }

  // --------------------------------------------------------------- run now

  /// Triggers one immediate run (立即运行). [scope] carries
  /// `{workspacePath, workspaceIdentity?}` of the active workspace — the
  /// desktop requires it server-side. Returns 'queued' on acceptance or
  /// 'duplicate' when a run is already in flight; any rejection throws.
  Future<String> runNow(String id, Map<String, dynamic> scope) async {
    final res = await _probe.run('runNow', _runNowMethods,
        argsOf: (_) => [
              {
                ...scope,
                'automationId': id,
              },
            ]);
    final status = res is Map ? '${res['status'] ?? ''}' : '';
    return status == 'duplicate' ? 'duplicate' : 'queued';
  }
}

/// Form-side input for create/update. Exactly one trigger kind is set;
/// [toWire] emits only the fields belonging to that kind.
class AutomationInput {
  final String title;
  final String prompt;

  /// AutomationInput.triggerCron / triggerInterval / triggerOneShot.
  final String trigger;
  final String? cronExpr;
  final int? interval;
  final String? intervalUnit;
  final bool? recurring;
  final int? maxRuns;
  final int? relativeDelayMinutes;

  final String? model;
  final String? provider;
  final String? mode;
  final String? thoughtLevel;
  final String? targetTaskId;

  /// Flag-only update (启停开关): [toWire] emits `{enabled}` alone.
  final bool? enabledOnly;

  /// Set on update so flag-only updates can round-trip the id.
  final String? existingId;

  const AutomationInput({
    this.title = '',
    this.prompt = '',
    this.trigger = triggerCron,
    this.cronExpr,
    this.interval,
    this.intervalUnit,
    this.recurring,
    this.maxRuns,
    this.relativeDelayMinutes,
    this.model,
    this.provider,
    this.mode,
    this.thoughtLevel,
    this.targetTaskId,
    this.enabledOnly,
    this.existingId,
  });

  static const triggerCron = 'cron';
  static const triggerInterval = 'interval';
  static const triggerOneShot = 'oneShot';
  static const intervalUnits = [
    'minute',
    'hour',
    'day',
    'week',
    'month',
    'year',
  ];

  bool get isFlagOnly => enabledOnly != null;

  /// Validation used by the form before submit; returns an i18n key or null.
  String? validate() {
    if (isFlagOnly) return null;
    if (title.trim().isEmpty) return 'auto.err.title';
    if (prompt.trim().isEmpty) return 'auto.err.prompt';
    switch (trigger) {
      case triggerCron:
        if ((cronExpr ?? '').trim().isEmpty) return 'auto.err.cron';
      case triggerInterval:
        if (interval == null || interval! < 1) return 'auto.err.interval';
      case triggerOneShot:
        final d = relativeDelayMinutes ?? 0;
        if (d < 1 || d > 60 * 24 * 365) return 'auto.err.delay';
    }
    return null;
  }

  Map<String, dynamic> toWire() {
    if (isFlagOnly) {
      return {
        if (existingId != null) 'automationId': existingId,
        'enabled': enabledOnly,
      };
    }
    return {
      'title': title.trim(),
      'prompt': prompt.trim(),
      ..._triggerWire(),
    };
  }

  Map<String, dynamic> _triggerWire() {
    final optional = {
      if (model != null && model!.isNotEmpty) 'model': model,
      if (provider != null && provider!.isNotEmpty) 'provider': provider,
      if (mode != null && mode!.isNotEmpty) 'mode': mode,
      if (thoughtLevel != null && thoughtLevel!.isNotEmpty)
        'thoughtLevel': thoughtLevel,
      if (targetTaskId != null && targetTaskId!.isNotEmpty)
        'targetTaskId': targetTaskId,
    };
    return switch (trigger) {
      triggerCron => {'cronExpr': cronExpr!.trim(), ...optional},
      triggerInterval => {
          'interval': interval,
          if (intervalUnit != null) 'intervalUnit': intervalUnit,
          'recurring': recurring ?? true,
          if (recurring == false && maxRuns != null) 'maxRuns': maxRuns,
          ...optional,
        },
      _ => {
          'relativeDelayMinutes': relativeDelayMinutes,
          // One-shot: non-recurring with a single run.
          'recurring': false,
          'maxRuns': 1,
          ...optional,
        },
    };
  }
}

/// Read-side view of one automation. Field names tolerate both
/// `automationId` and `id` shapes seen across protocol versions.
class AutomationItem {
  final Map<String, dynamic> raw;
  AutomationItem(this.raw);

  String get id => '${raw['automationId'] ?? raw['id'] ?? raw['taskId'] ?? ''}';

  String get title => '${raw['title'] ?? raw['name'] ?? ''}';
  String get prompt => '${raw['prompt'] ?? raw['instruction'] ?? ''}';
  String get cronExpr => '${raw['cronExpr'] ?? raw['cron'] ?? ''}';
  bool get enabled => raw['enabled'] != false && raw['paused'] != true;

  int? get interval => (raw['interval'] as num?)?.toInt();
  String? get intervalUnit => raw['intervalUnit'] as String?;
  bool get recurring => raw['recurring'] != false;
  int? get maxRuns => (raw['maxRuns'] as num?)?.toInt();
  int? get relativeDelayMinutes =>
      (raw['relativeDelayMinutes'] as num?)?.toInt();

  String? get model => raw['model'] as String?;
  String? get provider => raw['provider'] as String?;
  String? get mode => raw['mode'] as String?;
  String? get thoughtLevel => raw['thoughtLevel'] as String?;
  String? get targetTaskId => raw['targetTaskId'] as String?;

  /// Trigger kind derived from which fields are present.
  String get trigger {
    if (cronExpr.isNotEmpty) return AutomationInput.triggerCron;
    if (relativeDelayMinutes != null) {
      return AutomationInput.triggerOneShot;
    }
    if (interval != null) return AutomationInput.triggerInterval;
    return AutomationInput.triggerCron;
  }

  int? get lastRunAt => (raw['lastRunAt'] as num?)?.toInt();
  String? get lastResult => raw['lastResult'] as String?;

  /// Next scheduled fire, epoch ms (下次运行). Tolerates s/ms scales.
  int? get nextRunAtMs {
    final v = (raw['nextRunAt'] as num?)?.toInt() ??
        (raw['nextRunAtMs'] as num?)?.toInt();
    if (v == null) return null;
    return v < 100000000000 ? v * 1000 : v;
  }

  /// Completed-run counter shown as 已运行 n[/max] 次.
  int? get runCount =>
      (raw['runCount'] as num?)?.toInt() ??
      (raw['executedCount'] as num?)?.toInt();

  /// Prefills an edit form from this item.
  AutomationInput toInput() => AutomationInput(
        title: title,
        prompt: prompt,
        trigger: trigger,
        cronExpr: cronExpr.isEmpty ? null : cronExpr,
        interval: interval,
        intervalUnit: intervalUnit,
        recurring: recurring,
        maxRuns: maxRuns,
        relativeDelayMinutes: relativeDelayMinutes,
        model: model,
        provider: provider,
        mode: mode,
        thoughtLevel: thoughtLevel,
        targetTaskId: targetTaskId,
      );
}
