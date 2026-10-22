import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_channel.dart';

/// Result of an update check against the pinned GitHub latest release.
class UpdateInfo {
  final String latestVersion;
  final String releaseUrl;
  final String? body;
  final String? apkUrl;
  final bool isNewer;

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    this.body,
    this.apkUrl,
    required this.isNewer,
  });
}

/// True when the in-app GitHub update check is usable: the channel is
/// `github` and the compiled-in namespace was not blanked out.
bool get githubUpdateCheckEnabled =>
    appChannel == 'github' && githubUpdateRepo == officialUpdateRepo;

class UpdateCheckException implements Exception {
  final String message;
  final int? statusCode;
  const UpdateCheckException(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null
      ? 'UpdateCheckException: $message'
      : 'UpdateCheckException: $message ($statusCode)';
}

/// Queries [officialLatestReleaseApi] and compares the tag with
/// [currentVersion]. The request URL is the constant above; the JSON
/// `html_url` is never followed. Store builds update through their store.
Future<UpdateInfo> checkForUpdatesFromGithub(String currentVersion) async {
  if (!githubUpdateCheckEnabled) {
    throw const UpdateCheckException('update channel not configured');
  }
  final res = await http
      .get(officialLatestReleaseApi)
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    // Status only. A 404 body from a private repo must not reach the UI.
    throw UpdateCheckException('GitHub API ${res.statusCode}',
        statusCode: res.statusCode);
  }
  final data = jsonDecode(utf8.decode(res.bodyBytes));
  if (data is! Map) {
    throw const UpdateCheckException('invalid GitHub response');
  }
  final tag = '${data['tag_name'] ?? ''}';
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  final rawBody = data['body'];
  String? body;
  if (rawBody is String && rawBody.trim().isNotEmpty) {
    body = rawBody.length > 4000 ? rawBody.substring(0, 4000) : rawBody;
  }
  final assets = data['assets'];
  String? apkUrl;
  if (assets is List) {
    for (final a in assets.whereType<Map>()) {
      if (!'${a['name'] ?? ''}'.toLowerCase().endsWith('.apk')) continue;
      final pinned = officialApkDownloadUrl('${a['browser_download_url'] ?? ''}');
      if (pinned != null) {
        apkUrl = pinned;
        break;
      }
    }
  }
  final latest = version.isEmpty ? tag : version;
  return UpdateInfo(
    latestVersion: latest,
    releaseUrl: officialReleasesPage,
    body: body,
    apkUrl: apkUrl,
    isNewer: latest.isNotEmpty && compareVersions(latest, currentVersion) > 0,
  );
}

/// Browser target for an update. An asset URL is used only when it is an
/// https download on github.com for this repository; every other value
/// falls back to the releases page. The app does not fetch the APK.
String updateOpenUrl({String? apkUrl}) =>
    officialApkDownloadUrl(apkUrl) ?? officialReleasesPage;

/// `https://github.com/VickyTaiziyi/Zic/releases/download/<tag>/<file>.apk`
/// with no userinfo, query, or fragment. Anything else returns null.
String? officialApkDownloadUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme != 'https' || uri.host != 'github.com') return null;
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    return null;
  }
  if (uri.port != 443 && uri.hasPort) return null;
  final segs = uri.pathSegments;
  if (segs.length != 6) return null;
  if (segs[0] != 'VickyTaiziyi' || segs[1] != 'Zic') return null;
  if (segs[2] != 'releases' || segs[3] != 'download') return null;
  if (!_safeSegment(segs[4]) || !_safeApkFile(segs[5])) return null;
  return uri.toString();
}

bool _safeSegment(String value) {
  if (value.isEmpty || value == '.' || value == '..') return false;
  return RegExp(r'^[A-Za-z0-9._+-]+$').hasMatch(value);
}

bool _safeApkFile(String value) =>
    _safeSegment(value) && value.toLowerCase().endsWith('.apk');

/// Whether a startup prompt should show. Manual checks ignore [skipped]
/// so the user can open the dialog again. A newer tag than the one they
/// dismissed prompts again.
bool shouldPromptForVersion({
  required String latest,
  required String current,
  String? skipped,
}) {
  if (latest.isEmpty || compareVersions(latest, current) <= 0) return false;
  if (skipped != null &&
      skipped.isNotEmpty &&
      compareVersions(latest, skipped) <= 0) {
    return false;
  }
  return true;
}

/// Semantic version compare on the first three numeric segments
/// (`major.minor.patch`). Handles `1.2` vs `1.2.0` as equal.
int compareVersions(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final x = pa.length > i ? pa[i] : 0;
    final y = pb.length > i ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
