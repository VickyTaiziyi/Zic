<div align="center">

# Zic

给 ZCode 桌面端用的安卓远程客户端，非官方。

<a href="./README.md"><img alt="English" src="https://img.shields.io/badge/English-5F6368?style=for-the-badge"></a>
<a href="./README.zh-CN.md"><img alt="中文" src="https://img.shields.io/badge/%E4%B8%AD%E6%96%87-2F6FED?style=for-the-badge"></a>

</div>

[发布](https://github.com/VickyTaiziyi/Zic/releases) · [安全说明](SECURITY.md) · [致谢](NOTICES.md) · [许可证](LICENSE)

## 这是什么

Zic 从安卓手机连接一台已经配对的桌面端 ZCode。它与智谱 AI、ZCode 没有关联。

## 缘起

我给 [ZLinker](https://github.com/opensymph/ZLinker) 提过 [Pull Request #8](https://github.com/opensymph/ZLinker/pull/8)，修的是亮色模式下几处字看不清。之后 ZCode 更新了，我在自己的手机上看到会话一直显示离线。Zic 是为此写的客户端。

中继帧、配对证明、任务和对话移植自 ZLinker（MIT，Copyright (c) 2026 ZRemote contributors）。桌面端的 v4 配对链接不再带 `hash` 之后，原来的 HMAC 路径接不上。账号登录这一段是在 Zic 里写的：在官方页面读取 `localStorage` 里的 `zcodejwttoken`，向该主机 `POST /api/v1/remote/token`，正文为 `{"role":"terminal"}`，再用返回的令牌连接 `wss://<主机>/api/v1/remote/ws2`。仍带 `hash` 的旧链接继续用 HMAC 证明。

## 里面有什么

| | |
|---|---|
| 设备 | 列表、在线状态、主屏幕小组件 |
| 会话 | 任务、对话、工作流 |
| 调度 | 自动化、错峰 |
| 本机 | 使用统计、隐私说明、权利声明、开源致谢 |

使用统计只记在这台手机上。

## 环境

| | |
|---|---|
| Android | 8.0（API 26）及以上 |
| 安装包 | 仅 `arm64-v8a` |
| 更新 | 应用不下载、也不安装更新包。下载会打开系统浏览器 |

## 安装

从[发布页](https://github.com/VickyTaiziyi/Zic/releases)安装 APK，或按下面的步骤自己编译。配对链接是设备凭据，只安装你核对过的发布包。

> [!NOTE]
> 当前安装包用这台电脑上的调试钥匙签名。同一把钥匙打出的新版本可以直接覆盖安装。换一把正式钥匙之后，已安装的版本需要先卸载。

1. 在 ZCode 桌面端打开手机图标，扫描二维码，或把链接粘进 Zic。
2. v4 链接需要在设置里登录一次官方页面。

## 数据放在哪，流量去哪

登录和配对链接只写在应用私有目录的文件里。系统云备份是关的。卸载应用时，这个文件会一起删掉。相机只在扫描配对二维码时使用。

流量只发往三处：配对链接里的那台 ZCode 主机（HTTPS / WSS）、登录允许的主机（`zcode.z.ai`、`z.ai`、`zhipuaish.com`、`open.bigmodel.cn` 以及它们真正的子域名），以及 `https://api.github.com/repos/VickyTaiziyi/Zic/releases/latest`。没有开发者遥测，也没有 Zic 自己的账号。

## 从源码构建

需要 Flutter SDK（Dart `>=3.4`）和 Android SDK。

```bash
git clone https://github.com/VickyTaiziyi/Zic.git
cd Zic
flutter pub get
dart run tool/icon_gen.dart && dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

自己编译时，应用默认只检查 `VickyTaiziyi/Zic` 的新版本。编译参数 `--dart-define=GITHUB_UPDATE_REPO=` 可以关掉这个检查。填别的仓库名也不会生效。

## 参与

这个客户端如果对你有用，可以给仓库点一个 Star。

问题和拉取请求都欢迎。改文案、补说明、修小问题，可以直接提拉取请求。协议和本机存储相关的改动，请先开一个 Issue。提交前跑一遍 `flutter analyze` 和 `flutter test`。

安全问题请走仓库的 Security Advisories，不要开公开 issue，也不要贴出完整配对链接。

## 权利与许可

开发者对 Zic 这一名称、标识，以及本安装包的发布，保留所有权利。未经开发者许可，不得将这一名称、标识或本安装包用于商业用途。

与本安装包对应的源代码仍按仓库根目录的 MIT 许可证提供，著作权人为 Copyright (c) 2026 Zic contributors。MIT 许可证允许他人使用这些源代码。这份保留权利的声明不取消该许可证。

协议实现移植自 ZLinker，许可证为 MIT，Copyright (c) 2026 ZRemote contributors。第三方组件继续适用各自的许可证。对名称、标识和本安装包发行保留所有权利，并不收回这些许可。

使用 ZCode 服务时，还要遵守该服务自己的条款。

## 维护者

[VickyTaiziyi](https://github.com/VickyTaiziyi) · [vicyi.com](https://vicyi.com/)

第三方名单见 [NOTICES.md](NOTICES.md)。
