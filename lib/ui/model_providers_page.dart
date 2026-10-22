import 'package:flutter/material.dart';

import '../protocol/channel_client.dart';
import '../protocol/id.dart';
import '../state/device_session.dart';
import 'theme.dart';
import 'ui_settings.dart';
import 'widgets/dropdown_field.dart';

/// Model provider management of one device (model-provider channel:
/// getAll/save/delete), restyled with the Zic tokens.
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

  /// Web parity: `model-provider.onDidChangeProviderRegistry` pushes
  /// registry revisions — reload the list whenever the desktop changes it.
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
      Channels.modelProvider,
      'onDidChangeProviderRegistry',
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
      final res =
          await widget.session.callChannel('model-provider', 'getAll');
      if (mounted) {
        setState(() {
          _providers = res is List
              ? res
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList()
              : const [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save(Map<String, dynamic> provider) async {
    await widget.session.callChannel('model-provider', 'save', [
      {
        ...provider,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    ]);
  }

  Future<void> _toggle(Map<String, dynamic> provider, bool enabled) async {
    try {
      await _save({...provider, 'enabled': enabled});
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(trP(context, 'providers.toggleFailed', ['$e']));
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
      await widget.session
          .callChannel('model-provider', 'delete', [
        {'id': provider['id']}
      ]);
    } on ChannelRpcError {
      // Fallback: try alternate parameter shape.
      try {
        await widget.session
            .callChannel('model-provider', 'delete', ['${provider['id']}']);
      } catch (e2) {
        if (!mounted) return;
        _toast(trP(context, 'providers.deleteFailed', ['$e2']));
        return;
      }
    } catch (e) {
      if (!mounted) return;
      _toast(trP(context, 'providers.deleteFailed', ['$e']));
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
      builder: (context) => _AddProviderSheet(session: widget.session),
    );
    if (added == null) return;
    try {
      await _save(added);
      await _load();
      if (!mounted) return;
      _toast(tr(context, 'providers.added'));
    } catch (e) {
      if (!mounted) return;
      _toast(trP(context, 'providers.addFailed', ['$e']));
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
                  child: Text(trP(context, 'providers.loadFailed', [_error!])))
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
  final DeviceSession session;
  const _AddProviderSheet({required this.session});

  @override
  State<_AddProviderSheet> createState() => _AddProviderSheetState();
}

class _AddProviderSheetState extends State<_AddProviderSheet> {
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelsController = TextEditingController();
  String _apiFormat = 'anthropic-messages';
  List<String> _suggestions = const [];
  bool _fetchingModels = false;

  static const _formats = [
    'anthropic-messages',
    'openai-chat',
    'gemini',
  ];

  /// Web parity: `model-provider.getEndpointSuggestions` (preset endpoints)
  /// and `getModelsByEndpoint` (fills the model list automatically).
  Future<dynamic> _call(String method, List<Object?> args) =>
      widget.session.callChannel('model-provider', method, args);

  Future<void> _suggestEndpoints() async {
    try {
      final res = await _call('getEndpointSuggestions', []);
      final list = res is Map ? res['suggestions'] : res;
      if (mounted) {
        setState(() => _suggestions = [
              for (final s0 in (list as List? ?? const [])) '$s0',
            ]);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _suggestions = const []);
      }
    }
  }

  Future<void> _fetchModels(String endpoint) async {
    setState(() => _fetchingModels = true);
    try {
      final res = await _call('getModelsByEndpoint', [endpoint]);
      final ids = <String>[];
      if (res is List) {
        for (final m in res) {
          ids.add(m is Map ? '${m['id'] ?? m['modelId'] ?? ''}' : '$m');
        }
      } else if (res is Map && res['models'] is List) {
        for (final m in res['models'] as List) {
          ids.add(m is Map ? '${m['id'] ?? m['modelId'] ?? ''}' : '$m');
        }
      }
      if (mounted) {
        setState(() {
          _modelsController.text = ids.where((i) => i.isNotEmpty).join(', ');
          _fetchingModels = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

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
    final now = DateTime.now().millisecondsSinceEpoch;
    final modelIds = _modelsController.text
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final kind = _apiFormat.startsWith('anthropic')
        ? 'anthropic'
        : _apiFormat.startsWith('openai')
            ? 'openai'
            : 'gemini';
    Navigator.pop(context, {
      'id': 'custom:${generateUuid()}',
      'name': name,
      'enabled': true,
      'endpoints': {
        'baseURL': baseUrl,
        'paths': {kind: '/v1/messages'},
      },
      'apiFormat': _apiFormat,
      'source': 'custom',
      if (_apiKeyController.text.trim().isNotEmpty)
        'apiKey': _apiKeyController.text.trim(),
      'defaultKind': kind,
      'models': [
        for (var i = 0; i < modelIds.length; i++)
          {
            'id': modelIds[i],
            'kinds': [kind],
            'defaultKind': kind,
            'modalities': {
              'input': ['text'],
              'output': ['text'],
            },
            'priority': 100 + i,
          },
      ],
      'createdAt': now,
      'updatedAt': now,
    });
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
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com/api/anthropic',
              suffixIcon: IconButton(
                icon: const Icon(Icons.auto_awesome, size: 18),
                tooltip: tr(context, 'providers.suggest'),
                onPressed: _suggestEndpoints,
              ),
            ),
          ),
          if (_suggestions.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s0 in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(s0,
                            style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          _baseUrlController.text = s0;
                          _fetchModels(s0);
                        },
                      ),
                    ),
                ],
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
              suffixIcon: _fetchingModels
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
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
