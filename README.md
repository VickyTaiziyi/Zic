<div align="center">

# Zic

Unofficial Android client for the ZCode desktop remote.

<a href="./README.md"><img alt="English" src="https://img.shields.io/badge/English-2F6FED?style=for-the-badge"></a>
<a href="./README.zh-CN.md"><img alt="中文" src="https://img.shields.io/badge/%E4%B8%AD%E6%96%87-5F6368?style=for-the-badge"></a>

</div>

[Releases](https://github.com/VickyTaiziyi/Zic/releases) · [Security](SECURITY.md) · [Notices](NOTICES.md) · [License](LICENSE)

## What it is

Zic connects an Android phone to a paired ZCode desktop. It is not affiliated with Zhipu AI or ZCode.

## Why it exists

I opened [Pull Request #8](https://github.com/opensymph/ZLinker/pull/8) on [ZLinker](https://github.com/opensymph/ZLinker) to fix unreadable text in light mode. After ZCode updated, the session on my own phone stayed offline. Zic is a client written for that case.

The relay frames, pairing proof, tasks, and conversations are ported from ZLinker (MIT, Copyright (c) 2026 ZRemote contributors). After desktop v4 pairing links stopped carrying `hash`, the HMAC path no longer connected. The sign-in path is written in Zic: read `zcodejwttoken` from `localStorage` on the official page, `POST /api/v1/remote/token` on that host with `{"role":"terminal"}`, then connect with the returned token at `wss://<host>/api/v1/remote/ws2`. Links that still carry `hash` keep the HMAC proof.

## What is in the client

| | |
|---|---|
| Devices | List, online status, home-screen widget |
| Session | Tasks, conversations, workflows |
| Schedules | Automations and off-peak runs |
| On the phone | Usage counts, privacy notes, the rights statement, third-party notices |

Usage counts stay on the phone.

## Requirements

| | |
|---|---|
| Android | 8.0 (API 26) or newer |
| Package | `arm64-v8a` only |
| Updates | The app does not download or install a package. Download opens the system browser |

## Install

Install the APK from [Releases](https://github.com/VickyTaiziyi/Zic/releases), or build it with the steps below. A pairing link is a device credential. Install a package you have checked.

> [!NOTE]
> This package is signed with the debug key on this computer. A later build signed with that same key can replace it. After a switch to another release key, the installed package has to be uninstalled first.

1. In desktop ZCode, open the phone icon and scan the QR, or paste the link into Zic.
2. A v4 link needs one sign-in on the official page, from Settings.

## Where data sits, and where traffic goes

The login and pairing links are written only to a file in the app-private directory. Cloud backup is off. Uninstalling the app deletes that file. The camera is used only while scanning a pairing QR code.

Traffic goes to the ZCode host in the pairing link (HTTPS or WSS), to the allowed sign-in hosts (`zcode.z.ai`, `z.ai`, `zhipuaish.com`, `open.bigmodel.cn`, and their real subdomains), and to `https://api.github.com/repos/VickyTaiziyi/Zic/releases/latest`. There is no developer telemetry and no Zic account.

## Build

Flutter SDK with Dart `>=3.4`, plus the Android SDK.

```bash
git clone https://github.com/VickyTaiziyi/Zic.git
cd Zic
flutter pub get
dart run tool/icon_gen.dart && dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

A local build checks `VickyTaiziyi/Zic` for a newer release. `--dart-define=GITHUB_UPDATE_REPO=` turns that check off. Another repository name is ignored.

## Contributing

If this client is useful to you, a star on the repository is welcome.

Issues and pull requests are welcome. Copy, notes, and small fixes can go straight into a pull request. For changes to the relay or on-device storage, please open an issue first. Run `flutter analyze` and `flutter test` before sending it.

Report a vulnerability through Security Advisories on this repository. Please do not open a public issue for that, and do not paste a full pairing link.

## Rights and license

The developer reserves all rights in the Zic name, the Zic mark, and the distribution of this install package. Commercial use of that name, that mark, or this package requires the developer's permission.

The source that corresponds to this package is still offered under the MIT license at the repository root, Copyright (c) 2026 Zic contributors. The MIT license allows use of that source. This reservation does not cancel that license.

The protocol stack is ported from ZLinker under the MIT license, Copyright (c) 2026 ZRemote contributors. Third-party components keep their own licenses. Reserving the name, the mark, and this distribution does not take those licenses back.

Use of the ZCode service is also subject to that service's own terms.

## Maintainer

[VickyTaiziyi](https://github.com/VickyTaiziyi) · [vicyi.com](https://vicyi.com/)

Third-party notices are in [NOTICES.md](NOTICES.md).
