/// In-app privacy policy and the developer rights statement.
/// Kept in the binary so both pages work while the repository is private.
class LegalBlock {
  final String? heading;
  final String body;
  const LegalBlock(this.body, {this.heading});
}

List<LegalBlock> privacyBlocks(bool en) {
  if (en) {
    return const [
      LegalBlock(
        'This page says what Zic stores on the phone and which servers it talks to.',
      ),
      LegalBlock(
        'The ZCode login and pairing links are written only to a file in the app-private directory. Cloud backup is off. Uninstalling the app deletes that file with it.',
        heading: 'On this phone',
      ),
      LegalBlock(
        'Traffic uses HTTPS or WSS only. The sign-in page may open zcode.z.ai, z.ai, zhipuaish.com, open.bigmodel.cn, and their real subdomains. After pairing, the relay traffic goes only to the ZCode host in that link.',
        heading: 'Where it connects',
      ),
      LegalBlock(
        'Update checks request only https://api.github.com/repos/VickyTaiziyi/Zic/releases/latest. Zic does not download or install the package. Download opens the system browser on this repository\'s GitHub releases page, or on a download address that matches that repository.',
        heading: 'Updates',
      ),
      LegalBlock(
        'The camera is used only while you scan a pairing QR code.',
        heading: 'Camera',
      ),
      LegalBlock(
        'Device counts, open counts, and last-used times stay on the phone. They are not sent to the developer. There is no developer telemetry, no advertising SDK, and no Zic account.',
        heading: 'Usage statistics',
      ),
    ];
  }
  return const [
    LegalBlock('这一页说明 Zic 在手机上保存什么，以及会连接哪些服务器。'),
    LegalBlock(
      'ZCode 登录和配对链接只写在应用私有目录的文件里。系统云备份已关闭。卸载应用时，这个文件会一起删除。',
      heading: '留在本机的内容',
    ),
    LegalBlock(
      '连接只使用 HTTPS 或 WSS。登录页只打开 zcode.z.ai、z.ai、zhipuaish.com、open.bigmodel.cn，以及它们真正的子域名。配对之后，中继流量只发往那条链接里的 ZCode 主机。',
      heading: '会连接哪里',
    ),
    LegalBlock(
      '检查更新只请求 https://api.github.com/repos/VickyTaiziyi/Zic/releases/latest。Zic 自己不下载、也不安装安装包。点下载会交给系统浏览器，打开本仓库的 GitHub 发布页，或与该仓库匹配的下载地址。',
      heading: '检查更新',
    ),
    LegalBlock('相机只在你扫描配对二维码时使用。', heading: '相机'),
    LegalBlock(
      '设备数、打开次数和最近使用时间只留在手机上，不会发给开发者。没有开发者遥测，没有广告组件，也没有 Zic 自己的账号。',
      heading: '使用统计',
    ),
  ];
}

List<LegalBlock> rightsBlocks(bool en) {
  if (en) {
    return const [
      LegalBlock(
        'The developer reserves all rights in the Zic name, the Zic mark, and the distribution of this install package.',
      ),
      LegalBlock(
        'The source that corresponds to this package is still offered under the MIT license at the repository root, Copyright (c) 2026 Zic contributors. This reservation does not cancel that license.',
        heading: 'Source license',
      ),
      LegalBlock(
        'The protocol stack is ported from ZLinker under the MIT license, Copyright (c) 2026 ZRemote contributors. Third-party components keep their own licenses. Reserving the name, the mark, and this distribution does not take those licenses back.',
        heading: 'Ported code and dependencies',
      ),
      LegalBlock(
        'Zic is an unofficial client and is not affiliated with Zhipu AI or ZCode. Use of the ZCode service is also subject to that service\'s own terms.',
        heading: 'No affiliation',
      ),
      LegalBlock(
        'This build supports Android 8.0 (API 26) and newer. Notification channels exist from Android 8. Android 13 and newer ask for notification permission.',
        heading: 'Android versions',
      ),
    ];
  }
  return const [
    LegalBlock('开发者对 Zic 这一名称、标识，以及本安装包的发布，保留所有权利。'),
    LegalBlock(
      '与本安装包对应的源代码仍按仓库根目录的 MIT 许可证提供，著作权人为 Copyright (c) 2026 Zic contributors。这份保留权利的声明不取消该许可证。',
      heading: '源代码许可',
    ),
    LegalBlock(
      '协议实现移植自 ZLinker，许可证为 MIT，Copyright (c) 2026 ZRemote contributors。第三方组件继续适用各自的许可证。对名称、标识和本安装包发行保留所有权利，并不收回这些许可。',
      heading: '移植代码与依赖',
    ),
    LegalBlock(
      'Zic 是非官方客户端，与 Zhipu AI 及 ZCode 没有关联。使用 ZCode 服务时，还要遵守该服务自己的条款。',
      heading: '无关联声明',
    ),
    LegalBlock(
      '本构建支持 Android 8.0（API 26）及以上。Android 8 起可以使用通知渠道。Android 13 及以上会在系统里询问通知权限。',
      heading: '安卓版本',
    ),
  ];
}
