import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_auth.dart';
import '../design/zic_logo.dart';
import '../protocol/connection_params.dart';
import '../state/app_kv.dart';
import 'theme.dart';
import 'ui_settings.dart';

/// Runs the official-page login flow for [params]' relay host and stores
/// the ZCode JWT. Returns true when a session is now stored.
Future<bool> runLoginFlow(
  BuildContext context,
  RemoteConnectionParams params, {
  SessionAuth? auth,
}) async {
  return runLoginFlowForHost(context, params.source.host, auth: auth);
}

/// Same flow, keyed by relay host (settings entry: no device needed).
Future<bool> runLoginFlowForHost(
  BuildContext context,
  String host, {
  SessionAuth? auth,
  Uri? initialUrl,
}) async {
  final header = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => LoginPage(
        host: host,
        initialUrl: initialUrl,
        auth: auth,
      ),
    ),
  );
  if (header == null || header.isEmpty) return false;
  await (auth ?? sessionAuth).saveJwt(host, header);
  return true;
}

/// Official-page sign-in that captures `localStorage["zcodejwttoken"]`.
///
/// That JWT is what `POST /api/v1/remote/token` accepts. WAF cookies set
/// on first paint are not a session and are ignored here. The page stays
/// on official hosts; the JWT never leaves the device.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.host,
    this.initialUrl,
    this.auth,
  });

  /// Relay host the cookies are captured for (e.g. `zcode.z.ai`).
  final String host;

  /// Optional pairing link to land on the remote page directly.
  final Uri? initialUrl;

  /// Optional auth service override (tests); defaults to the shared
  /// process-wide [sessionAuth].
  final SessionAuth? auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Timer? _harvestTimer;
  String? _lastJwt;
  DateTime? _lastChangedAt;
  bool _captured = false;

  static const _jwtProbeJs = '''
(function () {
  try {
    return JSON.stringify({
      zcodejwttoken: localStorage.getItem('zcodejwttoken') || ''
    });
  } catch (e) {
    return '';
  }
})()
''';
  double _progress = 0;

  /// Selected login method. Persisted per device; BigModel is the default
  /// (the primary account system for most ZCode users in China).
  static const _methodPrefKey = 'zic.login.method';
  String _method = 'bigmodel'; // 'bigmodel' | 'zai' | 'auto'
  InAppWebViewController? _webController;

  /// The official LOGIN page — verified: it hosts both account entries
  /// ("使用 BigModel 账号登录" / "使用 Z.ai 账号登录"). Loading the site
  /// root used to land on the homepage, whose only entry is the Z.AI
  /// trigger — which is why all method chips once looked identical.
  Uri get _launchUrl => Uri.parse('https://${widget.host}/login');

  bool get _hasJwt => _lastJwt != null && _lastJwt!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadMethodPref();
    _harvestTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _harvest(auto: true);
    });
  }

  Future<void> _loadMethodPref() async {
    try {
      final saved = await AppKv.instance.getString(_methodPrefKey);
      if (saved != null && mounted) {
        setState(() => _method = saved);
      }
    } catch (_) {}
  }

  Future<void> _setMethod(String m) async {
    setState(() => _method = m);
    // Reload in place through the live controller — never recreate the
    // WebView (recreation left a blank surface on some OEM WebViews).
    final controller = _webController;
    if (controller != null) {
      try {
        await controller.evaluateJavascript(source: 'window.__zicAutoEntry = 0;');
      } catch (_) {}
      unawaited(controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(_launchUrl.toString()))));
    }
    try {
      await AppKv.instance.setString(_methodPrefKey, m);
    } catch (_) {}
  }

  /// Best-effort autoclick of the chosen SSO entry on the OFFICIAL /login
  /// page. Both buttons are verified DOM text ("使用 BigModel 账号登录" /
  /// "使用 Z.ai 账号登录"). Guarded to fire once per page instance.
  static String? _autoClickJsFor(String method) {
    String matcher;
    switch (method) {
      case 'bigmodel':
        matcher = '使用\\\\s*BigModel\\\\s*账号登录';
      case 'zai':
        matcher = '使用\\\\s*Z\\\\.ai\\\\s*账号登录';
      default:
        return null; // 'auto': never interfere with the page.
    }
    return '''
(function () {
  if (window.__zicAutoEntry) return 'already';
  window.__zicAutoEntry = 1;
  var re = new RegExp("$matcher", 'i');
  var nodes = document.querySelectorAll('button, a, [role="tab"], span, div, li');
  for (var i = 0; i < nodes.length; i++) {
    var t = (nodes[i].innerText || '').trim();
    if (t && t.length <= 20 && re.test(t)) {
      nodes[i].click();
      return 'clicked:' + t;
    }
  }
  return 'notfound';
})()
''';
  }

  @override
  void dispose() {
    _harvestTimer?.cancel();
    super.dispose();
  }

  Future<void> _harvest({bool auto = false}) async {
    final controller = _webController;
    if (controller == null) return;
    try {
      final raw = await controller.evaluateJavascript(source: _jwtProbeJs);
      if (!mounted) return;
      final jwt = jwtFromStorageProbe(raw);
      setState(() {
        if (jwt != _lastJwt) {
          _lastJwt = jwt;
          _lastChangedAt = DateTime.now();
          _captured = false;
        }
        final settled = _lastChangedAt != null &&
            DateTime.now().difference(_lastChangedAt!) >=
                SessionAuth.captureStabilityDelay;
        if (!_captured && _hasJwt && settled && auto) {
          // Status only. 完成 is still required so a mid-login account
          // switch is not saved out from under the user.
          _captured = true;
        }
      });
    } catch (_) {
      // The page may not have a DOM yet. The next tick retries.
    }
  }

  void _finish() {
    final jwt = _lastJwt;
    if (jwt == null || jwt.isEmpty) return;
    Navigator.of(context).pop(jwt);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'login.title')),
        leading: const CloseButton(),
      ),
      // Full-bleed login: the WebView gets the whole canvas below a slim
        // status row — the previous shrunken card wasted half the screen
        // and made the official page's own inputs tiny and laggy to hit.
      body: Column(
        children: [
          // Slim live status strip (replaces the big header block).
          Container(
            width: double.infinity,
            color: scheme.brightness == Brightness.dark
                ? ZColors.darkCard
                : ZColors.lightCard,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: ZicMark(
                    size: 17,
                    color: scheme.onPrimary,
                    surfaceColor: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _captured
                        ? tr(context, 'login.status.captured')
                        : tr(context, 'login.status.waiting'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: _captured
                            ? ZColors.successLight
                            : ZInk.soft(context)),
                  ),
                ),
                TextButton(
                  onPressed: _hasJwt ? _finish : null,
                  child: Text(tr(context, 'login.done')),
                ),
              ],
            ),
          ),
          // Login-method chooser: which entry on the official page to use.
          // BigModel is the default and the last choice is remembered.
          Container(
            width: double.infinity,
            color: scheme.brightness == Brightness.dark
                ? ZColors.darkCard
                : ZColors.lightCard,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                for (final (id, label) in const [
                  ('bigmodel', 'login.method.bigmodel'),
                  ('zai', 'login.method.zai'),
                  ('auto', 'login.method.auto'),
                ]) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tr(context, label),
                          style: TextStyle(
                              fontSize: 11.5,
                              color: _method == id
                                  ? scheme.onPrimary
                                  : ZInk.soft(context))),
                      selected: _method == id,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) => _setMethod(id),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            // ONE WebView instance for the page's lifetime. Recreating it
            // per method switch (the old ValueKey) left a blank surface on
            // some OEM WebViews — hybrid-composition surfaces don't always
            // survive fast teardown/rebuild. Method switches now reload
            // in place via the controller.
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_launchUrl.toString())),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                supportZoom: false,
                // The WebView must share the default cookie jar
                // (incognito=false) so the official page and the harvest
                // see the same session.
                incognito: false,
                // Texture mode (not hybrid composition): the more
                // compatible path on OEM WebViews — the login page was
                // verified blank-in-hybrid on one device while the same
                // page loads fine in a desktop browser.
                useHybridComposition: false,
              ),
              onWebViewCreated: (c) => _webController = c,
              onProgressChanged: (_, p) => setState(() => _progress = p / 100),
              onLoadStop: (c, url) {
                setState(() => _progress = 1);
                _harvest();
                // Preselect the chosen SSO entry (BigModel / z.ai are
                // different account systems with different page entries).
                final js = _autoClickJsFor(_method);
                if (js != null && url != null) {
                  unawaited(c.evaluateJavascript(source: js));
                }
              },
              // NEVER kick the login flow out to the external browser:
              // cookies set there are unreachable for the harvest, and the
              // official SSO chain may hop across subdomains. Everything
              // https stays in-app; only non-web schemes (mailto:, intent:)
              // are handed to the system.
              shouldOverrideUrlLoading: (controller, action) async {
                final uri = action.request.url;
                if (uri == null) return NavigationActionPolicy.CANCEL;
                if (uri.scheme == 'https' || uri.scheme == 'http') {
                  return NavigationActionPolicy.ALLOW;
                }
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              },
            ),
          ),
        ],
      ),
    );
  }
}
