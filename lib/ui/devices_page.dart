import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/zic_logo.dart';
import '../protocol/connection_params.dart';
import '../state/device_session.dart';
import '../state/device_store.dart';
import '../state/scheduled_store.dart';
import '../widgets/home_widget_bridge.dart';
import 'login_page.dart' show runLoginFlowForHost;
import 'startup_diagnostics.dart';
import 'qr_scan_page.dart';
import 'remote_page.dart';
import 'scheduled_page.dart';
import 'settings_page.dart';
import 'task_list_page.dart';
import 'theme.dart';
import 'ui_settings.dart';

/// Keep in sync with pubspec.yaml `version`. A const (not PackageInfo) so
/// the blocked card can show it without any platform call.
const appDisplayVersion = '1.0.12';

/// Home: the device list with live native status. Tap a card to open the
/// native task list (or WebView fallback), long-term management via the
/// overflow menu. Supports clipboard offer-to-add, drag-reorder and pin.
class DevicesPage extends StatefulWidget {
  final DeviceStore store;
  final ThemeController theme;
  final UiSettings ui;
  final DeviceSessionHub hub;
  final ScheduledStore scheduled;
  const DevicesPage({
    super.key,
    required this.store,
    required this.theme,
    required this.ui,
    required this.hub,
    required this.scheduled,
  });

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage>
    with WidgetsBindingObserver {
  /// Last clipboard URL we already offered (or the user dismissed) so we
  /// don't spam the snackbar on every resume.
  String? _clipboardHandled;

  /// Startup watchdog. Degraded devices (low-battery throttling, cold
  /// dexopt) can legitimately need >6s for the first storage round-trip —
  /// verified by the 1.0.4 diagnostics panel (all probes OK after
  /// warm-up, yet the 6s guard had tripped). 20s guard, auto-retry, live
  /// elapsed display, and recovery on ANY completion path.
  bool _loadTimedOut = false;
  Timer? _loadWatchdog;
  Timer? _elapsedTimer;
  Timer? _autoRetryTimer;
  int _autoRetries = 0;
  static const _maxAutoRetries = 5;
  final Stopwatch _loadElapsed = Stopwatch();
  final StartupDiagnostics _diagnostics = StartupDiagnostics();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armLoadWatchdog();
    _loadElapsed.start();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_loadTimedOut && mounted) setState(() {});
    });
    widget.store.load().then((_) => _onLoaded());
    widget.store.addListener(_onLoaded);
    widget.store.addListener(_onStoreChanged);
    widget.ui.addListener(_syncConnections);
  }

  /// Any completion path — the page's own load future, a late store
  /// notification, or an auto-retry — recovers the UI.
  void _onLoaded() {
    if (!widget.store.loaded) return;
    _loadWatchdog?.cancel();
    _autoRetryTimer?.cancel();
    final wasTimedOut = _loadTimedOut;
    if (mounted && _loadTimedOut) {
      _loadTimedOut = false;
    }
    if (!mounted) return;
    if (wasTimedOut) {
      setState(() {});
    } else {
      _syncConnections();
      _syncHomeWidget();
      _checkClipboard();
    }
  }

  void _armLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 20), () {
      if (!widget.store.loaded && mounted) {
        setState(() => _loadTimedOut = true);
        unawaited(_diagnostics.run());
        _scheduleAutoRetry();
      }
    });
  }

  void _scheduleAutoRetry() {
    if (_autoRetries >= _maxAutoRetries) return;
    _autoRetries += 1;
    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer(const Duration(seconds: 12), () {
      if (!widget.store.loaded && mounted) {
        widget.store.load().then((_) => _onLoaded());
      }
    });
  }

  @override
  void dispose() {
    _loadWatchdog?.cancel();
    _elapsedTimer?.cancel();
    _autoRetryTimer?.cancel();
    _diagnostics.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_onLoaded);
    widget.store.removeListener(_onStoreChanged);
    widget.ui.removeListener(_syncConnections);
    super.dispose();
  }

  void _onStoreChanged() {
    _syncConnections();
    _syncHomeWidget();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
      _syncHomeWidget();
    }
  }

  void _syncHomeWidget() {
    HomeWidgetBridge.syncDevices(widget.store.devices);
  }

  /// Keeps native connections in step with the device list and the
  /// native-list switch (see [DeviceSessionHub.syncWith]).
  void _syncConnections() {
    if (!widget.store.loaded || !mounted) return;
    widget.hub.syncWith(widget.store.devices);
  }

  /// On resume / first load: if the clipboard holds a remote URL that is
  /// not already saved, offer to add it.
  Future<void> _checkClipboard() async {
    if (!mounted) return;
    // Widget tests have no clipboard channel — skip to avoid pending timers.
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName.contains('TestWidgetsFlutterBinding') ||
        bindingName.contains('AutomatedTest')) {
      return;
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty || text == _clipboardHandled) return;
      if (RemoteConnectionParams.parse(text) == null) return;
      if (widget.store.devices.any((d) => d.url == text)) {
        _clipboardHandled = text;
        return;
      }
      _clipboardHandled = text;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Row(
            children: [
              Expanded(child: Text(tr(context, 'devices.clipboard.offer'))),
              // 关闭: dismiss without adding (re-offers next session).
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: tr(context, 'common.cancel'),
                onPressed: () => messenger.hideCurrentSnackBar(),
              ),
            ],
          ),
          action: SnackBarAction(
            label: tr(context, 'devices.clipboard.add'),
            onPressed: () async {
              await widget.store.addUrl(text);
            },
          ),
        ),
      );
    } catch (_) {
      // Clipboard access can fail on some platforms / permissions / tests.
    }
  }

  /// Card tap: native task list when the protocol link is healthy, the
  /// WebView remote page otherwise.
  Future<void> _open(Device device) async {
    final session = widget.hub.sessionOf(device.id);
    if (widget.ui.nativeListEnabled &&
        session != null &&
        session.status != DeviceStatus.error) {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _deviceThemeWrap(
          device,
          TaskListPage(
            store: widget.store,
            hub: widget.hub,
            device: device,
            theme: widget.theme,
          ),
        ),
      ));
      return;
    }
    await _openRemote(device);
  }

  /// Applies the device URL's `theme=dark|light` for the opened route.
  Widget _deviceThemeWrap(Device device, Widget child) {
    final hint = device.themeHint;
    if (hint == null) return child;
    final data = hint == ThemeModeHint.dark
        ? buildDarkTheme()
        : buildLightTheme();
    return Theme(data: data, child: child);
  }

  /// Opens the in-app WebView remote page. The native connection is
  /// suspended first (one terminal per device) and resumes ~1s after the
  /// page pops. Injects `theme=` from the URL when present.
  Future<void> _openRemote(Device device) async {
    await widget.store.touch(device.id);
    await widget.hub.suspend(device.id);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _deviceThemeWrap(
        device,
        RemotePage(device: device),
      ),
    ));
    widget.hub.scheduleResume(device);
  }

  Future<void> _addByUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(context, 'devices.add.pasteTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          keyboardType: TextInputType.url,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: tr(context, 'devices.add.pasteHint2'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr(context, 'devices.add.cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: Text(tr(context, 'devices.add.confirm')),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    final device = await widget.store.addUrl(url);
    if (!mounted) return;
    if (device.params == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'devices.add.savedUnparsed'))),
      );
    }
  }

  Future<void> _addByScan() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (url == null || url.trim().isEmpty) return;
    final device = await widget.store.addUrl(url);
    if (!mounted) return;
    if (device.params == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'devices.add.savedUnparsed'))),
      );
    }
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(tr(context, 'devices.add.scan')),
              subtitle: Text(tr(context, 'devices.add.scanHint')),
              onTap: () {
                Navigator.pop(c);
                _addByScan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(tr(context, 'devices.add.paste')),
              subtitle: Text(tr(context, 'devices.add.pasteHint')),
              onTap: () {
                Navigator.pop(c);
                _addByUrl();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(Device device) async {
    final controller = TextEditingController(text: device.label);
    final label = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(context, 'devices.rename.title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr(context, 'devices.rename.hint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr(context, 'devices.add.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, controller.text),
              child: Text(tr(context, 'devices.rename.save'))),
        ],
      ),
    );
    if (label != null) await widget.store.rename(device.id, label);
  }

  Future<void> _delete(Device device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(context, 'devices.delete.title')),
        content:
            Text(trP(context, 'devices.delete.body', [device.label])),
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
    if (confirm == true) await widget.store.remove(device.id);
  }

  Future<void> _copyUrl(Device device) async {
    await Clipboard.setData(ClipboardData(text: device.url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, 'devices.copy.done'))));
  }

  Future<void> _openInBrowser(Device device) async {
    await launchUrl(Uri.parse(device.url),
        mode: LaunchMode.externalApplication);
  }

  void _showExport() async {
    await Clipboard.setData(ClipboardData(text: widget.store.exportJson()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'devices.export.done'))),
    );
  }

  void _showScheduled() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScheduledPage(
        devices: widget.store,
        hub: widget.hub,
        store: widget.scheduled,
      ),
    ));
  }

  Future<void> _showImport() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(context, 'devices.import.title')),
        content: TextField(
          controller: controller,
          maxLines: 5,
          minLines: 3,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(hintText: tr(context, 'devices.import.hint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr(context, 'devices.add.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, controller.text),
              child: Text(tr(context, 'devices.import.confirm'))),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final n = await widget.store.importJson(raw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(trP(context, 'devices.import.done', ['$n']))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'devices.import.invalid'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([widget.store, widget.hub, widget.ui]),
          builder: (context, _) {
            final devices = widget.store.devices;
            // Entry is UNCONDITIONAL: the shell always renders and the
            // device list streams in. A storage layer that never answers
            // costs the list, never the app (verified hard requirement —
            // 1.0.0 entered fine, later builds blocked on this phone).
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, devices),
                if (!widget.store.loaded && !_loadTimedOut) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Text(
                      tr(context, 'home.loadingDevices'),
                      style: TextStyle(
                          fontSize: 12, color: ZInk.ghost(context)),
                    ),
                  ),
                ],
                if (!widget.store.loaded && _loadTimedOut) ...[
                  const SizedBox(height: 4),
                  _startupNotice(context),
                ],
                if (widget.store.degraded) ...[
                  const SizedBox(height: 4),
                  _degradedBanner(context),
                ],
                if (_needsLogin(devices)) ...[
                  const SizedBox(height: 4),
                  _authNotice(context, devices),
                ],
                Expanded(
                  child: devices.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [_emptyState(context)],
                        )
                      : RefreshIndicator(
                          onRefresh: () async => _syncConnections(),
                          edgeOffset: 8,
                          child: ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                            itemCount: devices.length + 1,
                            proxyDecorator: (child, index, animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (context, _) => Material(
                                  elevation: 2 + animation.value * 4,
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                  child: child,
                                ),
                              );
                            },
                            onReorderItem: (oldIndex, newIndex) {
                              widget.store.reorder(oldIndex, newIndex);
                            },
                            itemBuilder: (context, i) {
                              if (i == devices.length) {
                                return Padding(
                                  key: const ValueKey('zic-add-tile'),
                                  padding: const EdgeInsets.only(top: 4),
                                  child: _addTile(context),
                                );
                              }
                              final d = devices[i];
                              return Padding(
                                key: ValueKey(d.id),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _deviceCard(d),
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Brand header: mark + large title + live summary. No app bar — the
  /// page owns its whole canvas.
  Widget _header(BuildContext context, List<Device> devices) {
    final scheme = Theme.of(context).colorScheme;
    final running = widget.hub.activeSessions
        .fold<int>(0, (sum, s) => sum + s.runningTaskCount);
    final online = widget.hub.activeSessions
        .where((s) => s.status == DeviceStatus.connected)
        .length;
    final caption = devices.isEmpty
        ? tr(context, 'home.caption.start')
        : trP(context, 'home.caption.summary', [
            '${devices.length}',
            '$online',
            '$running',
          ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(
        children: [
          ZicMark(
            size: 42,
            color: scheme.primary,
            surfaceColor: scheme.surface,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'home.title'),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: ZInk.solid(context),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  caption,
                  style:
                      TextStyle(fontSize: 12, color: ZInk.muted(context)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr(context, 'settings.theme'),
            icon: Icon(
              widget.theme.mode == ThemeMode.dark
                  ? Icons.dark_mode_outlined
                  : widget.theme.mode == ThemeMode.light
                      ? Icons.light_mode_outlined
                      : Icons.contrast,
              size: 21,
            ),
            onPressed: () => widget.theme.cycle(),
          ),
          IconButton(
            tooltip: tr(context, 'settings.title'),
            icon: const Icon(Icons.settings_outlined, size: 21),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsPage(
                store: widget.store,
                theme: widget.theme,
                ui: widget.ui,
              ),
            )),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') _showExport();
              if (v == 'import') _showImport();
              if (v == 'sched') _showScheduled();
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                  value: 'export',
                  child: Text(tr(context, 'devices.menu.export'))),
              PopupMenuItem(
                  value: 'import',
                  child: Text(tr(context, 'devices.menu.import'))),
              PopupMenuItem(
                  value: 'sched', child: Text(tr(context, 'sched.menu'))),
            ],
          ),
        ],
      ),
    );
  }

  /// In-memory fallback banner: local storage never loaded; devices and
  /// the login won't survive an app restart until the storage issue is
  /// resolved.
  Widget _degradedBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ZInk.tile(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 16, color: ZInk.muted(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(context, 'home.degraded.banner'),
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: ZInk.soft(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Any v4 device whose native link is blocked on the missing login?
  bool _needsLogin(List<Device> devices) {
    return devices.any((d) {
      final params = d.params;
      if (params == null || params.passHash.isNotEmpty) return false;
      final session = widget.hub.sessionOf(d.id);
      return session == null || session.failureReason == 'auth-required';
    });
  }

  /// Slim sign-in notice for v4 links without a stored login.
  Widget _authNotice(BuildContext context, List<Device> devices) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final host = devices
        .firstWhere((d) =>
            d.params != null &&
            d.params!.passHash.isEmpty &&
            (widget.hub.sessionOf(d.id)?.failureReason == 'auth-required' ||
                widget.hub.sessionOf(d.id) == null))
        .params!
        .source
        .host;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: dark ? ZColors.accentTintDark : ZColors.accentTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.key_outlined,
                size: 16, color: dark ? ZColors.accentTextDark : ZColors.accentText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(context, 'home.authNotice'),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color:
                      dark ? ZColors.accentTextDark : ZColors.accentText,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () async {
                final ok = await runLoginFlowForHost(context, host);
                if (!ok || !mounted) return;
                for (final d in devices) {
                  widget.hub.sessionOf(d.id)?.reconnect();
                }
              },
              child: Text(tr(context, 'auth.login'),
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact startup notice (watchdog tripped): the app shell still
  /// renders and stays usable; this strip carries elapsed time, the
  /// fallback entry, and collapsible probe results.
  Widget _startupNotice(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ZInk.tile(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_bottom,
                    size: 15, color: ZInk.muted(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trP(context, 'home.startup.elapsed', [
                      '${_loadElapsed.elapsed.inSeconds}',
                      '$_autoRetries'
                    ]),
                    style: TextStyle(
                        fontSize: 12, color: ZInk.soft(context)),
                  ),
                ),
                Text('v$appDisplayVersion',
                    style:
                        TextStyle(fontSize: 10.5, color: ZInk.ghost(context))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact),
                    onPressed: () {
                      widget.store.forceLoadedInMemory();
                    },
                    child: Text(tr(context, 'home.startup.fallback'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact),
                    onPressed: _diagnostics.running
                        ? null
                        : () => unawaited(_diagnostics.run()),
                    child: Text(tr(context, 'home.startup.rerun'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            Theme(
              // Flat, divider-free expansion for the probe list.
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                listTileTheme: const ListTileThemeData(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 0,
                ),
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: Text(tr(context, 'home.startup.probes'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: ZInk.soft(context))),
                children: [
                  AnimatedBuilder(
                    animation: _diagnostics,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in _diagnostics.results)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                _probeDot(r),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text.rich(TextSpan(children: [
                                    TextSpan(
                                      text: '${r.label}  ',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: ZInk.soft(context)),
                                    ),
                                    TextSpan(
                                      text: '${r.stateLabel} ${r.elapsedMs}ms',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _probeColor(context, r)),
                                    ),
                                    if (r.detail != null)
                                      TextSpan(
                                        text: '\n${r.detail}',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: ZInk.ghost(context)),
                                      ),
                                  ])),
                                ),
                              ],
                            ),
                          ),
                        if (_diagnostics.results.isEmpty)
                          Text(_diagnostics.running
                              ? tr(context, 'home.startup.probing')
                              : tr(context, 'home.startup.probesEmpty'),
                              style: TextStyle(
                                  fontSize: 12, color: ZInk.muted(context))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _probeDot(ProbeResult r) {
    final color = switch (r.state) {
      ProbeState.ok => ZColors.successLight,
      ProbeState.timeout => ZColors.dangerLight,
      ProbeState.error => ZColors.warningDeep,
      ProbeState.pending => ZColors.neutral400,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Color _probeColor(BuildContext context, ProbeResult r) => switch (r.state) {
        ProbeState.ok => ZColors.successLight,
        ProbeState.timeout => Theme.of(context).colorScheme.error,
        ProbeState.error => ZColors.warningDeep,
        ProbeState.pending => ZInk.muted(context),
      };

  Widget _addTile(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _showAddSheet,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ZInk.hairline(context)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: ZInk.muted(context)),
              const SizedBox(width: 8),
              Text(
                tr(context, 'devices.add'),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: ZInk.soft(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: ZicMark(
              size: 58,
              color: scheme.onPrimary,
              surfaceColor: scheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(tr(context, 'devices.empty.title'),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: ZInk.solid(context))),
          const SizedBox(height: 8),
          Text(
            tr(context, 'devices.empty.body'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, height: 1.6, color: ZInk.faint(context)),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
            onPressed: _addByScan,
            icon: const Icon(Icons.qr_code_scanner, size: 19),
            label: Text(tr(context, 'home.empty.scan')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _addByUrl,
            child: Text(tr(context, 'home.empty.paste')),
          ),
        ],
      ),
    );
  }

  /// One device, Zic anatomy: a status ring on the left, the identity
  /// block in the middle, live counts on the right.
  Widget _deviceCard(Device device) {
    final host = device.params?.source.host ?? '';
    final session = widget.hub.sessionOf(device.id);
    final running = session?.runningTaskCount ?? 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(device),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index:
                    widget.store.devices.indexWhere((d) => d.id == device.id),
                child: _statusRing(context, session, device.pinned),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (device.pinned) ...[
                          Icon(Icons.pin_invoke_outlined,
                              size: 13, color: ZInk.muted(context)),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            device.label,
                            style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      host.isNotEmpty
                          ? '${_statusText(context, session)} · $host'
                          : _statusText(context, session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: ZInk.muted(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.lastUsedAt != null
                          ? trP(context, 'devices.lastUsed',
                              [relativeTime(context, device.lastUsedAt!)])
                          : tr(context, 'devices.neverUsed'),
                      style:
                          TextStyle(fontSize: 11, color: ZInk.ghost(context)),
                    ),
                  ],
                ),
              ),
              if (running > 0) ...[
                const SizedBox(width: 8),
                _runningPill(context, running),
              ],
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon:
                    Icon(Icons.more_vert, size: 20, color: ZInk.ghost(context)),
                onSelected: (v) {
                  switch (v) {
                    case 'pin':
                      widget.store.setPinned(device.id, !device.pinned);
                    case 'rename':
                      _rename(device);
                    case 'web':
                      _openRemote(device);
                    case 'browser':
                      _openInBrowser(device);
                    case 'copy':
                      _copyUrl(device);
                    case 'delete':
                      _delete(device);
                  }
                },
                itemBuilder: (c) => [
                  PopupMenuItem(
                      value: 'pin',
                      child: Text(tr(
                          context,
                          device.pinned
                              ? 'devices.menu.unpin'
                              : 'devices.menu.pin'))),
                  PopupMenuItem(
                      value: 'rename',
                      child: Text(tr(context, 'devices.menu.rename'))),
                  PopupMenuItem(
                      value: 'web',
                      child: Text(tr(context, 'devices.menu.web'))),
                  PopupMenuItem(
                      value: 'browser',
                      child: Text(tr(context, 'devices.menu.browser'))),
                  PopupMenuItem(
                      value: 'copy',
                      child: Text(tr(context, 'devices.menu.copy'))),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(tr(context, 'devices.menu.delete'),
                        style: TextStyle(
                            color: Theme.of(c).colorScheme.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The status ring: state-colored halo around a desktop glyph. This is
  /// the home page's primary status surface.
  Widget _statusRing(
      BuildContext context, DeviceSession? session, bool pinned) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (ring, glyph) = switch (session?.status) {
      DeviceStatus.connected => (
          dark ? ZColors.success : ZColors.successLight,
          dark ? ZColors.success : ZColors.successLight
        ),
      DeviceStatus.connecting => (ZColors.accent, ZColors.accent),
      DeviceStatus.error => (
          dark ? ZColors.danger : ZColors.dangerLight,
          dark ? ZColors.danger : ZColors.dangerLight
        ),
      _ => (ZInk.muted(context), ZInk.muted(context)),
    };
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring.withValues(alpha: dark ? 0.14 : 0.10),
        border: Border.all(color: ring.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Icon(
        pinned ? Icons.push_pin_outlined : Icons.desktop_windows_outlined,
        size: 20,
        color: glyph,
      ),
    );
  }

  Widget _runningPill(BuildContext context, int running) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: dark ? ZColors.accentTintDark : ZColors.accentTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: ZColors.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            running > 9 ? '9+' : '$running',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: dark ? ZColors.accentTextDark : ZColors.accentText,
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(BuildContext context, DeviceSession? session) {
    if (session == null) return tr(context, 'status.offline');
    if (session.status == DeviceStatus.connected) {
      return session.runningTaskCount > 0
          ? trP(
              context, 'status.tasksRunning', ['${session.runningTaskCount}'])
          : tr(context, 'status.online');
    }
    if (session.status == DeviceStatus.error) {
      return session.kicked
          ? tr(context, 'status.kicked')
          : tr(context, 'status.error');
    }
    return tr(context, 'status.connecting');
  }
}
