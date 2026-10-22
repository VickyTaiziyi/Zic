import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../update/app_channel.dart';
import 'document_page.dart';
import 'external_link.dart';
import 'legal_copy.dart';
import 'notices_page.dart';
import 'theme.dart';
import 'ui_settings.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _build = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    } catch (_) {
      // Version display is best-effort.
    }
  }

  bool get _en =>
      UiSettingsProvider.of(context)?.locale.startsWith('en') ?? false;

  Future<void> _openExternal(String url) async {
    final ok = await openPinnedUrl(url);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'about.linkFailed'))));
  }

  void _openDocument(String titleKey, List<LegalBlock> blocks) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocumentPage(title: tr(context, titleKey), blocks: blocks),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'settings.about'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const SizedBox(height: 24),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 72,
                height: 72,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Zic',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ZInk.solid(context),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              _version.isEmpty
                  ? ''
                  : '${tr(context, 'about.version')} $_version ($_build)',
              style: TextStyle(fontSize: 12, color: ZInk.muted(context)),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              tr(context, 'about.android'),
              style: TextStyle(fontSize: 12, color: ZInk.muted(context)),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(tr(context, 'about.githubHome')),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openExternal(officialGithubProfile),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(tr(context, 'about.github')),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openExternal(officialGithubRepo),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(tr(context, 'about.blog')),
            subtitle: const Text('vicyi.com'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openExternal(officialBlog),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr(context, 'about.privacy')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDocument(
                'about.privacy', privacyBlocks(_en)),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(tr(context, 'about.rights')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _openDocument('about.rights', rightsBlocks(_en)),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(tr(context, 'about.notices')),
            subtitle: Text(tr(context, 'about.noticesHint')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const NoticesPage(),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr(context, 'about.licenses')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Zic',
              applicationVersion:
                  _version.isEmpty ? null : '$_version+$_build',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(context, 'about.disclaimer'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: ZInk.ghost(context)),
            ),
          ),
        ],
      ),
    );
  }
}
