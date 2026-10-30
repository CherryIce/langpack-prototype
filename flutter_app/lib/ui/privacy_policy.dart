import 'package:flutter/material.dart';

class PrivacyPolicyContent extends StatelessWidget {
  const PrivacyPolicyContent({super.key, required this.english});

  final bool english;

  @override
  Widget build(BuildContext context) {
    final sections = english
        ? const [
            (
              'Data on your device',
              'Projects, source strings, translations, review results, task summaries, export history, and preferences are saved on the device or browser you use. LangPack currently has no account system or cloud sync, so this data is not automatically shared across devices.',
            ),
            (
              'Imported documents',
              'Text, Markdown, and Word documents are read and parsed on your device. When you start translation, the selected text is sent for translation. The original document file is not uploaded by this workflow.',
            ),
            (
              'Information sent for translation',
              'Translation requests include the selected source text, source and target languages, and any credentials required by your chosen provider. If you enter a MyMemory contact email, it is also sent with the relevant requests.\n\n'
                  'Anonymous MyMemory requests and requests using only a contact email go directly to MyMemory. Requests using a private MyMemory key, and requests to other providers, go through the built-in proxy or a custom proxy you configure. That proxy forwards the necessary information to the selected translation provider.\n\n'
                  'Services receive connection information needed to handle a request. When the built-in proxy forwards MyMemory requests, the request IP address may be passed to MyMemory when available so it can identify the applicable quota.',
            ),
            (
              'Provider credentials',
              'Credentials stay in the current application session by default. If you turn on “Save credentials on this device,” they are saved separately on this device without additional encryption. Leave this option off on a shared device. Credentials are excluded from projects, task records, and exported language packs.\n\n'
                  'You can clear a provider’s credentials from its details page. This removes both the current session copy and the copy saved on this device.',
            ),
            (
              'Credential verification',
              'Saving credentials starts a separate provider check. This check uses the credentials and does not send your project text. Some providers use a fixed one-character test translation, which may incur usage or charges. DeepL and Google checks use read-only interfaces. Anonymous MyMemory checks do not send a test translation to the provider. Manually verifying again can make another request.',
            ),
            (
              'Third-party services',
              'Translation providers and the operator of a custom proxy process requests under their own rules and privacy policies. Choose services and proxies you trust, and review their policies before sending content or credentials.',
            ),
            (
              'Managing your data',
              'You can delete projects and clear provider credentials in the app. Removing the app or clearing its local data or browser site data may remove your saved records. Export any language packs you need to keep. Files already exported to your device are managed by you and are not removed when you delete a project in LangPack.',
            ),
          ]
        : const [
            (
              '保存在设备上的内容',
              '项目、原文、译文、校对结果、任务摘要、导出记录和偏好设置保存在当前设备或浏览器中。LangPack 当前没有账户系统和云同步，这些数据不会自动在不同设备间共享。',
            ),
            (
              '导入的文档',
              '文本、Markdown 和 Word 文档在本机读取和解析。开始翻译后，选中的文本会发送给翻译服务；这一流程不会上传文档原文件。',
            ),
            (
              '翻译时发送的信息',
              '翻译请求会包含所选原文、原文和目标语言，以及所选平台需要的凭据。如果填写了 MyMemory 联系邮箱，相关请求也会携带该邮箱。\n\n'
                  'MyMemory 匿名模式或仅填写联系邮箱时，直接连接 MyMemory。使用 MyMemory 私有词库密钥或其他平台时，请求会经过内置代理或你配置的自定义代理，由代理向所选翻译平台转发必要信息。\n\n'
                  '服务会接收处理请求所需的网络连接信息。内置代理转发 MyMemory 请求时，会在可获取的情况下将请求的 IP 地址提供给 MyMemory，用于识别相应额度。',
            ),
            (
              '平台凭据',
              '凭据默认只保留在本次应用会话中。开启“在本机保存凭据”后，凭据会单独保存在本机，该存储不提供额外加密。共享设备建议保持关闭。凭据不会写入项目、任务记录或导出的语言包。\n\n'
                  '你可以在平台详情页清除凭据，同时移除本次会话及本机保存的副本。',
            ),
            (
              '凭据验证',
              '保存凭据后会进行一次独立的平台验证。验证会使用凭据，不会发送项目文案。部分平台会使用固定的单字试译，可能产生字符用量或费用；DeepL 和 Google 使用只读接口检查。MyMemory 匿名模式不会向平台发送试译。手动重新验证会再次发起请求。',
            ),
            (
              '第三方服务',
              '翻译平台和自定义代理的运营方按照各自的规则与隐私政策处理请求。请使用你信任的平台和代理，并在发送内容或凭据前了解相应政策。',
            ),
            (
              '管理和删除数据',
              '你可以在应用中删除项目、清除平台凭据。卸载应用、清除应用本地数据或浏览器站点数据，可能会移除已保存的记录。请提前导出需要保留的语言包。已导出到设备的文件由你自行管理，删除 LangPack 内的项目不会删除这些文件。',
            ),
          ];
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          english
              ? 'This page explains how the current version of LangPack handles the information used by its features.'
              : '本页说明 LangPack 当前版本在使用各项功能时如何处理相关信息。',
          style: textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.6),
        ),
        for (final section in sections) ...[
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(
              section.$1,
              style: textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.$2,
            style: textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.6),
          ),
        ],
      ],
    );
  }
}
