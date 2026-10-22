import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_auth.dart';
import '../state/device_store.dart';
import '../update/app_channel.dart';
import '../update/update_prompt.dart';
import 'about_page.dart';
import 'login_page.dart' show runLoginFlowForHost;
import 'theme.dart';
import 'ui_settings.dart';
import 'usage_stats_page.dart';

/// App settings: theme, language, native-list switch, plus links to
/// usage stats and about.
class SettingsPage extends StatefulWidget {
  final DeviceStore store;
  final ThemeController theme;
  final UiSettings ui;
  const SettingsPage({
    super.key,
    required this.store,
    required this.theme,
    required this.ui,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = false;
  Future<bool>? _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = sessionAuth.hasSession('zcode.z.ai');
  }

  void _refreshSession() {
    _sessionFuture = sessionAuth.hasSession('zcode.z.ai');
  }

  /// v4 cookie-auth entry: sign in on the official page, or drop the
  /// stored session (keystore + WebView jar) on sign-out.
  Future<void> _handleAuthAction(BuildContext context,
      {required bool signedIn}) async {
    if (signedIn) {
      await sessionAuth.clear();
      try {
        await CookieManager.instance().deleteCookies(
          url: WebUri('https://zcode.z.ai'),
        );
      } catch (_) {}
      if (!mounted) return;
      setState(_refreshSession);
      ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text(tr(this.context, 'auth.signedOut'))));
      return;
    }
    final ok = await runLoginFlowForHost(context, 'zcode.z.ai');
    if (ok && mounted) setState(_refreshSession);
  }

  /// Store builds open their listing. The github build checks the pinned
  /// repository and offers a browser download. The app never installs an APK.
  Future<void> _checkForUpdates() async {
    if (_checking) return;
    final storeUrl = storeListingUrl;
    if (storeUrl != null) {
      await launchUrl(storeUrl, mode: LaunchMode.externalApplication);
      return;
    }
    if (appChannel == 'appstore') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'update.storePending'))));
      return;
    }
    setState(() => _checking = true);
    try {
      await presentGithubUpdate(context, silent: false);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final ui = widget.ui;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'settings.title'))),
      body: AnimatedBuilder(
        animation: Listenable.merge([theme, ui]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _header(context, tr(context, 'settings.appearance')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(tr(context, 'settings.theme')),
                  const Spacer(),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(tr(context, 'settings.theme.dark')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(tr(context, 'settings.theme.light')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(tr(context, 'settings.theme.system')),
                      ),
                    ],
                    selected: {theme.mode},
                    onSelectionChanged: (s) => theme.setMode(s.first),
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
            _header(context, tr(context, 'settings.general')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(tr(context, 'settings.language')),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'zh-CN',
                        label: Text(tr(context, 'settings.language.zh')),
                      ),
                      ButtonSegment(
                        value: 'en-US',
                        label: Text(tr(context, 'settings.language.en')),
                      ),
                    ],
                    selected: {ui.locale},
                    onSelectionChanged: (s) => ui.setLocale(s.first),
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.list_alt_outlined),
              title: Text(tr(context, 'settings.nativeList')),
              subtitle: Text(tr(context, 'settings.nativeListHint')),
              value: ui.nativeListEnabled,
              onChanged: (v) => ui.setNativeListEnabled(v),
            ),
            _header(context, tr(context, 'settings.account')),
            FutureBuilder<bool>(
              future: _sessionFuture,
              builder: (context, snap) => ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(tr(context, snap.data == true
                    ? 'auth.logged-in'
                    : 'auth.not-logged-in')),
                subtitle: Text(tr(context, 'auth.subtitle')),
                trailing: FilledButton.tonal(
                  onPressed: () => _handleAuthAction(context,
                      signedIn: snap.data == true),
                  child: Text(tr(context, snap.data == true
                      ? 'auth.logout'
                      : 'auth.login')),
                ),
              ),
            ),
            _header(context, tr(context, 'settings.notifications')),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: Text(tr(context, 'settings.notifications')),
              subtitle: Text(tr(context, 'settings.notificationsHint')),
              value: ui.notificationsEnabled,
              onChanged: (v) => ui.setNotificationsEnabled(v),
            ),
            if (ui.notificationsEnabled) ...[
              SwitchListTile(
                secondary: const SizedBox(width: 24),
                dense: true,
                title: Text(tr(context, 'settings.notify.tasks')),
                value: ui.notifyTasksEnabled,
                onChanged: (v) => ui.setNotifyTasksEnabled(v),
              ),
              SwitchListTile(
                secondary: const SizedBox(width: 24),
                dense: true,
                title: Text(tr(context, 'settings.notify.offPeak')),
                value: ui.notifyOffPeakEnabled,
                onChanged: (v) => ui.setNotifyOffPeakEnabled(v),
              ),
              SwitchListTile(
                secondary: const SizedBox(width: 24),
                dense: true,
                title: Text(tr(context, 'settings.notify.auto')),
                value: ui.notifyAutoEnabled,
                onChanged: (v) => ui.setNotifyAutoEnabled(v),
              ),
            ],
            _header(context, tr(context, 'settings.data')),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: Text(tr(context, 'settings.usageStats')),
              subtitle: Text(tr(context, 'settings.usageStatsHint')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    UsageStatsPage(store: widget.store, ui: widget.ui),
              )),
            ),
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text(tr(context, 'settings.checkUpdate')),
              trailing: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _checkForUpdates,
            ),
            _header(context, tr(context, 'settings.about')),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(tr(context, 'settings.about')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AboutPage(),
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ZInk.muted(context),
          ),
        ),
      );
}
