import 'package:flutter/material.dart';

import '../protocol/channel_client.dart';
import '../protocol/provider_settings.dart';
import '../state/device_session.dart';
import 'theme.dart';
import 'ui_settings.dart';
import 'widgets/dropdown_field.dart';

/// Model provider management of one device (`provider-settings` getView /
/// personal overlay), restyled with the Zic tokens.
class ModelProvidersPage extends StatefulWidget {
  final DeviceSession session;
  const ModelProvidersPage({super.key, required this.session});

  @override
  State<ModelProvidersPage> createState() => _ModelProvidersPageState();
}

class _ModelProvidersPageState extends State<ModelProvidersPage> {
  List<Map<String, dynamic>> _providers = const [];
  bool _loading = true;
  String? _error;

  /// `provider-settings.onDidChange` pushes a new view. Reload when it does.
  void Function()? _cancelRegistryListener;

  @override
  void initState() {
    super.initState();
    _load();
    _listenRegistry();
  }

  void _listenRegistry() {
    final bridge = widget.session.bridge;
    if (bridge == null) return;
    _cancelRegistryListener = bridge.channels.addEventListener(
      Channels.providerSettings,
      'onDidChange',
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _cancelRegistryListener?.call();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _fetchView();
      if (!mounted) return;
      setState(() {
        _providers = parseProviderSettingsView(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[providers] load failed: $e');
      setState(() {
        _error = _failureText(e, 'providers.loadFailed');
        _loading = false;
      });
    }
  }

  /// `getView` on the channel the mobile bridge actually registers.
  /// A channel that is still coming up fails in about a second; retry once.
  Future<dynamic> _fetchView() async {
    try {
      return await widget.session
          .callChannel(Channels.providerSettings, 'getView');
    } catch (e) {
      if (!channelNotReady(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return widget.session.callChannel(Channels.providerSettings, 'getView');
    }
  }

  String _failureText(Object error, String detailKey) {
    if (channelNotReady(error)) return tr(context, 'providers.loadFailed.plain');
    return trP(context, detailKey, [channelErrorMessage(error)]);
  }

  Future<void> _toggle(Map<String, dynamic> provider, bool enabled) async {
    try {
      await widget.session.callChannel(
        Channels.providerSettings,
        'savePersonalProviderOverlay',
        [
          '${provider['id']}',
          personalProviderOverlay(provider),
          {'enabled': enabled},
        ],
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(_failureText(e, 'providers.toggleFailed'));
    }
  }

  Future<void> _delete(Map<String, dynamic> provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'providers.deleteTitle')),
        content: Text(trP(context, 'providers.deleteBody',
            ['${provider['name']}'])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, 'devices.add.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'devices.delete.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.session.callChannel(
        Channels.providerSettings,
        'deletePersonalProvider',
        ['${provider['id']}'],
      );
    } catch (e) {
      if (!mounted) return;
      _toast(_failureText(e, 'providers.deleteFailed'));
      return;
    }
    await _load();
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showAddSheet() async {
    final added = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddProviderSheet(),
    );
    if (added == null) return;
    final modelIds = [
      for (final id in (added['modelIds'] as List? ?? const [])) '$id',
    ].where((id) => id.isNotEmpty).toList();
    final draft = Map<String, dynamic>.from(added)..remove('modelIds');
    try {
      final created = await widget.session.callChannel(
        Channels.providerSettings,
        'createPersonalProvider',
        [draft],
      );
      final providerId =
          created is Map ? '${created['providerId'] ?? ''}' : '';
      Object? modelError;
      if (providerId.isNotEmpty) {
        for (final modelId in modelIds) {
          try {
            await widget.session.callChannel(
              Channels.providerSettings,
              'addPersonalModel',
              [providerId, modelId, <String, dynamic>{}, true],
            );
          } catch (e) {
            modelError ??= e;
          }
        }
      }
      await _load();
      if (!mounted) return;
      if (modelError != null) {
        _toast(_failureText(modelError, 'providers.addFailed'));
      } else {
        _toast(tr(context, 'providers.added'));
      }
    } catch (e) {
      if (!mounted) return;
      _toast(_failureText(e, 'providers.addFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'providers.title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'providers.add')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _providers.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final p = _providers[index];
                      final enabled = p['enabled'] == true;
                      final endpoints = p['endpoints'];
                      final baseUrl = endpoints is Map
                          ? '${endpoints['baseURL'] ?? ''}'
                          : '';
                      final models =
                          p['models'] is List ? p['models'] as List : [];
                      final disabledReason =
                          p['systemDisabledReason'] as String?;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${p['name'] ?? p['id']}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        '${p['apiFormat'] ?? ''}',
                                        if (models.isNotEmpty)
                                          trP(context, 'providers.modelsCount',
                                              ['${models.length}']),
                                        baseUrl,
                                        if (!enabled &&
                                            disabledReason != null)
                                          trP(context, 'providers.disabled',
                                              [disabledReason]),
                                      ]
                                          .where((s) => s.isNotEmpty)
                                          .join(' · '),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: ZInk.faint(context)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: enabled,
                                onChanged: (v) => _toggle(p, v),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 18, color: ZInk.faint(context)),
                                onPressed: () => _delete(p),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _AddProviderSheet extends StatefulWidget {
  const _AddProviderSheet();

  @override
  State<_AddProviderSheet> createState() => _AddProviderSheetState();
}

class _AddProviderSheetState extends State<_AddProviderSheet> {
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelsController = TextEditingController();
  String _apiFormat = 'anthropic-messages';

  static const _formats = [
    'anthropic-messages',
    'openai-chat-completions',
    'openai-responses',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelsController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (name.isEmpty || baseUrl.isEmpty) return;
    final modelIds = _modelsController.text
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    Navigator.pop(
      context,
      {
        ...personalProviderDraft(
          name: name,
          apiType: _apiFormat,
          baseUrl: baseUrl,
          apiKey: _apiKeyController.text.trim(),
        ),
        'modelIds': modelIds,
      },
    );
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
          Text(tr(context, 'providers.addTitle'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
                labelText: tr(context, 'providers.name'),
                hintText: 'My Provider'),
          ),
          const SizedBox(height: 10),
          DropdownField<String>(
            value: _apiFormat,
            decoration: InputDecoration(
                labelText: tr(context, 'providers.apiFormat')),
            items: [
              for (final f in _formats)
                DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) => setState(() => _apiFormat = v ?? _apiFormat),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com/api/anthropic',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: InputDecoration(
                labelText: tr(context, 'providers.apiKey')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelsController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: tr(context, 'providers.models'),
              hintText: 'GLM-5.2, GLM-5-Turbo',
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
