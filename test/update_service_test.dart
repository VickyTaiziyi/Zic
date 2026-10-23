import 'package:flutter_test/flutter_test.dart';

import 'package:zic/ui/external_link.dart';
import 'package:zic/ui/legal_copy.dart';
import 'package:zic/ui/oss_notices.dart';
import 'package:zic/update/app_channel.dart';
import 'package:zic/update/update_prompt.dart';
import 'package:zic/update/update_service.dart';

void main() {
  group('update change lines', () {
    test('keeps the change and drops the product and platform lines', () {
      const body = '''
Zic 1.0.17，给 ZCode 桌面端用的安卓远程客户端。

发消息后，回复留在当前任务里。

可以预览电脑上写出的文档。

Android 8.0 及以上，仅 arm64-v8a。应用不下载安装包，更新会打开浏览器。
''';
      expect(updateChangeLines(body), [
        '发消息后，回复留在当前任务里。',
        '可以预览电脑上写出的文档。',
      ]);
    });
  });

  group('compareVersions', () {
    test('equal versions', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
    });

    test('newer detection', () {
      expect(compareVersions('1.1.0', '1.0.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    });

    test('older detection', () {
      expect(compareVersions('0.9.0', '1.0.0'), lessThan(0));
      expect(compareVersions('1.0.9', '1.0.10'), lessThan(0));
    });

    test('malformed segments treated as zero', () {
      expect(compareVersions('x.y', '0.0.0'), 0);
      expect(compareVersions('1.x', '1.0.0'), 0);
    });
  });

  group('app channel', () {
    test('default channel is github', () {
      // Not overridden in `flutter test`, so the default applies.
      expect(appChannel, 'github');
    });

    test('store listing urls only exist on store channels', () {
      // On the default github channel there is no store listing.
      expect(storeListingUrl, isNull);
    });

    test('update API is pinned to the official repository', () {
      expect(githubUpdateRepo, officialUpdateRepo);
      expect(githubUpdateCheckEnabled, isTrue);
      expect(officialLatestReleaseApi.scheme, 'https');
      expect(officialLatestReleaseApi.host, 'api.github.com');
      expect(
        officialLatestReleaseApi.path,
        '/repos/VickyTaiziyi/Zic/releases/latest',
      );
    });
  });

  group('official apk url', () {
    const good =
        'https://github.com/VickyTaiziyi/Zic/releases/download/v1.0.15/zic-1.0.15-arm64.apk';

    test('accepts this repository\'s release asset', () {
      expect(officialApkDownloadUrl(good), good);
      expect(updateOpenUrl(apkUrl: good), good);
    });

    test('rejects anything that is not that asset', () {
      const rejected = [
        'http://github.com/VickyTaiziyi/Zic/releases/download/v1/a.apk',
        'https://github.com.evil/VickyTaiziyi/Zic/releases/download/v1/a.apk',
        'https://objects.githubusercontent.com/VickyTaiziyi/Zic/a.apk',
        'https://user@github.com/VickyTaiziyi/Zic/releases/download/v1/a.apk',
        'https://github.com/other/Zic/releases/download/v1/a.apk',
        'https://github.com/VickyTaiziyi/Zic/releases/download/v1/a.exe',
        'https://github.com/VickyTaiziyi/Zic/releases/download/v1/a.apk?x=1',
        'https://github.com/VickyTaiziyi/Zic/releases/download/v1/a.apk#frag',
        'https://github.com/VickyTaiziyi/Zic/releases/latest',
        'https://github.com/zic-app/zic/releases/download/v1/a.apk',
      ];
      for (final url in rejected) {
        expect(officialApkDownloadUrl(url), isNull, reason: url);
        expect(updateOpenUrl(apkUrl: url), officialReleasesPage, reason: url);
      }
      expect(updateOpenUrl(), officialReleasesPage);
    });
  });

  group('startup prompt', () {
    test('asks only for a version newer than the one dismissed', () {
      expect(
        shouldPromptForVersion(
            latest: '1.0.16', current: '1.0.15', skipped: null),
        isTrue,
      );
      expect(
        shouldPromptForVersion(
            latest: '1.0.16', current: '1.0.15', skipped: '1.0.16'),
        isFalse,
      );
      expect(
        shouldPromptForVersion(
            latest: '1.0.17', current: '1.0.15', skipped: '1.0.16'),
        isTrue,
      );
      expect(
        shouldPromptForVersion(
            latest: '1.0.15', current: '1.0.15', skipped: null),
        isFalse,
      );
    });

    test('flutter test does not run the network probe', () {
      expect(updateChecksDisabledForTests(), isTrue);
    });
  });

  group('about facts', () {
    test('rights reserve the name and keep the port license', () {
      final zh = rightsBlocks(false).map((b) => b.body).join('\n');
      expect(zh, contains('保留所有权利'));
      expect(zh, contains('MIT'));
      expect(zh, contains('ZLinker'));
      expect(zh, contains('并不收回这些许可'));
      final en = rightsBlocks(true).map((b) => b.body).join('\n');
      expect(en, contains('reserves all rights'));
      expect(en, contains('does not take those licenses back'));
    });

    test('privacy names only the pinned update endpoint', () {
      final zh = privacyBlocks(false).map((b) => b.body).join('\n');
      expect(zh, contains(
          'https://api.github.com/repos/VickyTaiziyi/Zic/releases/latest'));
      expect(zh, contains('不会发给开发者'));
    });

    test('acknowledgements point at real upstreams', () {
      expect(
        ossNotices.map((n) => n.name),
        isNot(contains('flutter_secure_storage')),
      );
      final zlinker = ossNotices.firstWhere((n) => n.name == 'ZLinker');
      expect(zlinker.license, 'MIT');
      expect(zlinker.url, 'https://github.com/opensymph/ZLinker');
      expect(zlinker.note, contains('ZRemote contributors'));
      for (final notice in ossNotices) {
        expect(isPinnedExternalUrl(notice.url), isTrue, reason: notice.url);
      }
      expect(isPinnedExternalUrl(officialGithubProfile), isTrue);
      expect(isPinnedExternalUrl(officialBlog), isTrue);
      expect(isPinnedExternalUrl('https://github.com/zic-app/zic'), isFalse);
    });
  });
}
