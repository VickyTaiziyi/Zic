/// `provider-settings.getView` → the list the model settings page paints.
///
/// A bare list is the older `model-provider.getAll` shape and is kept as-is.
List<Map<String, dynamic>> parseProviderSettingsView(Object? res) {
  if (res is List) {
    return [
      for (final item in res)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }
  if (res is! Map) return const [];
  final list = res['providers'];
  if (list is! List) return const [];
  return [
    for (final item in list)
      if (item is Map)
        normalizeProviderSettingsRow(item.cast<String, dynamic>()),
  ];
}

/// One settings row. Legacy rows (name / endpoints) pass through.
Map<String, dynamic> normalizeProviderSettingsRow(Map<String, dynamic> raw) {
  if (raw['providerId'] == null &&
      (raw['name'] != null || raw['endpoints'] != null)) {
    return raw;
  }
  final config = raw['effectiveConfig'];
  final api = config is Map ? config['api'] : null;
  final baseUrl = api is Map ? '${api['baseUrl'] ?? ''}' : '';
  final apiType = api is Map ? '${api['type'] ?? ''}' : '';
  final models = raw['models'];
  final reason = _firstIssue(raw['issues']);
  return {
    'id': '${raw['providerId'] ?? raw['id'] ?? ''}',
    'name': '${raw['providerName'] ?? raw['name'] ?? raw['providerId'] ?? ''}',
    'enabled': raw['enabled'] == true,
    'apiFormat': apiType,
    'endpoints': {'baseURL': baseUrl},
    'models': models is List ? models : const <Object?>[],
    if (reason != null) 'systemDisabledReason': reason,
    'personalConfig': raw['personalConfig'],
    'templateId': raw['templateId'],
  };
}

/// Sparse personal overlay for `savePersonalProviderOverlay`. Membership
/// lists belong to the model add/remove calls, not this save.
Map<String, dynamic> personalProviderOverlay(Map<String, dynamic> provider) {
  final personal = provider['personalConfig'];
  if (personal is! Map) return const {};
  final overlay = Map<String, dynamic>.from(personal);
  overlay.remove('builtinModelIds');
  overlay.remove('personalModelIds');
  overlay.remove('modelOrder');
  return overlay;
}

/// `createPersonalProvider` argument.
Map<String, dynamic> personalProviderDraft({
  required String name,
  required String apiType,
  required String baseUrl,
  String? apiKey,
}) {
  return {
    'providerName': name,
    'initialConfig': {
      'api': {'type': apiType, 'baseUrl': baseUrl},
      if (apiKey != null && apiKey.isNotEmpty)
        'access': {'type': 'api-key', 'apiKey': apiKey},
    },
  };
}

String? _firstIssue(Object? issues) {
  if (issues is! List || issues.isEmpty) return null;
  final first = issues.first;
  if (first is Map) {
    final message = first['message'] ?? first['code'];
    if (message == null) return null;
    final text = '$message'.trim();
    return text.isEmpty ? null : text;
  }
  final text = '$first'.trim();
  return text.isEmpty ? null : text;
}
