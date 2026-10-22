import 'package:flutter/material.dart';

import '../protocol/automation.dart';
import '../protocol/conversation.dart';
import '../state/device_session.dart';
import '../state/device_store.dart';
import 'model_option_field.dart';
import 'theme.dart';
import 'ui_settings.dart';
import 'widgets/dropdown_field.dart';

/// One 定时任务模板 idea (official moreIdeas trio): dictionary key plus
/// its cron preset and display schedule.
class _Idea {
  final String key;
  final String schedule;
  final String cron;
  const _Idea(this.key, this.schedule, this.cron);
}

/// Server-side automations of one device (desktop zcode-cron-scheduler).
/// Standalone page with a device picker; the pane itself is embedded by
/// the scheduled page so both entries share the exact list UI.
class AutomationsPage extends StatefulWidget {
  final DeviceStore store;
  final DeviceSessionHub hub;
  final String? initialDeviceId;
  const AutomationsPage({
    super.key,
    required this.store,
    required this.hub,
    this.initialDeviceId,
  });

  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  late String? _deviceId;

  @override
  void initState() {
    super.initState();
    widget.store.load();
    _deviceId = widget.initialDeviceId;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final devices =
            widget.store.devices.where((d) => d.params != null).toList();
        if (_deviceId == null ||
            !devices.any((d) => d.id == _deviceId)) {
          _deviceId = devices.isEmpty ? null : devices.first.id;
        }
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(context, 'auto.title'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text(tr(context, 'auto.subtitle'),
                    style:
                        TextStyle(fontSize: 11, color: ZInk.faint(context))),
              ],
            ),
          ),
          body: devices.isEmpty
              ? Center(
                  child: Text(tr(context, 'sched.noDevices'),
                      style: TextStyle(color: ZInk.muted(context))))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: _devicePicker(devices),
                    ),
                    Expanded(
                      child: AutomationsPane(
                        key: ValueKey('auto-$_deviceId'),
                        session: _deviceId == null
                            ? null
                            : widget.hub.sessionOf(_deviceId!),
                        onRetry: () => widget.hub.syncWith(widget.store.devices),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _devicePicker(List<Device> devices) {
    return DropdownField<String>(
      value: _deviceId,
      decoration: InputDecoration(
        labelText: tr(context, 'sched.device'),
        suffixIcon: const Icon(Icons.desktop_windows_outlined, size: 18),
      ),
      items: [
        for (final d in devices)
          DropdownMenuItem(value: d.id, child: Text(d.label)),
      ],
      onChanged: (v) => setState(() => _deviceId = v ?? _deviceId),
    );
  }
}

/// Automations list of one device session: load / unavailable / list, plus
/// create/edit (bottom sheet), enable toggle and delete-with-confirm.
///
/// [compact] embeds without its own scroll view (the host page scrolls);
/// otherwise the list is a RefreshIndicator + ListView.
class AutomationsPane extends StatefulWidget {
  final AutomationHost? session;

  /// Retry hook when the device has no live session (re-sync connections).
  final void Function()? onRetry;
  final bool compact;

  const AutomationsPane({
    super.key,
    required this.session,
    this.onRetry,
    this.compact = false,
  });

  @override
  State<AutomationsPane> createState() => _AutomationsPaneState();
}

class _AutomationsPaneState extends State<AutomationsPane> {
  static const _templateIdeas = [
    _Idea('weeklyReview', '每周五 16:00', '0 16 * * 5'),
    _Idea('meetingPrep', '每周五 16:00', '0 16 * * 5'),
    _Idea('contentIdeas', '每周一 9:00', '0 9 * * 1'),
  ];

  List<AutomationItem> _items = const [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = widget.session;
    if (session == null) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await session.automation.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _runOp(Future<void> Function() op,
      {String? errorKey}) async {
    if (_busy) return;
    _busy = true;
    try {
      await op();
    } catch (e) {
      if (mounted) {
        _toast(errorKey != null
            ? tr(context, errorKey)
            : trP(context, 'auto.opFailed', ['$e']));
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _showSheet({AutomationItem? edit}) async {
    final session = widget.session;
    final input = await showModalBottomSheet<AutomationInput>(
      context: context,
      isScrollControlled: true,
      builder: (c) => AutomationSheet(
        initial: edit?.toInput(),
        loadOptions:
            session is DeviceSession ? session.prepareWorkspace : null,
      ),
    );
    if (input == null) return;
    if (session == null) return;
    await _runOp(() async {
      if (edit == null) {
        await session.automation.create(input);
        if (mounted) _toast(tr(context, 'auto.created'));
      } else {
        await session.automation.update(edit.id, input);
        if (mounted) _toast(tr(context, 'auto.saved'));
      }
      await _load();
    }, errorKey: edit == null ? 'auto.error.create' : 'auto.error.update');
  }

  Future<void> _toggle(AutomationItem item, bool enabled) async {
    final session = widget.session;
    if (session == null) return;
    await _runOp(() async {
      await session.automation.setEnabled(item.id, enabled);
      await _load();
    }, errorKey: 'auto.error.toggle');
  }

  /// 立即运行: official queued/duplicate/failed toast trio.
  Future<void> _runNow(AutomationItem item) async {
    final session = widget.session;
    if (session == null) return;
    await _runOp(() async {
      final result =
          await session.automation.runNow(item.id, session.automationScope);
      if (!mounted) return;
      _toast(tr(context, switch (result) {
        'duplicate' => 'auto.runNowDuplicate',
        _ => 'auto.runNowQueued',
      }));
    }, errorKey: 'auto.runNowFailed');
  }

  Future<void> _delete(AutomationItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(context, 'auto.delete.title')),
        content: Text(trP(context, 'auto.delete.body',
            [item.title.isEmpty ? item.id : item.title])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr(context, 'devices.add.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error,
                foregroundColor: Theme.of(c).colorScheme.onError),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr(context, 'devices.delete.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final session = widget.session;
    if (session == null) return;
    await _runOp(() async {
      await session.automation.remove(item.id);
      if (mounted) _toast(tr(context, 'auto.deleted'));
      await _load();
    }, errorKey: 'auto.error.delete');
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null ||
        session.status == DeviceStatus.error ||
        session.status == DeviceStatus.disconnected) {
      return _unavailable(context);
    }
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(tr(context, 'auto.loading'),
                style:
                    TextStyle(fontSize: 13, color: ZInk.faint(context))),
          ],
        ),
      );
    }
    if (_error != null) {
      return _errorView(context);
    }
    if (_items.isEmpty) {
      final empty = Padding(
        padding: EdgeInsets.symmetric(
            vertical: 24, horizontal: widget.compact ? 0 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(context, 'auto.empty'),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ZInk.solid(context))),
            const SizedBox(height: 4),
            Text(tr(context, 'auto.empty.desc'),
                style:
                    TextStyle(fontSize: 12.5, color: ZInk.faint(context))),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _showSheet(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr(context, 'auto.createManually')),
            ),
            TextButton.icon(
              onPressed: () => _pickTemplate(),
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text(tr(context, 'auto.templates')),
            ),
          ],
        ),
      );
      if (widget.compact) return empty;
      return Center(child: SingleChildScrollView(child: empty));
    }
    final cards = [
      for (final item in _items) ...[
        _itemCard(item),
        const SizedBox(height: 8),
      ],
      _addAction(context),
    ];
    if (widget.compact) return Column(children: cards);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        itemCount: cards.length,
        separatorBuilder: (context, index) => const SizedBox.shrink(),
        itemBuilder: (context, i) => cards[i],
      ),
    );
  }

  Widget _addAction(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _showSheet(),
          icon: const Icon(Icons.add, size: 18),
          label: Text(tr(context, 'auto.add')),
        ),
      );


Future<void> _pickTemplate() async {
  final picked = await showModalBottomSheet<_Idea>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(tr(sheetCtx, 'auto.templates'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          for (final idea in _templateIdeas)
            ListTile(
              dense: true,
              title: Text(tr(sheetCtx, 'auto.tpl.${idea.key}.title'),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(idea.schedule,
                      style:
                          TextStyle(fontSize: 11, color: ZColors.sky500)),
                  Text(tr(sheetCtx, 'auto.tpl.${idea.key}.desc'),
                      style: TextStyle(
                          fontSize: 11.5, color: ZInk.muted(sheetCtx))),
                ],
              ),
              trailing: Icon(Icons.arrow_forward_ios,
                  size: 14, color: ZInk.ghost(sheetCtx)),
              onTap: () => Navigator.pop(sheetCtx, idea),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !mounted) return;
  final prompt = tr(context, 'auto.tpl.${picked.key}.prompt');
  final title = tr(context, 'auto.tpl.${picked.key}.title');
  final session = widget.session;
  if (!mounted) return;
  final completed = await showModalBottomSheet<AutomationInput>(
    context: context,
    isScrollControlled: true,
    builder: (c) => AutomationSheet(
      template: (title: title, prompt: prompt, cronExpr: picked.cron),
      loadOptions:
          session is DeviceSession ? session.prepareWorkspace : null,
    ),
  );
  if (completed == null || session == null || !mounted) return;
  await _runOp(() async {
    await session.automation.create(completed);
    if (mounted) _toast(tr(context, 'auto.created'));
    await _load();
  }, errorKey: 'auto.error.create');
}

/// Mirrors the task-list fallback view: reason + retry + guidance to the
  /// local scheduled-send fallback.
  Widget _unavailable(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: ZInk.ghost(context)),
            const SizedBox(height: 16),
            Text(
              tr(context, 'auto.unavailable.title'),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ZInk.solid(context)),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'auto.unavailable.body'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ZInk.faint(context)),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: widget.onRetry ?? _load,
              child: Text(tr(context, 'tasks.retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              trP(context, 'auto.loadFailed', [_error!]),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ZInk.faint(context)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              child: Text(tr(context, 'tasks.retry')),
            ),
          ],
        ),
      ),
    );
  }

  /// 已运行 n 次 / 已运行 n/max 次 (official count copy).
  String _runCountLabel(BuildContext context, AutomationItem item) {
    final count = item.runCount ?? 0;
    final max = item.maxRuns;
    final limited = max != null && max > 0 && !item.recurring;
    return trP(
        context,
        limited ? 'auto.runCountLimited' : 'auto.runCount',
        limited ? ['$count', '$max'] : ['$count']);
  }

  Widget _itemCard(AutomationItem item) {
    final dotColor = item.enabled ? ZColors.success : ZColors.neutral400;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title.isEmpty ? item.id : item.title,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.enabled
                            ? tr(context, 'auto.enabled')
                            : tr(context, 'auto.disabled'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: item.enabled
                                ? ZColors.success
                                : ZInk.muted(context)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    describeTrigger(context, item),
                    style:
                        TextStyle(fontSize: 12, color: ZInk.muted(context)),
                  ),
                  if (item.prompt.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: ZInk.muted(context)),
                      ),
                    ),
                  if (item.lastRunAt != null || item.nextRunAtMs != null ||
                      item.runCount != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (item.lastRunAt != null)
                          trP(context, 'auto.lastRun',
                              [relativeTime(context, item.lastRunAt!)]),
                        // 下次运行 {when} — shown while the automation is on.
                        if (item.enabled && item.nextRunAtMs != null)
                          trP(context, 'auto.nextRun',
                              [relativeTime(context, item.nextRunAtMs!)]),
                        if (item.runCount != null)
                          _runCountLabel(context, item),
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 11, color: ZInk.ghost(context)),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: item.enabled,
              onChanged: (v) => _toggle(item, v),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'run-now':
                    _runNow(item);
                  case 'edit':
                    _showSheet(edit: item);
                  case 'delete':
                    _delete(item);
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(
                  value: 'run-now',
                  child: Row(
                    children: [
                      const Icon(Icons.play_arrow_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(tr(context, 'auto.runNow')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(tr(context, 'auto.edit')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline, size: 18),
                      const SizedBox(width: 8),
                      Text(tr(context, 'devices.menu.delete'),
                          style:
                              TextStyle(color: Theme.of(c).colorScheme.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Frequency presets mirroring the official schedule control
/// (每小时/每天/每工作日/每周/每月/自定义/一次性延迟).
enum FrequencyPreset { hourly, daily, weekdays, weekly, monthly, customInterval, once }

/// Create/edit form (bottom sheet, official mobile form shape). Field order
/// follows the official web form: title → prompt → model → frequency rule.
class AutomationSheet extends StatefulWidget {
  final AutomationInput? initial;

  /// Prefilled from a tapped 定时任务模板 tile.
  final ({String title, String prompt, String cronExpr})? template;

  /// prepareWorkspace loader (the full device session): drives the model /
  /// thought-level selectors — desktop parity, pick instead of type.
  final Future<WorkspacePrep> Function()? loadOptions;
  const AutomationSheet(
      {super.key, this.initial, this.template, this.loadOptions});

  @override
  State<AutomationSheet> createState() => AutomationSheetState();
}

class AutomationSheetState extends State<AutomationSheet> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _cron;
  late final TextEditingController _interval;
  late final TextEditingController _maxRuns;
  late final TextEditingController _delay;
  late final TextEditingController _targetTask;

  /// Selected model option (`provider/model` composite) split for the wire
  /// (automation carries model + provider separately); null = 默认.
  String? _modelValue;
  String? _thought;
  late String _intervalUnit;
  late bool _recurring;
  String? _mode;
  bool _advanced = false;

  FrequencyPreset _preset = FrequencyPreset.daily;
  TimeOfDay _timeOfDay = const TimeOfDay(hour: 9, minute: 0);
  final Set<int> _weekdays = {1};
  int _monthDay = 1;

  @override
  void initState() {
    super.initState();
    final init = widget.initial ??
        (widget.template == null
            ? null
            : AutomationInput(
                title: widget.template!.title,
                prompt: widget.template!.prompt,
                cronExpr: widget.template!.cronExpr));
    _title = TextEditingController(text: init?.title ?? '');
    _prompt = TextEditingController(text: init?.prompt ?? '');
    _cron = TextEditingController(text: init?.cronExpr ?? '0 9 * * *');
    _interval = TextEditingController(text: '${init?.interval ?? 30}');
    _maxRuns = TextEditingController(text: '${init?.maxRuns ?? 10}');
    _delay = TextEditingController(
        text: '${init?.relativeDelayMinutes ?? 60}');
    _intervalUnit = init?.intervalUnit ?? 'day';
    _recurring = init?.recurring ?? true;
    _derivePreset(init);
    _mode = init?.mode;
    _modelValue = (init?.provider ?? '').isNotEmpty && (init?.model ?? '').isNotEmpty
        ? '${init!.provider}/${init.model}'
        : init?.model;
    _thought = init?.thoughtLevel;
    _targetTask = TextEditingController(text: init?.targetTaskId ?? '');
    _advanced =
        (_modelValue ?? '').isNotEmpty || (_thought ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _cron.dispose();
    _interval.dispose();
    _maxRuns.dispose();
    _delay.dispose();
    _targetTask.dispose();
    super.dispose();
  }

  /// Maps an edited item's trigger onto the closest frequency preset so
  /// edits open with recognizable controls instead of a bare expression.
  void _derivePreset(AutomationInput? init) {
    if (init == null) return;
    if (init.trigger == AutomationInput.triggerOneShot) {
      _preset = FrequencyPreset.once;
      return;
    }
    if (init.trigger == AutomationInput.triggerInterval) {
      _preset = FrequencyPreset.customInterval;
      return;
    }
    final parts = (init.cronExpr ?? '').trim().split(RegExp(r'\s+'));
    if (parts.length != 5 ||
        !RegExp(r'^\d{1,2}$').hasMatch(parts[0]) ||
        !RegExp(r'^\d{1,2}$').hasMatch(parts[1])) {
      // Legacy/unparseable shapes land on daily without touching the value:
      // saving regenerates only when another control changes.
      _preset = FrequencyPreset.daily;
      return;
    }
    final dom = parts[2], month = parts[3], dow = parts[4];
    if (dom == '*' && month == '*' && dow == '*') {
      if (parts[0] == '0' && parts[1] == '*') {
        // '0 * * * *' — the hourly preset's own shape.
        _preset = FrequencyPreset.hourly;
        return;
      }
      final minute = int.parse(parts[0]);
      final hour = int.parse(parts[1]);
      _timeOfDay = TimeOfDay(hour: hour, minute: minute);
      _preset = FrequencyPreset.daily;
      return;
    }
    if (!(RegExp(r'^\d{1,2}$').hasMatch(parts[0]) &&
        RegExp(r'^\d{1,2}$').hasMatch(parts[1]))) {
      // Wildcard-minute shapes (*/15 …): expose as custom interval.
      _preset = FrequencyPreset.customInterval;
      return;
    }
    _timeOfDay = TimeOfDay(
        hour: int.parse(parts[1]), minute: int.parse(parts[0]));
    if (dom == '*' && month == '*' && dow == '1-5') {
      _preset = FrequencyPreset.weekdays;
      return;
    }
    if (dom == '*' && month == '*' && RegExp(r'^[0-6](,[0-6])*$').hasMatch(dow)) {
      _preset = FrequencyPreset.weekly;
      _weekdays
        ..clear()
        ..addAll([for (final t in dow.split(',')) int.parse(t) % 7]);
      return;
    }
    if (month == '*' &&
        dow == '*' &&
        RegExp(r'^\d{1,2}$').hasMatch(dom)) {
      _preset = FrequencyPreset.monthly;
      _monthDay = int.parse(dom);
      return;
    }
    _preset = FrequencyPreset.customInterval;
  }

  /// Cron minute/hour from the picked time.
  String get _timePart =>
      '${_timeOfDay.hour.toString().padLeft(2, '0')}:'
      '${_timeOfDay.minute.toString().padLeft(2, '0')}';

  List<int> _sortedWeekdays() => _weekdays.toList()..sort();

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _timeOfDay);
    if (t != null) setState(() => _timeOfDay = t);
  }

  /// Synthetic item feeding the humanized schedule preview.
  AutomationItem _previewItem() {
    final cron = _effectiveCron();
    return AutomationItem({
      'automationId': 'preview',
      'title': _title.text,
      'prompt': _prompt.text,
      if (cron != null)
        'cronExpr': cron
      else if (_preset == FrequencyPreset.customInterval) ...{
        'interval': int.tryParse(_interval.text.trim()) ?? 1,
        'intervalUnit': _intervalUnit,
        'recurring': _recurring,
        if (!_recurring) 'maxRuns': int.tryParse(_maxRuns.text.trim()) ?? 1,
      } else ...{
        'relativeDelayMinutes': int.tryParse(_delay.text.trim()) ?? 1,
        'recurring': false,
        'maxRuns': 1,
      },
    });
  }

  /// Opens the official custom-repeat dialog and applies its result to the
  /// interval controllers.
  Future<void> _openCustomRepeat() async {
    final result = await showDialog<CustomRepeatResult>(
      context: context,
      builder: (_) => CustomRepeatDialog(
        initial: CustomRepeatResult(
          interval: int.tryParse(_interval.text.trim()) ?? 30,
          unit: _intervalUnit,
          recurring: _recurring,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _interval.text = '${result.interval}';
      _intervalUnit = result.unit;
      _recurring = result.recurring;
      if (!result.recurring) {
        _maxRuns.text = '\${result.maxRuns ?? 1}';
      }
      _preset = FrequencyPreset.customInterval;
    });
  }

  void _submit() {
    // Split the composite option value back into the wire's provider+model.
    String? provider;
    String? model;
    final mv = _modelValue;
    if (mv != null && mv.isNotEmpty) {
      final idx = mv.lastIndexOf('/');
      if (idx > 0) {
        provider = mv.substring(0, idx);
        model = mv.substring(idx + 1);
      } else {
        model = mv;
      }
    }
    // Presets regenerate the expression; interval/one-shot keep their own
    // wire shapes.
    final presetCron = _effectiveCron();
    final input = AutomationInput(
      title: _title.text,
      prompt: _prompt.text,
      trigger: _preset == FrequencyPreset.once
          ? AutomationInput.triggerOneShot
          : (_preset == FrequencyPreset.customInterval
              ? AutomationInput.triggerInterval
              : AutomationInput.triggerCron),
      cronExpr: presetCron ?? _cron.text,
      interval: int.tryParse(_interval.text.trim()),
      intervalUnit: _intervalUnit,
      recurring: _recurring,
      maxRuns: int.tryParse(_maxRuns.text.trim()),
      relativeDelayMinutes: int.tryParse(_delay.text.trim()),
      model: model,
      provider: provider,
      mode: _mode,
      thoughtLevel:
          _thought == null || _thought!.isEmpty ? null : _thought,
      targetTaskId: _targetTask.text.trim().isEmpty
          ? null
          : _targetTask.text.trim(),
    );
    final error = input.validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, error))),
      );
      return;
    }
    Navigator.pop(context, input);
  }


  /// Wire expression produced by the active preset (null for interval /
  /// one-shot, which carry dedicated fields).
  String? _effectiveCron() {
    final m = _timeOfDay.minute, h = _timeOfDay.hour;
    switch (_preset) {
      case FrequencyPreset.hourly:
        return '0 * * * *';
      case FrequencyPreset.daily:
        return '$m $h * * *';
      case FrequencyPreset.weekdays:
        return '$m $h * * 1-5';
      case FrequencyPreset.weekly:
        return '$m $h * * ${_sortedWeekdays().join(',')}';
      case FrequencyPreset.monthly:
        return '$m $h $_monthDay * *';
      case FrequencyPreset.customInterval:
      case FrequencyPreset.once:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context,
                  widget.initial == null ? 'auto.create' : 'auto.edit'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              tr(context, 'auto.hint'),
              style: TextStyle(fontSize: 11, color: ZInk.muted(context)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                  labelText: tr(context, 'auto.name'),
                  hintText: tr(context, 'auto.name.hint')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prompt,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: tr(context, 'auto.prompt'),
                  hintText: tr(context, 'auto.prompt.hint')),
            ),
            const SizedBox(height: 10),
            ModelOptionField(
              loadOptions: widget.loadOptions,
              optionId: 'model',
              labelText: tr(context, 'auto.model'),
              noneLabel: tr(context, 'auto.model.default'),
              value: _modelValue,
              onChanged: (v) => setState(() => _modelValue = v),
            ),
            const SizedBox(height: 16),
            // Official frequency presets; interval shapes come from the
            // custom-repeat dialog under 自定义….
            Text(tr(context, 'auto.preset'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ZInk.muted(context))),
            const SizedBox(height: 8),
            DropdownField<FrequencyPreset>(
              value: _preset,
              decoration:
                  InputDecoration(labelText: tr(context, 'auto.preset')),
              items: [
                for (final preset in FrequencyPreset.values)
                  DropdownMenuItem(
                    value: preset,
                    child: Text(switch (preset) {
                      FrequencyPreset.hourly =>
                        tr(context, 'auto.freq.hourly'),
                      FrequencyPreset.daily => tr(context, 'auto.freq.daily'),
                      FrequencyPreset.weekdays =>
                        tr(context, 'auto.freq.weekdays'),
                      FrequencyPreset.weekly => tr(context, 'auto.freq.weekly'),
                      FrequencyPreset.monthly =>
                        tr(context, 'auto.freq.monthly'),
                      FrequencyPreset.customInterval =>
                        tr(context, 'auto.freq.customInterval'),
                      FrequencyPreset.once =>
                        tr(context, 'auto.trigger.oneShot'),
                    }),
                  ),
              ],
              onChanged: (v) async {
                if (v == null || v == _preset) return;
                if (v == FrequencyPreset.customInterval) {
                  await _openCustomRepeat();
                  return;
                }
                setState(() => _preset = v);
              },
            ),
            const SizedBox(height: 10),
            if (_preset != FrequencyPreset.once &&
                _preset != FrequencyPreset.hourly &&
                _preset != FrequencyPreset.customInterval)
              InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration:
                      InputDecoration(labelText: tr(context, 'auto.time')),
                  child: Text(_timePart),
                ),
              ),
            if (_preset == FrequencyPreset.weekly) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(tr(context, 'auto.weekday.${d % 7}')),
                        selected: _weekdays.contains(d % 7),
                        onSelected: (on) => setState(() {
                          on
                              ? _weekdays.add(d % 7)
                              : _weekdays.remove(d % 7);
                          if (_weekdays.isEmpty) _weekdays.add(1);
                        }),
                      ),
                  ],
                ),
              ),
            ],
            if (_preset == FrequencyPreset.monthly) ...[
              const SizedBox(height: 10),
              DropdownField<int>(
                value: _monthDay.clamp(1, 28),
                decoration:
                    InputDecoration(labelText: tr(context, 'auto.monthDay')),
                items: [
                  for (var d = 1; d <= 28; d++)
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) => setState(() => _monthDay = v ?? _monthDay),
              ),
            ],
            if (_preset == FrequencyPreset.customInterval) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  trP(context, 'auto.every', [
                    _interval.text.trim(),
                    tr(context, 'auto.intervalUnit.$_intervalUnit'),
                  ]),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(tr(context, 'auto.recurring'),
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(tr(context, 'auto.recurring.hint'),
                    style:
                        TextStyle(fontSize: 11, color: ZInk.faint(context))),
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
              ),
              if (!_recurring)
                TextField(
                  controller: _maxRuns,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: tr(context, 'auto.maxRuns'),
                      hintText: tr(context, 'auto.maxRuns.hint')),
                ),
            ],
            if (_preset == FrequencyPreset.once)
              TextField(
                controller: _delay,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr(context, 'auto.delayMinutes'),
                  helperText: tr(context, 'auto.delayHint'),
                ),
              ),
            const SizedBox(height: 8),
            // 运行时间预览（official schedule.preview line）.
            Builder(builder: (context) {
              final previewItem = _previewItem();
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  trP(context, 'auto.schedule.preview',
                      [describeTrigger(context, previewItem)]),
                  style: TextStyle(fontSize: 11, color: ZInk.ghost(context)),
                ),
              );
            }),
            const SizedBox(height: 6),
            _advancedSection(context),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(tr(context, 'devices.rename.save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedSection(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      dense: true,
      title: Text(tr(context, 'auto.advanced'),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ZInk.muted(context))),
      initiallyExpanded: _advanced,
      children: [
        DropdownField<String?>(
          value: _mode,
          decoration: InputDecoration(labelText: tr(context, 'auto.mode')),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(tr(context, 'auto.mode.default')),
            ),
            for (final m in const ['build', 'plan', 'yolo'])
              DropdownMenuItem(value: m, child: Text(tr(context, 'chat.mode.$m'))),
          ],
          onChanged: (v) => setState(() => _mode = v),
        ),
        const SizedBox(height: 10),
        ModelOptionField(
          loadOptions: widget.loadOptions,
          optionId: 'thought_level',
          labelText: tr(context, 'auto.thoughtLevel'),
          noneLabel: tr(context, 'auto.thoughtLevel.default'),
          value: _thought,
          onChanged: (v) => setState(() => _thought = v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _targetTask,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
              labelText: tr(context, 'auto.targetTask')),
        ),
      ],
    );
  }
}

/// Result of the custom-repeat dialog: interval wire shape with optional
/// finite-run estimation from a chosen end date.
class CustomRepeatResult {
  final int interval;
  final String unit;
  final bool recurring;

  /// Estimated cap when an end date was picked (the wire has no endDate,
  /// so the scheduler stops after this many runs).
  final int? maxRuns;
  const CustomRepeatResult({
    required this.interval,
    required this.unit,
    required this.recurring,
    this.maxRuns,
  });
}

/// Official 自定义重复 dialog: every N minutes/hours/days/weeks/months/years
/// ending never / on a chosen date.
class CustomRepeatDialog extends StatefulWidget {
  final CustomRepeatResult initial;
  const CustomRepeatDialog({super.key, required this.initial});

  @override
  State<CustomRepeatDialog> createState() => _CustomRepeatDialogState();
}

class _CustomRepeatDialogState extends State<CustomRepeatDialog> {
  late int _interval = widget.initial.interval;
  late String _unit = widget.initial.unit;
  late bool _neverEnds = widget.initial.recurring;
  DateTime? _endDate;

  static const _stepMs = {
    'minute': 60000,
    'hour': 3600000,
    'day': 86400000,
    'week': 7 * 86400000,
    'month': 30 * 86400000,
    'year': 365 * 86400000,
  };

  Widget _endsChoice(
    BuildContext context, {
    required bool selected,
    required bool value,
    required String label,
    required VoidCallback onPick,
  }) =>
      ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        leading: Icon(
          selected == value ? Icons.radio_button_checked : Icons.radio_button_off,
          size: 18,
          color: selected == value ? ZColors.sky500 : ZInk.ghost(context),
        ),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        onTap: onPick,
      );

  int? get _estimatedRuns {
    if (_neverEnds || _endDate == null) return null;
    final stepMs = (_interval.clamp(1, 200)) * (_stepMs[_unit] ?? 0);
    if (stepMs <= 0) return null;
    final diff = _endDate!.millisecondsSinceEpoch -
        DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return null;
    return (diff / stepMs).ceil().clamp(1, 999);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'auto.custom.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: '$_interval',
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: tr(context, 'auto.custom.every')),
                    onChanged: (v) =>
                        _interval = int.tryParse(v.trim()) ?? _interval,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: DropdownField<String>(
                    value: _unit,
                    decoration: InputDecoration(
                        labelText: tr(context, 'auto.intervalUnit.label')),
                    items: [
                      for (final u in AutomationInput.intervalUnits)
                        DropdownMenuItem(
                            value: u,
                            child: Text(tr(context, 'auto.intervalUnit.$u'))),
                    ],
                    onChanged: (v) => setState(() => _unit = v ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'auto.custom.ends'),
                style: TextStyle(fontSize: 12, color: ZInk.muted(context))),
            _endsChoice(
              context,
              selected: _neverEnds,
              value: true,
              label: tr(context, 'auto.custom.never'),
              onPick: () => setState(() => _neverEnds = true),
            ),
            _endsChoice(
              context,
              selected: _neverEnds,
              value: false,
              label: tr(context, 'auto.custom.until'),
              onPick: () => setState(() => _neverEnds = false),
            ),
            if (!_neverEnds)
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate:
                        _endDate ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (d != null) setState(() => _endDate = d);
                },
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration:
                      InputDecoration(labelText: tr(context, 'auto.custom.dateLabel')),
                  child: Text(_endDate == null
                      ? tr(context, 'auto.custom.dateLabel')
                      : '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'),
                ),
              ),
            if (_estimatedRuns != null) ...[
              const SizedBox(height: 6),
              Text(trP(context, 'auto.custom.estRuns', ['$_estimatedRuns']),
                  style: TextStyle(fontSize: 11, color: ZInk.faint(context))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'devices.add.cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            CustomRepeatResult(
              interval: _interval,
              unit: _unit,
              recurring: _neverEnds,
              maxRuns: _estimatedRuns,
            ),
          ),
          child: Text(tr(context, 'devices.rename.save')),
        ),
      ],
    );
  }
}

/// Humanized trigger summary (official terms): the desktop never shows a
/// raw cron expression — common shapes map to 每天/每工作日/每周/每月 + time,
/// anything else falls back to the expression itself.
String describeTrigger(BuildContext context, AutomationItem item) {
  switch (item.trigger) {
    case AutomationInput.triggerCron:
      return _describeCron(context, item.cronExpr);
    case AutomationInput.triggerInterval:
      final unit =
          tr(context, 'auto.intervalUnit.${item.intervalUnit ?? 'day'}');
      var text =
          trP(context, 'auto.every', ['${item.interval ?? 0}', unit]);
      if (!item.recurring) {
        text += ' · ${trP(context, 'auto.maxRunsN', ['${item.maxRuns ?? '?'}'])}';
      }
      return text;
    default:
      return trP(context, 'auto.once',
          [formatDelay(context, item.relativeDelayMinutes ?? 0)]);
  }
}

/// "30 9 * * *" → 每天 09:30 · "0 9 * * 1-5" → 每工作日 09:00 ·
/// "0 9 * * 3" → 每周三 09:00 · "0 9 5 * *" → 每月 5 号 09:00.
/// 5-field cron: minute hour day-of-month month day-of-week.
String _describeCron(BuildContext context, String expr) {
  final parts = expr.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return trP(context, 'auto.cronAt', [expr]);
  final minute = parts[0], hour = parts[1], dom = parts[2];
  final month = parts[3], dow = parts[4];
  if (!RegExp(r'^\d{1,2}$').hasMatch(minute) ||
      !RegExp(r'^\d{1,2}$').hasMatch(hour)) {
    return trP(context, 'auto.cronAt', [expr]);
  }
  final time = '${hour.padLeft(2, '0')}:${minute.padLeft(2, '0')}';
  final bothStar = dom == '*' && month == '*' && dow == '*';
  if (bothStar) return trP(context, 'auto.cron.daily', [time]);
  if (dom == '*' && month == '*' && dow == '1-5') {
    return trP(context, 'auto.cron.weekdays', [time]);
  }
  String? weekday(String token) {
    if (!RegExp(r'^\d$').hasMatch(token)) return null;
    final d = int.parse(token) % 7;
    return tr(context, 'auto.weekday.$d');
  }
  if (dom == '*' && month == '*') {
    final name = weekday(dow);
    if (name != null) return trP(context, 'auto.cron.weekly', [time, name]);
    // weekday lists like "1,3,5" / "0,6"
    final names = <String>[];
    for (final t in dow.split(RegExp(r'[,]'))) {
      final n = weekday(t);
      if (n == null) {
        names.clear();
        break;
      }
      names.add(n);
    }
    if (names.isNotEmpty) {
      return trP(context, 'auto.cron.weekly',
          [time, names.join(tr(context, 'auto.weekday.sep'))]);
    }
  }
  if (month == '*' && dow == '*' && RegExp(r'^\d{1,2}$').hasMatch(dom)) {
    return trP(context, 'auto.cron.monthly', [time, dom]);
  }
  return trP(context, 'auto.cronAt', [expr]);
}

/// 90 → 90 分钟; 1440 → 24 小时 → also days for big values.
String formatDelay(BuildContext context, int minutes) {
  if (minutes < 60) return trP(context, 'auto.minutes', ['$minutes']);
  if (minutes < 60 * 24) {
    return trP(
        context, 'auto.hours', [(minutes / 60).toStringAsFixed(0)]);
  }
  return trP(
      context, 'auto.days', [(minutes / 60 / 24).toStringAsFixed(0)]);
}
