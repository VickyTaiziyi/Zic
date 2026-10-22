import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_kv.dart';
import '../ui/ui_settings.dart';
import 'app_channel.dart';
import 'update_service.dart';

/// Version the user dismissed with Later. A newer tag prompts again.
const skippedUpdateKey = 'zic.update.skipped';

/// `flutter test` sets this. The startup probe must not hit the network
/// from a widget test that pumps the app.
bool updateChecksDisabledForTests() {
  if (const bool.fromEnvironment('FLUTTER_TEST')) return true;
  return Platform.environment['FLUTTER_TEST'] == 'true';
}

/// After the first frame. Failures and a still-private release list stay
/// quiet. Later is remembered per version in the app-private file.
Future<void> promptForUpdateOnStartup(BuildContext context) async {
  if (updateChecksDisabledForTests()) return;
  if (!context.mounted) return;
  await presentGithubUpdate(context, silent: true);
}

/// Settings uses [silent] false so "up to date" and failures are visible.
/// Startup uses true.
Future<void> presentGithubUpdate(BuildContext context,
    {required bool silent}) async {
  if (!githubUpdateCheckEnabled) {
    if (!silent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'update.manualOnly'))));
    }
    return;
  }
  try {
    final info = await PackageInfo.fromPlatform();
    final update = await checkForUpdatesFromGithub(info.version);
    if (!context.mounted) return;
    if (!update.isNewer) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(context, 'update.latest'))));
      }
      return;
    }
    if (silent) {
      final skipped = await AppKv.instance.getString(skippedUpdateKey);
      if (!shouldPromptForVersion(
        latest: update.latestVersion,
        current: info.version,
        skipped: skipped,
      )) {
        return;
      }
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(trP(context, 'update.newVersion', [update.latestVersion])),
        content: (update.body ?? '').trim().isEmpty
            ? Text(tr(context, 'update.availableBody'))
            : SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: SelectableText(update.body!,
                      style: const TextStyle(fontSize: 12, height: 1.5)),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await AppKv.instance
                    .setString(skippedUpdateKey, update.latestVersion);
              } catch (_) {
                // Dismiss still closes. The next launch may ask again.
              }
            },
            child: Text(tr(context, 'update.later')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openUpdateInBrowser(update.apkUrl);
            },
            child: Text(tr(context, 'update.download')),
          ),
        ],
      ),
    );
  } on UpdateCheckException catch (e) {
    if (silent || !context.mounted) return;
    final key =
        e.statusCode == 404 ? 'update.unavailable' : 'update.failed';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, key))));
  } catch (_) {
    if (silent || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'update.failed'))));
  }
}

/// Opens the allowlisted asset URL, or the pinned releases page.
Future<bool> openUpdateInBrowser(String? apkUrl) async {
  final target = updateOpenUrl(apkUrl: apkUrl);
  if (officialApkDownloadUrl(target) == null &&
      target != officialReleasesPage) {
    return false;
  }
  try {
    return await launchUrl(Uri.parse(target),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
