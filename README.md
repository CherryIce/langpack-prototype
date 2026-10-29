# 译包 LangPack · 主备真实翻译

**[在线体验：译包 LangPack · 多语言工作台](https://langpack-studio-oct29.neonkrill256.chatgpt.site)**（已公开）

完整体验：项目首页 → 文本输入 / 文档导入 → 多选语言 → MyMemory 翻译 → 校对 → JSON / ZIP 下载。

## 打开

前端源码位于 `web/`，服务端代理位于 `worker/`。[在线版本](https://langpack-studio-oct29.neonkrill256.chatgpt.site) 已公开，普通使用者无需配置翻译密钥。

本地运行 `node scripts/dev-server.mjs`，通过标准输入的一行 JSON 提供服务端密钥（`{"key":"你的服务端密钥"}`），或由受控环境提供 `TRANSLATION_API_KEY`。访问打印的 `http://127.0.0.1:4173`。不要把密钥放进命令行参数、前端代码或交付包。

构建执行 `bash scripts/build.sh`，再执行 `node scripts/validate-artifact.mjs`；生成的 `dist/server/index.js` 内嵌静态界面，但不包含运行时密钥。

## 已实现

- 项目创建、搜索、文案列表和浏览器本地保存。
- 文本按行 / 空行拆分，常见文案语义 key；自定义内容使用稳定备用 key，并允许手动命名。
- TXT、Markdown、DOCX 本地解析，段落勾选、编辑、合并与按句拆分。
- 英语、日语、韩语、法语、德语、西班牙语、繁体中文多选。
- MyMemory 主服务与 ZTAITrans 自动备用，记录每条译文的实际来源。MyMemory 额度耗尽后，备用重译当前完整原段，并在冷却期处理后续条目。
- 逐条逐语言进度、暂停与恢复、任务记录和只重试失败项。
- 长段落按 480 UTF-8 字节优先按句切分，接口每次最多 500 字节；合并后仍对应原来的一个 key，保留换行及占位符。
- 串行限速约 1.1 秒 / 请求；单次请求 15 秒超时，临时网络、限流与服务错误最多自动重试两次。
- MyMemory 日额度耗尽后自动切换备用；备用授权、配置不可用时停止，预算耗尽单独提示。保留成功结果，不把服务商警告当成译文。
- 译文编辑、人工确认、key 唯一性及占位符检查。
- 独立 JSON 与 ZIP 真实下载，缺失译文阻止正式导出，草稿 ZIP 附校验报告。
- 导出快照重下载、偏好设置、手机底部导航与电脑工作台布局。

## 边界

主服务调用 `https://api.mymemory.translated.net/get`，无需 API key。备用通过同源 `/api/translation/backup` 调用 ZTAITrans，密钥只保存在服务端 `TRANSLATION_API_KEY`，上游地址和 fast 档位固定。仅 MyMemory 的额度耗尽触发自动切换，普通源文或请求错误不会盲目回退。

点击开始翻译会将所选原文发送给相应服务；文档文件本身只在本地解析，不调用公共翻译记忆写入接口。设置中可选填自己的有效联系邮箱，通过 `de` 参数随请求发送。官方匿名额度每天 5,000 字符，提供有效邮箱为每天 50,000 字符，具体以服务商规则为准。

key 继续由本地规则生成，未知文案提供稳定备用 key 并允许手动命名。未接入语义命名大模型、账户或云端存储。数据保存在当前浏览器，清理站点数据后不会保留；导出记录最多保留最近 20 次。

旧项目、人工编辑和导出快照保留。旧版未编辑的演示译文会标记来源，并要求重译或重新人工确认，不会冒充真实服务结果。批量翻译默认保护人工修改和已确认内容；单条重译提供明确替换操作，并防止迟到结果覆盖请求期间的新编辑。

页面关闭会中断网络任务；刷新后成功条目保留，其余项可继续。同一页面会话内，已成功的分段缓存可用于失败重试；刷新后未完整完成的长段落可能重新请求部分分段。原文变化时，旧任务不会覆盖新文案。

文档限制为 10 MB、1000 个内容块；DOCX 需要支持 `DecompressionStream('deflate-raw')` 的现代浏览器。PDF、扫描件和旧版 DOC 暂不支持。复杂 DOCX 布局不保证还原，导出仅包含文本资源。

所有项目文件均为独立新增，未修改上层 APP 效果册。

## 验证

执行 `node --test tests/*.test.cjs tests/*.test.mjs`。`tests/browser-fixture.html` 是仅用于浏览器回归的模拟响应页面，不包含在发布的静态目录中。真实服务成功结果与模拟服务验证须分别记录；已用真实服务验证主服务额度耗尽后的备用翻译、文档解析、校对和导出，详细证据见 outputs 下的本轮验证记录。自动化用例与真实服务验收分别记录。

官方文档：https://mymemory.translated.net/doc/spec.php 与 https://mymemory.translated.net/doc/usagelimits.php。

## 备用服务限制

ZTAITrans 使用现有授权额度；附件文档没有承诺免费或永久免费。备用客户端最长等待约 10 分钟，服务端固定 fast，不自动升级档位。单段最多 50,000 个字符、请求体 256 KiB；超过限制需在导入预览中拆分。单条响应实测可能把业务 ID 回显为 "1"，仅在原文完全一致时兼容，其他错配继续拒绝。

仓库及本地交付包均不包含实际密钥；部署使用 Sites 的秘密环境变量。

## Flutter 多端版本

Flutter 工程位于 [`flutter_app/`](flutter_app/README.md)，覆盖 iOS、Android、桌面（Windows / macOS / Linux）与 Web，共用文本输入、文档导入、语言多选、真实翻译、校对与 JSON / ZIP 导出流程。原版 `web/` 和现有服务端代理保留。

使用 Flutter 3.35.7 / Dart 3.9.2，在 `flutter_app/` 执行 `flutter pub get`、`flutter analyze`、`flutter test`。完整 Web 流程先执行 `flutter build web --release`，再到仓库根目录运行 `node scripts/flutter-server.mjs`，打开 `http://127.0.0.1:4180`。原生 App（iOS / Android / Windows / macOS / Linux）默认复用公开在线项目的备用代理，无需填写密钥或自行搭建服务器；已有空配置会自动使用此默认服务。显式自定义的服务器地址仍保留，可在设置中清空以恢复应用默认连接。Flutter Web 使用其部署站点的同源代理；自行部署时，备用密钥仅由运营方通过服务端环境变量 `TRANSLATION_API_KEY` 注入。

Flutter 各端本地数据与原版浏览器数据分别保存，没有账户或云同步；旧版原文需重新导入。平台启动、调试地址、签名、真实 API 验收和 CI 边界详见 [Flutter 使用说明](flutter_app/README.md)。`.github/workflows/flutter.yml` 提供多平台检查；[此前六平台构建记录](https://github.com/CherryIce/langpack-prototype/actions/runs/40858371621) 已成功，后续改动以对应提交的新检查结果为准。构建成功不代表真机验收或商店发布。

原生 App 的默认在线代理需要安装包含本次改动的新版本；仅将网站设为公开不会改变已安装的旧版 App。旧版也可先把备用服务器地址填写为 `https://langpack-studio-oct29.neonkrill256.chatgpt.site`，无需填写 API 密钥。公共备用服务共享站点现有授权额度，并不承诺永久免费。
