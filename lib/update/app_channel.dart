/// Distribution channel, fixed at build time:
/// `flutter build apk --dart-define=APP_CHANNEL=github|play|appstore`
///
/// - github (default): check this repository's GitHub releases. The app
///   never downloads or installs an APK; the browser opens a pinned URL.
/// - play / appstore: "check for updates" opens the store listing.
const appChannel = String.fromEnvironment('APP_CHANNEL',
    defaultValue: 'github');

/// The only GitHub namespace an update check may query.
const officialUpdateRepo = 'VickyTaiziyi/Zic';

/// `--dart-define=GITHUB_UPDATE_REPO=` turns the check off for a local
/// experiment. Any other value, including a different owner/name, is
/// ignored: a rebuild must not retarget the check at another repository.
const _definedUpdateRepo = String.fromEnvironment('GITHUB_UPDATE_REPO',
    defaultValue: officialUpdateRepo);

/// Empty when the check is compiled off. Otherwise always
/// [officialUpdateRepo], never the raw dart-define.
String get githubUpdateRepo =>
    _definedUpdateRepo.isEmpty ? '' : officialUpdateRepo;

const officialGithubProfile = 'https://github.com/VickyTaiziyi';
const officialGithubRepo = 'https://github.com/VickyTaiziyi/Zic';
const officialReleasesPage = 'https://github.com/VickyTaiziyi/Zic/releases';
const officialBlog = 'https://vicyi.com/';

/// Latest-release API. Built only from [officialUpdateRepo].
final officialLatestReleaseApi = Uri.parse(
    'https://api.github.com/repos/$officialUpdateRepo/releases/latest');

const _playPackageId = 'dev.zic.remote';

/// Filled when the App Store listing exists (numeric id). Until then the
/// appstore channel shows a hint instead of a broken link.
const appStoreId = '';

Uri? get storeListingUrl {
  switch (appChannel) {
    case 'play':
      return Uri.parse('market://details?id=$_playPackageId');
    case 'appstore':
      return appStoreId.isEmpty
          ? null
          : Uri.parse('itms-apps://apps.apple.com/app/id$appStoreId');
    default:
      return null;
  }
}
