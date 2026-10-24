import 'package:flutter_test/flutter_test.dart';
import 'package:zic/protocol/provider_settings.dart';

void main() {
  test('getView providers become list rows', () {
    final rows = parseProviderSettingsView({
      'revision': 3,
      'providers': [
        {
          'providerId': 'custom:1',
          'providerName': 'DeepSeek',
          'enabled': true,
          'templateId': 'openai',
          'effectiveConfig': {
            'api': {
              'type': 'openai-chat-completions',
              'baseUrl': 'https://api.deepseek.com/v1',
            },
          },
          'personalConfig': {
            'api': {'type': 'openai-chat-completions'},
            'personalModelIds': ['deepseek-v4'],
          },
          'models': [
            {'modelId': 'deepseek-v4', 'enabled': true},
          ],
          'issues': [
            {'message': 'Key missing'},
          ],
        },
      ],
    });

    expect(rows, hasLength(1));
    expect(rows.single['id'], 'custom:1');
    expect(rows.single['name'], 'DeepSeek');
    expect(rows.single['enabled'], isTrue);
    expect(rows.single['apiFormat'], 'openai-chat-completions');
    expect(rows.single['endpoints'], {
      'baseURL': 'https://api.deepseek.com/v1',
    });
    expect(rows.single['models'], hasLength(1));
    expect(rows.single['systemDisabledReason'], 'Key missing');
    expect(
      personalProviderOverlay(rows.single),
      {'api': {'type': 'openai-chat-completions'}},
    );
  });

  test('a legacy list is kept', () {
    final rows = parseProviderSettingsView([
      {'id': 'old', 'name': 'Old', 'endpoints': {'baseURL': 'https://x'}},
    ]);
    expect(rows.single['name'], 'Old');
  });

  test('create draft carries the api type and optional key', () {
    expect(
      personalProviderDraft(
        name: 'Mine',
        apiType: 'anthropic-messages',
        baseUrl: 'https://api.example.com',
        apiKey: 'sk-1',
      ),
      {
        'providerName': 'Mine',
        'initialConfig': {
          'api': {
            'type': 'anthropic-messages',
            'baseUrl': 'https://api.example.com',
          },
          'access': {'type': 'api-key', 'apiKey': 'sk-1'},
        },
      },
    );
  });
}
