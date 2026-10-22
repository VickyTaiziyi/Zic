import 'package:flutter/material.dart';

import '../state/device_session.dart';
import '../state/device_store.dart';
import '../state/scheduled_store.dart';
import 'automations_page.dart';
import 'theme.dart';
import 'ui_settings.dart';
import 'widgets/dropdown_field.dart';

/// Combined scheduling hub: server-side device automations on top, local
/// scheduled messages below (the two coexist — local send works offline,
/// automations run on the desktop without the app).
class ScheduledPage extends StatefulWidget {
  final DeviceStore devices;
  final DeviceSessionHub hub;
  final ScheduledStore store;
  const ScheduledPage({
    super.key,
    required this.devices,
    required this.hub,
    required this.store,
  });

  @override
  State<ScheduledPage> createState() => _ScheduledPageState();
}

class _ScheduledPageState extends State<ScheduledPage> {
  String? _autoDeviceId;

  @override
  void initState() {
    super.initState();
    widget.store.load();
    widget.devices.load();
  }

  Future<void> _showAddSheet() async {
    final devices = widget.devices.devices
        .where((d) => d.params != null)
        .toList();
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'sched.noDevices'))),
      );
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _AddSheet(devices: devices, store: widget.store),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'sched.created'))),
      );
    }
  }

  String _fmtDateTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'sched.title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'sched.add')),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([widget.store, widget.devices, widget.hub]),
        builder: (context, _) {
          final items = widget.store.items;
          final devices =
              widget.devices.devices.where((d) => d.params != null).toList();
          if (_autoDeviceId == null ||
              !devices.any((d) => d.id == _autoDeviceId)) {
            _autoDeviceId = devices.isEmpty ? null : devices.first.id;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _sectionHeader(context, tr(context, 'sched.section.server')),
              const SizedBox(height: 8),
              _serverSection(context, devices),
              const SizedBox(height: 24),
              _sectionHeader(
                context,
                tr(context, 'sched.section.local'),
                trailing: Text(
                  tr(context, 'sched.hint'),
                  style:
                      TextStyle(fontSize: 11, color: ZInk.ghost(context)),
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Text(tr(context, 'sched.empty'),
                    style: TextStyle(color: ZInk.muted(context)))
              else
                for (final m in items) ...[
                  _itemCard(m),
                  const SizedBox(height: 8),
                ],
            ],
          );
        },
      ),
    );
  }

  /// Listenable merge above covers store/devices/hub; locale rebuilds
  /// arrive through the MaterialApp ancestor.

  Widget _sectionHeader(BuildContext context, String text,
      {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ZInk.muted(context)),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  /// Device automations: device picker + the shared pane. The pane handles
  /// its own unavailable/error/empty states (with local-send guidance).
  Widget _serverSection(BuildContext context, List<Device> devices) {
    if (devices.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr(context, 'sched.noDevices'),
              style: TextStyle(fontSize: 13, color: ZInk.muted(context))),
        ),
      );
    }
    final session = widget.hub.sessionOf(_autoDeviceId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownField<String>(
          key: ValueKey('auto-device-$_autoDeviceId'),
          value: _autoDeviceId,
          decoration: InputDecoration(
            labelText: tr(context, 'sched.device'),
            suffixIcon:
                const Icon(Icons.desktop_windows_outlined, size: 18),
          ),
          items: [
            for (final d in devices)
              DropdownMenuItem(value: d.id, child: Text(d.label)),
          ],
          onChanged: (v) => setState(() => _autoDeviceId = v ?? _autoDeviceId),
        ),
        const SizedBox(height: 8),
        AutomationsPane(
          key: ValueKey('auto-pane-$_autoDeviceId'),
          session: session,
          compact: true,
          onRetry: () => widget.hub.syncWith(widget.devices.devices),
        ),
      ],
    );
  }

  Widget _itemCard(ScheduledMessage m) {
    final (label, color) = m.sent
        ? (tr(context, 'sched.sent'), ZColors.success)
        : m.attempts >= MessageScheduler.maxAttempts
            ? (tr(context, 'sched.failed'), ZColors.danger)
            : (tr(context, 'sched.pending'), ZColors.sky500);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(m.deviceLabel,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: color)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(m.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: ZInk.muted(context))),
                  const SizedBox(height: 4),
                  Text(
                    m.sent
                        ? _fmtDateTime(m.fireAt)
                        : '${_fmtDateTime(m.fireAt)} · ${relativeTime(context, m.fireAt)}',
                    style:
                        TextStyle(fontSize: 11, color: ZInk.ghost(context)),
                  ),
                  if (m.lastError != null && !m.sent)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        m.lastError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 11, color: ZColors.danger),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: ZInk.faint(context)),
              onPressed: () => widget.store.remove(m.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  final List<Device> devices;
  final ScheduledStore store;
  const _AddSheet({required this.devices, required this.store});

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  late String _deviceId;
  final _textController = TextEditingController();
  DateTime _fireAt =
      DateTime.now().add(const Duration(minutes: 10));

  @override
  void initState() {
    super.initState();
    _deviceId = widget.devices.first.id;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _fireAt.isAfter(DateTime.now()) ? _fireAt : DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(minutes: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fireAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _fireAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final device =
        widget.devices.where((d) => d.id == _deviceId).first;
    await widget.store.add(
      deviceId: device.id,
      deviceLabel: device.label,
      text: text,
      fireAt: _fireAt.millisecondsSinceEpoch,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'sched.add'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(tr(context, 'sched.hint'),
              style: TextStyle(fontSize: 11, color: ZInk.muted(context))),
          const SizedBox(height: 16),
          DropdownField<String>(
            value: _deviceId,
            decoration:
                InputDecoration(labelText: tr(context, 'sched.device')),
            items: [
              for (final d in widget.devices)
                DropdownMenuItem(value: d.id, child: Text(d.label)),
            ],
            onChanged: (v) => setState(() => _deviceId = v ?? _deviceId),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textController,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: tr(context, 'sched.message')),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                  labelText: tr(context, 'sched.time'),
                  suffixIcon: const Icon(Icons.event_outlined, size: 18)),
              child: Text(
                '${_fireAt.year}-${_fireAt.month.toString().padLeft(2, '0')}-'
                '${_fireAt.day.toString().padLeft(2, '0')} '
                '${_fireAt.hour.toString().padLeft(2, '0')}:'
                '${_fireAt.minute.toString().padLeft(2, '0')}',
              ),
            ),
          ),
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
    );
  }
}
