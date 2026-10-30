# 译包 LangPack · Flutter

**[公开在线体验：译包 LangPack · 多语言工作台](https://langpack-standalone.406859116.workers.dev/)**（Cloudflare Workers 独立部署）

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

## 多平台翻译与代理

默认只启用 **MyMemory**，可匿名使用，联系邮箱及私有词库 API key 均为选填；私有词库 key 不代表免费额度增加。设置中可选择主平台、启用其他平台并调整备用顺序。只在额度耗尽或语言不支持时按顺序回退；鉴权、配置和普通请求错误会停止，普通限流只在原平台重试。各平台冷却独立，到期后的下一条待翻译内容重新优先尝试该平台。

支持的代理平台与凭据：

| 平台 | 用户配置 | 语言范围 |
| --- | --- | --- |
| ZTAITrans | API key，可选 tenantId；或开发者访问码，二选一 | 34 种目标语言 |
| DeepL | API key；按控制台选择免费接口 api-free 或标准接口 api | 不支持 fil、si，支持其余 32 种 |
| Azure | API key，可选资源区域 | 34 种目标语言 |
| Google | API key，Basic / v2 | 不支持 nb，支持其余 33 种 |

ZTAITrans 不再提供匿名共享授权；开发者访问码通过服务端验证后，才可使用部署者的授权。状态检测只读取 `/api/translation/status`，开发者模式使用 `X-LangPack-Developer-Token` 请求头，不消耗翻译额度。各平台翻译通过统一 `/api/translation/provider` 转发，密钥不写入客户端 URL、项目、任务或导出；MyMemory 配置私有词库 key 后也使用固定代理，仅匿名或邮箱模式直接访问其公开 GET 接口。

凭据默认只保留在本次应用会话。只有在配置窗口明确勾选“在本机保存凭据”才写入独立本地存储；该存储不提供额外加密，共享设备请保持关闭。取消本机保存会移除此前保存的副本，“清除”同时删除会话及本机副本。平台顺序和备用开关可以独立持久化，修改邮箱或导出设置不会丢失它们；邮箱身份变更仅清除 MyMemory 的冷却和请求缓存，不影响其他平台。旧版项目的成功译文继续复用，不会因新增平台强制重译。

原生 App 默认连接 `https://langpack-standalone.406859116.workers.dev`；空地址使用该内置代理，显式自定义地址保留。Flutter Web 使用部署站点的同源代理。新增平台功能需部署对应服务端并更新客户端，源码变更不代表线上或已安装版本已更新。

在 `flutter_app/` 构建：

```sh
flutter build web --release
```

再在仓库根目录启动：

```sh
node scripts/flutter-server.mjs
```

打开 [http://127.0.0.1:4180](http://127.0.0.1:4180)。默认监听 `127.0.0.1:4180`，可通过服务端环境变量 `HOST`、`PORT` 调整。服务同时提供 Flutter Web 静态文件与 `/api/translation/status`、`/api/translation/provider`，网页与代理同源，无需开放跨域访问。

自备密钥在应用的平台配置中填写，由代理转发到固定官方接口；不要放入源码、`--dart-define`、安装包或命令行参数。开发者模式的环境密钥和访问码仅由部署方配置，客户端只输入访问码。未配置后续平台时，MyMemory 额度耗尽会停止并保留成功结果。

正式部署时，将 Web 文件和现有 `worker/handler.js` 代理部署到同一 HTTPS 域名。Node 服务放在 HTTPS 反向代理后时，为服务端配置 `PUBLIC_ORIGIN=https://你的服务域名`，让代理校验使用外部固定域名；默认仍使用本地 HTTP 地址，不信任任意转发请求头。HTTPS、进程管理和入口访问控制需按部署环境配置，脚本本身不提供账户系统。当前代码未自动部署你的自建服务。上述独立在线服务可供原生客户端使用其代理。

仅调试界面可以运行 `flutter run -d chrome`；该开发服务器未挂载备用代理，完整流程使用上述同源服务。

## 移动端与桌面端启动

标准版本的原生客户端直接运行即可使用默认在线代理，例如：

```sh
flutter run -d macos
```

需要使用自己的服务器时，可在应用设置中填写自定义地址，或通过 `API_BASE_URL` 设置定制构建的首次运行默认地址。应用内显式保存的地址优先；清空自定义地址或点击“恢复内置在线服务”后，一律使用公开在线代理。地址使用 HTTPS **根域名**，不含接口路径或密钥：

```sh
flutter run -d macos --dart-define=API_BASE_URL=https://langpack-standalone.406859116.workers.dev
```

上述命令使用新的独立部署地址，也可替换为自己的服务器。通过 `flutter devices` 获取 iOS / Android 设备标识，再替换 `-d` 参数。Windows、Linux 分别在对应系统运行 `flutter run -d windows`、`flutter run -d linux`。

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
- 与 MediaServiceClient 对齐的 35 语言覆盖：简体中文作为源文，另有 34 种目标语言可搜索、多选和导出。巴西葡萄牙语与葡萄牙葡萄牙语分开，菲律宾语使用 `fil`、书面挪威语使用 `nb`、僧伽罗语使用 `si`。
- 常见中文语义 key、自定义内容稳定备用 key 与手动修改；未接入语义命名模型。
- MyMemory 真实翻译、480 UTF-8 字节分段、Unicode / 换行 / 占位符保护、限速与临时失败重试。
- 按用户启用顺序在额度耗尽或语言不支持时切换；DeepL / Azure / Google 的长段落按不超过 4000 字符分段，MyMemory 私有词库代理按 480 UTF-8 字节分段，均不拆占位符并保留原换行；ZTAITrans 保留整段。保留实际来源及可选模型，不混合不同平台的段落片段。
- 暂停 / 继续、失败项重试、逐条重译、人工校对确认；批量保护人工结果，拒绝迟到请求覆盖新编辑。
- 默认增量翻译：同一项目按完整原文与目标语言复用已保存的成功机器译文，重复导入、重启和同批重复内容无需重复请求；新增语言只补齐该语言，修改原文只处理变化内容。语言选择页展示保留、复用和待翻译数量。
- 正式导出校验 key、完整性和占位符；各语言独立 JSON、ZIP、带报告的草稿 ZIP、最近 20 次导出快照重下载。

文档最多 **10 MB / 1000 个内容块**，DOCX 正文解压最多 **20 MB**。不支持 PDF、扫描件、旧版 DOC、加密文档或复杂版式还原；导出仅包含文本资源。文档文件在本地解析；开始翻译后，所选原文会发送给对应服务。

各平台免费额度、套餐和限流以账户控制台为准。DeepL 新注册 Developer 为总计 100 万字符，旧 Free 为每月 50 万；Azure F0 每月 200 万字符，到限停止；Google Basic 每月 50 万 NMT 字符抵扣，需结算账户，超额可能收费，请设置用量限额。ZTAITrans 不承诺免费或永久免费。应用不会因免费接口失败而自动换到付费接口。

项目、校对、任务摘要、导出快照与设置保存在当前设备或浏览器，无账户、云同步或跨设备共享。Flutter 各端数据与旧版 `web/` 原型分别保存；旧版数据不自动迁移，新版需重新导入原文。删除应用 / 浏览器站点数据会移除记录，请及时导出需要保留的语言包。

开始一次有效的批量翻译后，会保存最近选择的目标语言，即使所有译文都已存在或可以本地复用。新项目、新文本/文档翻译和项目发起的新翻译默认沿用最近选择；单纯勾选、无效或空任务、单条重译、恢复与失败重试不会改写这项偏好。新操作的语言选择独立保存为本轮草稿，取消不会改动项目历史范围；正式启动后将新增目标并入项目。浏览旧项目、校对和导出继续使用项目已有语言；恢复与失败重试沿用原批次语言快照。修改邮箱、备用服务等其他设置也会保留最近语言。

MyMemory 不支持精确的巴西葡萄牙语、菲律宾语、书面挪威语目标；这些语言需要启用支持的平台，不混用其他语言或地区变体。平台能力受服务商变更影响；本次新增平台只完成模拟验证，未逐种执行真实服务验收。

应用进入后台、窗口隐藏或关闭网页时会暂停任务并保存成功结果，恢复后可处理未完成项；不保证后台持续翻译。重启后未完整完成的长段落可能重新请求部分分段。

增量复用保留实际服务来源，新复制的译文仍需校对。仅复用原文和版本一致、占位符完整的成功机器结果；人工修改、失败或来源不明的内容不进入共享候选，多个不同成功译文冲突时重新请求。同批首个新成功结果可供后续相同内容使用；“重新翻译”会明确发送新请求。项目之间不共享持久译文，移除的文案不另建历史记忆。

## 检查与构建

默认检查不调用真实翻译服务：

```sh
flutter analyze
flutter test
```

`provider_service_test.dart`、`provider_controller_test.dart` 与 `widget_test.dart` 使用模拟响应验证多平台路由、凭据隔离、冷却恢复、分段、设置及增量复用，不调用真实接口。`live_smoke_test.dart` 默认关闭；只有明确开启 `RUN_LIVE_TRANSLATION` 或 `RUN_PUBLIC_PROXY_TEST` 时才可能调用真实服务并消耗额度。ZTAITrans 的真实备用流程还需通过受控运行环境提供 `LANGPACK_ZTAI_API_KEY` 或 `LANGPACK_DEVELOPER_TOKEN`，不能通过客户端构建参数嵌入密钥。没有凭据时不会运行真实备用用例。

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
