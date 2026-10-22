import 'package:flutter/material.dart';

import '../state/device_session.dart';
import 'theme.dart';
import 'ui_settings.dart';

/// Entitlement / quota usage of one device
/// (usage-stats.getEntitlementSnapshot over the workspace bridge).
class DeviceUsagePage extends StatefulWidget {
  final DeviceSession session;
  const DeviceUsagePage({super.key, required this.session});

  @override
  State<DeviceUsagePage> createState() => _DeviceUsagePageState();
}

class _DeviceUsagePageState extends State<DeviceUsagePage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  /// App-usage snapshot (`getAppUsageSnapshot {range, timeZone}`) — the
  /// local-session-based estimation tab of the web settings usage page.
  String _appRange = '7d';
  Map<String, dynamic>? _appUsage;
  bool _appLoading = false;

  static const _appRanges = ['7d', '30d', '90d', 'all'];

  @override
  void initState() {
    super.initState();
    _load();
    _loadAppUsage();
  }

  Future<void> _loadAppUsage() async {
    if (!mounted) return;
    setState(() => _appLoading = true);
    try {
      final res = await widget.session.callChannel(
        'usage-stats',
        'getAppUsageSnapshot',
        [
          {'range': _appRange, 'timeZone': DateTime.now().timeZoneName},
        ],
      );
      if (mounted) {
        setState(() {
          _appUsage = res is Map ? res.cast<String, dynamic>() : {};
          _appLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _appLoading = false);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.session.callChannel(
        'usage-stats',
        'getEntitlementSnapshot',
        [
          {'includeSubscription': true}
        ],
      );
      if (mounted) {
        setState(() {
          _data = res is Map ? res.cast<String, dynamic>() : {};
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

  String _fmtTime(Object? millis) {
    if (millis is! num) return '-';
    final t = DateTime.fromMillisecondsSinceEpoch(millis.toInt()).toLocal();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'usageRpc.title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(trP(context, 'usageRpc.loadFailed', [_error!])))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final data = _data ?? const {};
    final context_ = data['context'];
    final provider = data['provider'];
    final remaining = data['remaining'];
    final subscription = data['subscription'];
    final quota = data['quota'];

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _loadAppUsage();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _appUsageCard(context),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ZColors.sky500.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt, color: ZColors.sky500),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context_ is Map
                              ? '${context_['displayName'] ?? '-'}'
                              : '-',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            if (provider is Map) '${provider['name'] ?? ''}',
                            if (quota is Map && quota['level'] != null)
                              '${quota['level']}',
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 12, color: ZInk.faint(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (remaining is Map && remaining['isShow'] == true)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tr(context, 'usageRpc.remaining'),
                            style: const TextStyle(fontSize: 14)),
                        Text(
                          '${remaining['count'] ?? '-'}',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ZColors.sky500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:
                            ((remaining['percentage'] as num?) ?? 0) / 100,
                        minHeight: 6,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor:
                            const AlwaysStoppedAnimation(ZColors.sky500),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      trP(context, 'usageRpc.remainingDetail', [
                        '${remaining['percentage'] ?? '-'}',
                        _fmtTime(remaining['nextResetTime']),
                      ]),
                      style: TextStyle(
                          fontSize: 11, color: ZInk.faint(context)),
                    ),
                  ],
                ),
              ),
            ),
          if (quota is Map && quota['limits'] is List) ...[
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'usageRpc.limits'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (final limit in quota['limits'] as List)
                      if (limit is Map)
                        _LimitRow(
                            limit: limit.cast<String, dynamic>(),
                            fmtTime: _fmtTime),
                  ],
                ),
              ),
            ),
          ],
          if (subscription is Map &&
              subscription['details'] is List &&
              (subscription['details'] as List).isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'usageRpc.subscription'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (final d in subscription['details'] as List)
                      if (d is Map) ...[
                        _kv(tr(context, 'usageRpc.product'),
                            '${d['productName'] ?? '-'}'),
                        _kv(tr(context, 'usageRpc.billing'),
                            '${d['billingCycle'] ?? '-'}'),
                        _kv(tr(context, 'usageRpc.renew'),
                            '${d['renewTime'] ?? '-'}'),
                        _kv(tr(context, 'usageRpc.expire'),
                            '${d['expireTime'] ?? '-'}'),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 应用用量: dailyModelUsage stacked bars (per-day totals with model
  /// breakdown), web `settings.usage.tab.appUsage` parity.
  Widget _appUsageCard(BuildContext context) {
    final daily = _appUsage?['dailyModelUsage'];
    final days = daily is List ? daily.whereType<Map>().toList() : <Map>[];
    double maxTotal = 0;
    final rows = <(String, double, Map<String, double>)>[];
    for (final d in days) {
      final models = <String, double>{};
      final list = d['models'];
      var total = 0.0;
      if (list is List) {
        for (final m in list.whereType<Map>()) {
          final tokens = ((m['totalTokens'] as num?) ?? 0).toDouble();
          final id = '${m['modelId'] ?? '?'}';
          models[id] = (models[id] ?? 0) + tokens;
          total += tokens;
        }
      }
      if (total > maxTotal) maxTotal = total;
      rows.add(('${d['date'] ?? ''}', total, models));
    }
    final modelIds = <String>{for (final r in rows) for (final k in r.$3.keys) k}.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr(context, 'usageRpc.appUsage'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                for (final r in _appRanges)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      if (_appRange == r || _appLoading) return;
                      setState(() => _appRange = r);
                      _loadAppUsage();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        r == 'all' ? tr(context, 'usageRpc.rangeAll') : r,
                        style: TextStyle(
                          fontSize: 11,
                          color: _appRange == r
                              ? ZColors.sky500
                              : ZInk.muted(context),
                          fontWeight: _appRange == r
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(tr(context, 'usageRpc.appUsageHint'),
                style: TextStyle(fontSize: 10.5, color: ZInk.faint(context))),
            const SizedBox(height: 10),
            if (_appLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr(context, 'usageRpc.appUsageEmpty'),
                    style: TextStyle(fontSize: 12.5, color: ZInk.faint(context))),
              )
            else ...[
              for (final (date, total, models) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(date,
                              style: TextStyle(
                                  fontSize: 11, color: ZInk.muted(context))),
                          Text(_fmtTokens(total),
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 5,
                          child: Row(
                            children: [
                              for (final id in modelIds)
                                if ((models[id] ?? 0) > 0 && maxTotal > 0)
                                  Expanded(
                                    flex:
                                        ((models[id]! / maxTotal) * 100)
                                            .round()
                                            .clamp(1, 100),
                                    child: Container(
                                        color:
                                            _modelColor(id, modelIds)),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final id in modelIds)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: _modelColor(id, modelIds),
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text(id,
                            style: TextStyle(
                                fontSize: 10, color: ZInk.muted(context))),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _modelColor(String id, List<String> ids) {
    const palette = [
      ZColors.sky500,
      ZColors.success,
      ZColors.warning,
      ZColors.danger,
      ZColors.neutral500,
    ];
    final i = ids.indexOf(id);
    return palette[i % palette.length];
  }

  static String _fmtTokens(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.round().toString();
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: ZInk.muted(context))),
          Flexible(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  final Map<String, dynamic> limit;
  final String Function(Object?) fmtTime;

  const _LimitRow({required this.limit, required this.fmtTime});

  @override
  Widget build(BuildContext context) {
    final type = '${limit['type'] ?? ''}';
    final percentage = (limit['percentage'] as num?)?.toDouble();
    final usageDetails = limit['usageDetails'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$type · unit ${limit['unit'] ?? '-'}',
                  style: const TextStyle(fontSize: 12)),
              Text(
                [
                  if (limit['usage'] != null)
                    trP(context, 'usageRpc.used', ['${limit['usage']}']),
                  if (limit['remaining'] != null)
                    trP(context, 'usageRpc.left', ['${limit['remaining']}']),
                  if (percentage != null) '$percentage%',
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: ZInk.muted(context)),
              ),
            ],
          ),
          if (percentage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (percentage / 100).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    percentage > 80 ? ZColors.danger : ZColors.sky500,
                  ),
                ),
              ),
            ),
          if (usageDetails is List && usageDetails.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                usageDetails
                    .whereType<Map>()
                    .map((u) => '${u['modelCode']}: ${u['usage']}')
                    .join('  '),
                style:
                    TextStyle(fontSize: 10, color: ZInk.faint(context)),
              ),
            ),
          Text(
            trP(context, 'usageRpc.resetAt', [fmtTime(limit['nextResetTime'])]),
            style: TextStyle(fontSize: 10, color: ZInk.ghost(context)),
          ),
        ],
      ),
    );
  }
}
