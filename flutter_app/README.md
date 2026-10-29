# 译包 LangPack · Flutter

**[公开在线体验：译包 LangPack · 多语言工作台](https://langpack-studio-oct29.neonkrill256.chatgpt.site)**

一套 Dart 代码实现 iOS、Android、桌面（Windows / macOS / Linux）与 Web 的多语言翻译工作台。默认应用标识为 `com.cherryice.langpack`。

完整流程：项目首页 → 文本输入或文档导入 → 段落预览与 key → 语言多选 → 真实翻译 → 校对 → JSON / ZIP 导出。

## 开发环境

使用 Flutter **3.35.7** / Dart **3.9.2**，具体依赖记录在 `pubspec.lock`。先安装对应平台工具链，再在本目录运行：

```sh
flutter --version
flutter doctor -v
flutter pub get
flutter devices
```

iOS / macOS 需要 macOS、Xcode 和 CocoaPods；Android 需要 Android SDK、JDK 及已接受的 SDK 许可。Windows 需要 Windows 和 Visual Studio 桌面 C++ 工具链；Linux 需要 Linux 及 GTK 开发依赖。生成平台工程不代表已经构建或运行验证。

## Web 与备用翻译服务

原生 App（iOS / Android / Windows / macOS / Linux）默认连接公开在线项目的 `/api/translation/status` 和 `/api/translation/backup`，由在线服务器调用 ZTAITrans。普通使用者无需填写密钥或自行部署代理；密钥始终保存在服务器。首次运行及旧版保存的空地址会自动使用默认在线服务，显式自定义地址仍保留。

网站设为公开不会修改已安装的旧二进制，请安装包含默认在线服务改动的新版本。旧版 App 也可先在“备用翻译服务器”中填写 `https://langpack-studio-oct29.neonkrill256.chatgpt.site`，填的是服务地址，无需填写 API 密钥。

Flutter Web 使用自身部署站点的同源代理，避免跨域访问限制；它不会默认从其他域名跨域调用上述公开站点。在线站点的普通用户无需配置密钥；自行本地或独立部署 Flutter Web 时，由部署者配置自己的服务端密钥。

在 `flutter_app/` 构建：

```sh
flutter build web --release
```

再在仓库根目录启动：

```sh
node scripts/flutter-server.mjs
```

打开 [http://127.0.0.1:4180](http://127.0.0.1:4180)。默认监听 `127.0.0.1:4180`，可通过服务端环境变量 `HOST`、`PORT` 调整。服务同时提供 Flutter Web 静态文件与 `/api/translation/status`、`/api/translation/backup`，网页与代理同源，无需开放跨域访问。

MyMemory 主翻译无需密钥。对于自行部署的 Node 服务，启用 ZTAITrans 备用翻译时，由部署环境向 **Node 服务进程**注入 `TRANSLATION_API_KEY`，再启动服务。密钥不进入 Flutter 设置、`--dart-define`、源码、Web 文件或客户端安装包。自建服务未配置备用密钥时，MyMemory 仍可独立使用；额度耗尽后会提示该服务器备用未配置，并保留成功结果。

正式部署时，将 Web 文件和现有 `worker/handler.js` 代理部署到同一 HTTPS 域名。Node 服务放在 HTTPS 反向代理后时，为服务端配置 `PUBLIC_ORIGIN=https://你的服务域名`，让代理校验使用外部固定域名；默认仍使用本地 HTTP 地址，不信任任意转发请求头。HTTPS、进程管理和入口访问控制需按部署环境配置，脚本本身不提供账户系统。当前代码未自动部署你的自建服务。上述公开 Sites 站点已可供原生客户端使用其在线代理。

仅调试界面可以运行 `flutter run -d chrome`；该开发服务器未挂载备用代理，完整流程使用上述同源服务。

## 移动端与桌面端启动

标准版本的原生客户端直接运行即可使用默认在线代理，例如：

```sh
flutter run -d macos
```

需要使用自己的服务器时，可在应用设置中填写自定义地址，或通过 `API_BASE_URL` 设置定制构建的首次运行默认地址。应用内显式保存的地址优先；清空自定义地址或点击“恢复内置在线服务”后，一律使用公开在线代理。地址使用 HTTPS **根域名**，不含接口路径或密钥：

```sh
flutter run -d macos --dart-define=API_BASE_URL=https://translate.example.com
```

请替换示例域名。通过 `flutter devices` 获取 iOS / Android 设备标识，再替换 `-d` 参数。Windows、Linux 分别在对应系统运行 `flutter run -d windows`、`flutter run -d linux`。

本机调试先启动 Node 服务，macOS / iOS 模拟器使用本机回环地址：

```sh
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:4180
flutter run -d "从 flutter devices 复制的 iOS 模拟器标识" --dart-define=API_BASE_URL=http://127.0.0.1:4180
```

Android 标准模拟器通过 `10.0.2.2` 访问宿主机：

```sh
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:4180
```

这些 HTTP 地址仅用于 Debug 调试，发布使用 HTTPS。物理手机的 `127.0.0.1` 指向手机自身。已保存的应用设置优先于构建时默认地址，切换服务时请同时检查设置。

## 功能与数据边界

- 项目创建、搜索、文案选择、key / 原文编辑，手机底部导航与桌面侧栏。
- 文本按行 / 空行拆分，TXT / Markdown / DOCX 本地解析，段落预览、勾选、编辑、合并与按句拆分。
- 英语、日语、韩语、法语、德语、西班牙语、繁体中文多选。
- 常见中文语义 key、自定义内容稳定备用 key 与手动修改；未接入语义命名模型。
- MyMemory 真实翻译、480 UTF-8 字节分段、Unicode / 换行 / 占位符保护、限速与临时失败重试。
- 仅主服务额度耗尽切换整段 ZTAITrans，冷却期后续条目继续用备用；保留实际来源，不把错误提示写成译文。
- 暂停 / 继续、失败项重试、逐条重译、人工校对确认；批量保护人工结果，拒绝迟到请求覆盖新编辑。
- 正式导出校验 key、完整性和占位符；各语言独立 JSON、ZIP、带报告的草稿 ZIP、最近 20 次导出快照重下载。

文档最多 **10 MB / 1000 个内容块**，DOCX 正文解压最多 **20 MB**。不支持 PDF、扫描件、旧版 DOC、加密文档或复杂版式还原；导出仅包含文本资源。文档文件在本地解析；开始翻译后，所选原文会发送给对应服务。

MyMemory 有免费额度和限流。公共备用服务共享在线站点现有授权预算，ZTAITrans 未承诺免费或永久免费。备用授权、配置或预算不可用时会停止任务并保留成功结果。

项目、校对、任务摘要、导出快照与设置保存在当前设备或浏览器，无账户、云同步或跨设备共享。Flutter 各端数据与旧版 `web/` 原型分别保存；旧版数据不自动迁移，新版需重新导入原文。删除应用 / 浏览器站点数据会移除记录，请及时导出需要保留的语言包。

应用进入后台、窗口隐藏或关闭网页时会暂停任务并保存成功结果，恢复后可处理未完成项；不保证后台持续翻译。重启后未完整完成的长段落可能重新请求部分分段。

## 检查与构建

默认检查不调用真实翻译服务：

```sh
flutter analyze
flutter test
```

无需填写地址或密钥的原生默认服务验收：

```sh
flutter test test/live_smoke_test.dart --dart-define=RUN_PUBLIC_PROXY_TEST=true
```

该项模拟 MyMemory 额度耗尽，实际调用默认公开 ZTAITrans 代理，验证空地址也能完成真实翻译。

全文档真实验收也可通过公开在线代理运行，无需客户端密钥；自建代理由部署者配置服务端密钥。下面以公开服务为例，显式开启：

```sh
flutter test test/live_smoke_test.dart --dart-define=RUN_LIVE_TRANSLATION=true --dart-define=API_BASE_URL=https://langpack-studio-oct29.neonkrill256.chatgpt.site
```

`RUN_LIVE_TRANSLATION` 和 `RUN_PUBLIC_PROXY_TEST` 默认关闭，真实测试会发送样例中文并消耗额度。测试区分实际主服务请求与“模拟主服务额度耗尽 → 真实备用翻译”的文档流程；产物写入仓库 `outputs/flutter-live/`，可通过 `LIVE_OUTPUT_DIR` 改为其他项目内证据目录。真实后端、Mock 合约测试、界面运行和构建证据分别记录。

在对应宿主机与工具链上执行：

| 平台 | 构建命令 | 输出目录 |
| --- | --- | --- |
| Web | `flutter build web --release` | `build/web/` |
| Android 调试 | `flutter build apk --debug` | `build/app/outputs/flutter-apk/` |
| iOS 模拟器 | `flutter build ios --simulator --debug --no-codesign` | `build/ios/iphonesimulator/` |
| macOS 调试 | `flutter build macos --debug` | `build/macos/Build/Products/Debug/` |
| Windows | `flutter build windows --release` | `build/windows/` |
| Linux | `flutter build linux --release` | `build/linux/` |

Android 已移除模板的 Release 使用 Debug 签名配置，商店分发前需配置自有 keystore。iOS / macOS 发布需要自有证书、团队与签名；当前工程未完成商店发布。密钥和签名材料不纳入 Git。

`.github/workflows/flutter.yml` 提供固定 Flutter 3.35.7 的静态检查、测试及各平台构建。CI 不调用真实翻译、不配置生产密钥、不发布应用。[此前六平台构建记录](https://github.com/CherryIce/langpack-prototype/actions/runs/40858371621) 已成功；后续改动需查看对应提交的新检查结果。本机实际验证结果以本轮交付说明和 `outputs/` 证据为准。

## 代码结构

- `lib/models.dart`：项目、文案、译文、任务摘要和导出快照。
- `lib/controller.dart`：状态、持久化、任务、校对和导出流程。
- `lib/services/translation_service.dart`：真实翻译、分段、缓存、限速与取消。
- `lib/services/document_service.dart`：文档、唯一 key 与占位符。
- `lib/services/export_service.dart`：校验、JSON / ZIP 与平台文件保存。
- `lib/ui/`：自适应界面。
- `../worker/`、`../scripts/flutter-server.mjs`：服务端备用代理与同源开发服务。

参考 [Flutter 平台集成文档](https://docs.flutter.dev/platform-integration) 和 [flutter-action 项目文档](https://github.com/subosito/flutter-action)。
