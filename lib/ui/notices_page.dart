import 'package:flutter/material.dart';

import 'external_link.dart';
import 'oss_notices.dart';
import 'theme.dart';
import 'ui_settings.dart';

/// In-app acknowledgements. Each row opens only a pinned upstream URL.
class NoticesPage extends StatelessWidget {
  const NoticesPage({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final ok = await openPinnedUrl(url);
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'about.linkFailed'))));
  }

  @override
  Widget build(BuildContext context) {
    final en =
        UiSettingsProvider.of(context)?.locale.startsWith('en') ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'about.notices'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              en
                  ? 'Upstream projects and the license named in each package LICENSE for this build. The full texts are under Open-source licenses. flutter_secure_storage is not used.'
                  : '本构建直接依赖的上游，以及各包 LICENSE 中的许可证。完整文本在「开源许可」里。未使用 flutter_secure_storage。',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: ZInk.muted(context)),
            ),
          ),
          for (final notice in ossNotices)
            ListTile(
              title: Text(notice.version.isEmpty
                  ? notice.name
                  : '${notice.name} ${notice.version}'),
              subtitle: Text(notice.note.isEmpty
                  ? notice.license
                  : '${notice.license} · ${notice.note}'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(context, notice.url),
            ),
        ],
      ),
    );
  }
}
