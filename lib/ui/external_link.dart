import 'package:url_launcher/url_launcher.dart';

import '../update/app_channel.dart';

/// Exact https URLs the about page and acknowledgements may open.
/// Anything else is refused, including the old placeholder repository.
const pinnedExternalUrls = <String>{
  officialGithubProfile,
  officialGithubRepo,
  officialReleasesPage,
  officialBlog,
  'https://github.com/opensymph/ZLinker',
  'https://github.com/flutter/flutter',
  'https://pub.dev/packages/app_links',
  'https://pub.dev/packages/clock',
  'https://pub.dev/packages/crypto',
  'https://pub.dev/packages/cupertino_icons',
  'https://pub.dev/packages/file_picker',
  'https://pub.dev/packages/flutter_inappwebview',
  'https://pub.dev/packages/flutter_local_notifications',
  'https://pub.dev/packages/flutter_markdown',
  'https://pub.dev/packages/highlight',
  'https://pub.dev/packages/home_widget',
  'https://pub.dev/packages/http',
  'https://pub.dev/packages/image',
  'https://pub.dev/packages/image_picker',
  'https://pub.dev/packages/markdown',
  'https://pub.dev/packages/mobile_scanner',
  'https://pub.dev/packages/package_info_plus',
  'https://pub.dev/packages/shared_preferences',
  'https://pub.dev/packages/url_launcher',
  'https://pub.dev/packages/web_socket_channel',
  'https://pub.dev/packages/zxing2',
};

bool isPinnedExternalUrl(String url) => pinnedExternalUrls.contains(url);

/// Opens [url] only when it is in [pinnedExternalUrls]. Returns false
/// when the URL is refused or the system has no handler.
Future<bool> openPinnedUrl(String url) async {
  if (!isPinnedExternalUrl(url)) return false;
  try {
    return await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
