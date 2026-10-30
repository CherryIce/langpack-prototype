import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import '../services/translation_service.dart' show defaultBackupServiceOrigin;
import 'ios_modals.dart';
import 'privacy_policy.dart';
import 'settings_detail_page.dart';

const _green = Color(0xFF197E64);
const _ink = Color(0xFF243E34);
const _muted = Color(0xFF72887A);
const _line = Color(0xFFE1E9E2);
const _canvas = Color(0xFFF5F8F4);

/// One adaptive workspace for mobile, desktop, and the browser.
class LangPackApp extends StatelessWidget {
  const LangPackApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '译包 LangPack',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _green,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: _canvas,
      dividerColor: _line,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: _ink,
        displayColor: _ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF9FBF8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _green, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _green,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _green),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE0F1E6),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
      ),
    ),
    home: _Workspace(controller: controller),
  );
}

enum _View {
  home,
  project,
  input,
  document,
  languages,
  progress,
  review,
  export,
  tasks,
  exports,
  settings,
}

class _Workspace extends StatefulWidget {
  const _Workspace({required this.controller});
  final AppController controller;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  AppController get c => widget.controller;
  bool get _compact => MediaQuery.sizeOf(context).width < 650;
  static const _englishLanguageNames = <String, String>{
    'zh-Hans': 'Simplified Chinese',
    'zh-Hant': 'Traditional Chinese',
    'en': 'English',
    'pt-BR': 'Portuguese (Brazil)',
    'pt-PT': 'Portuguese (Portugal)',
    'ms': 'Malay',
    'th': 'Thai',
    'fr': 'French',
    'es': 'Spanish',
    'ar': 'Arabic',
    'fil': 'Filipino',
    'vi': 'Vietnamese',
    'ru': 'Russian',
    'tr': 'Turkish',
    'id': 'Indonesian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'de': 'German',
    'hi': 'Hindi',
    'hu': 'Hungarian',
    'it': 'Italian',
    'ro': 'Romanian',
    'sv': 'Swedish',
    'bg': 'Bulgarian',
    'pl': 'Polish',
    'da': 'Danish',
    'fi': 'Finnish',
    'nl': 'Dutch',
    'cs': 'Czech',
    'sk': 'Slovak',
    'uk': 'Ukrainian',
    'el': 'Greek',
    'nb': 'Norwegian Bokmål',
    'hr': 'Croatian',
    'si': 'Sinhala',
  };
  bool get _en => c.settings.interfaceLocale == 'en';
  String _t(String zh, String en) => _en ? en : zh;
  String _sourceName(Project project) => project.sourceLocale == 'en'
      ? _t('英文', 'English')
      : _t('中文', 'Simplified Chinese');
  String _languageLabel(Language language) => _en
      ? _englishLanguageNames[language.code] ?? language.nativeName
      : language.name;
  String _localeLabel(String code, {String? sourceLocale}) {
    final language = targetLanguagesFor(
      sourceLocale ?? c.currentProject?.sourceLocale ?? 'zh-Hans',
    ).where((item) => item.code == code).firstOrNull;
    return language == null ? code : _languageLabel(language);
  }

  _View _view = _View.home;
  final _input = TextEditingController();
  final _prefix = TextEditingController();
  String _split = 'line';
  String _search = '';
  String _languageSearch = '';
  String _locale = 'en';
  String _previewFile = '';
  List<DocumentBlock> _textBlocks = [];
  List<DocumentBlock> _documentBlocks = [];
  bool _importing = false;
  int _importGeneration = 0;
  String? _inputError;
  bool _draft = false;
  bool _saving = false;
  int _reviewIndex = 0;
  String? _lastError;
  String _lastMessage = '';
  bool? _backupConfigured;
  int _backupCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
    if (c.error != null || c.message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onController());
    }
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _input.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    final error = c.error;
    final message = c.message;
    if (error != null && error.isNotEmpty && error != _lastError) {
      _lastError = error;
      _notify(error, error: true);
    } else if (error == null) {
      _lastError = null;
    }
    if (message.isNotEmpty && message != _lastMessage && error == null) {
      _lastMessage = message;
      _notify(message);
    }
    setState(() {});
  }

  void _notify(String text, {bool error = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizeError(text)),
          backgroundColor: error ? const Color(0xFF9B4B39) : _ink,
          duration: Duration(seconds: error ? 7 : 4),
        ),
      );
    });
  }

  String _localizeError(String text) {
    if (!_en || !RegExp(r'[\u3400-\u9fff]').hasMatch(text)) return text;
    final raw = text.replaceFirst(RegExp(r'^FormatException:\s*'), '');
    const known = <String, String>{
      '请输入项目名称。': 'Enter a project name.',
      '请先选择文案及目标语言。': 'Select source strings and target languages first.',
      '请至少选择一条文案。': 'Select at least one source string.',
      '请至少选择一种目标语言。': 'Select at least one target language.',
      '中文原文不能为空。': 'Source text cannot be empty.',
      '英文原文不能为空。': 'Source text cannot be empty.',
      '没有待翻译文案，已保留成功及人工校对的结果。':
          'Nothing new to translate. Completed and reviewed results are preserved.',
      '翻译已暂停，成功结果已保留。继续时处理未完成项。':
          'Translation paused. Completed results are saved. Resume to process pending items.',
      '翻译未完成，请检查网络后重试。':
          'Translation did not finish. Check your connection and retry.',
      '语言包已导出，快照已保存。': 'Language packs exported and a snapshot saved.',
      '设置已保存。': 'Settings saved.',
      '凭据已保存到本机，可随时清除。':
          'Credentials saved on this device. You can clear them anytime.',
      '凭据仅在本次会话使用。': 'Credentials are used only in this session.',
      '该平台的会话及本机凭据已清除。':
          'Session and device credentials for this provider were cleared.',
      '不支持这个平台的凭据配置。': 'Credential setup for this provider is not supported.',
      '请选择自备密钥或开发者访问码中的一种。':
          'Choose either your own API key or a developer access code.',
      '请完整填写该平台的所有必填凭据。': 'Fill in all required credentials for this provider.',
      '请输入有效联系邮箱，或留空。': 'Enter a valid contact email or leave it blank.',
      '本地保存失败，可能已超出存储空间。请导出语言包备份。':
          'Local save failed, possibly because storage is full. Export a language pack backup.',
      '本地数据未能读取，原始存档已保留。请导出当前工作备份。':
          'Local data could not be read. The original archive is preserved; export a backup of your current work.',
      '已保存的翻译凭据无法读取，请重新配置；项目数据已保留。':
          'Saved provider credentials could not be read. Reconfigure them; project data is preserved.',
      '本机凭据未完成保存或清除，旧的本机副本可能仍保留，请重试。':
          'Device credentials could not be saved or cleared. An older copy may remain; retry.',
    };
    final translated = known[raw];
    if (translated != null) return translated;
    if (raw.contains('占位符')) {
      return 'Placeholders do not match the source text. Fix them before confirming or exporting.';
    }
    if (raw.contains('额度') || raw.contains('余额')) {
      return 'Provider quota or balance may be exhausted. Check the provider console or try another enabled provider.';
    }
    if (raw.contains('鉴权') || raw.contains('凭据')) {
      return 'Provider authentication failed. Check the credentials and configuration.';
    }
    if (raw.contains('不支持') && raw.contains('语言')) {
      return 'This target language is not supported by the selected provider.';
    }
    if (raw.contains('DOCX') || raw.contains('文档')) {
      return 'The document could not be read. Use a valid, unencrypted TXT, Markdown, or DOCX file.';
    }
    if (raw.contains('网络') || raw.contains('请求')) {
      return 'The request could not be completed. Check your connection and retry.';
    }
    return 'Could not complete this action. Check the input or provider settings and try again.';
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _notify(error.toString(), error: true);
    }
  }

  void _go(_View view) {
    if (view == _View.languages && _view == _View.review) {
      c.setBatchLocales(c.currentProject?.locales ?? []);
    }
    if (_view == _View.document && view != _View.document) {
      _importGeneration++;
      _importing = false;
    }
    c.clearError();
    setState(() => _view = view);
  }

  List<DocumentBlock> get _blocks =>
      _view == _View.document ? _documentBlocks : _textBlocks;
  List<Entry> get _entries => c.currentProject?.selectedEntries.toList() ?? [];

  int get _navIndex => switch (_view) {
    _View.tasks => 1,
    _View.exports => 2,
    _View.settings => 3,
    _ => 0,
  };

  String get _title => switch (_view) {
    _View.home => _t('我的项目', 'My projects'),
    _View.project => c.currentProject?.name ?? '项目',
    _View.input => _t('文本输入', 'Text input'),
    _View.document => _t('文档导入', 'Import document'),
    _View.languages => _t('目标语言', 'Target languages'),
    _View.progress => _t('翻译任务', 'Translation task'),
    _View.review => _t('翻译校对', 'Review translations'),
    _View.export => _t('导出语言包', 'Export language packs'),
    _View.tasks => _t('翻译任务', 'Translation tasks'),
    _View.exports => _t('导出记录', 'Exports'),
    _View.settings => _t('偏好设置', 'Settings'),
  };

  void _selectNavigation(int index) {
    _go([_View.home, _View.tasks, _View.exports, _View.settings][index]);
  }

  void _openActiveProgress() {
    final id = c.activeProjectId;
    if (id == null || !c.projects.any((project) => project.id == id)) {
      _notify('该任务对应的项目已不存在。');
      return;
    }
    c.openProject(id);
    _go(_View.progress);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final compact = MediaQuery.sizeOf(context).width < 650;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (!compact) _sidebar(wide),
            Expanded(
              child: Column(
                children: [
                  _topbar(compact),
                  if (c.running && _view != _View.progress) _runningBanner(),
                  Expanded(
                    child: c.loading
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            key: ValueKey(_view),
                            padding: EdgeInsets.fromLTRB(
                              compact ? 16 : 34,
                              compact ? 16 : 34,
                              compact ? 16 : 34,
                              compact ? 24 : 40,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1260,
                                ),
                                child: _content(),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: compact
          ? NavigationBar(
              height: 64,
              selectedIndex: _navIndex,
              onDestinationSelected: _selectNavigation,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.grid_view_rounded),
                  label: _t('我的项目', 'Projects'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.translate_rounded),
                  label: _t('翻译任务', 'Tasks'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: _t('导出记录', 'Exports'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.tune_rounded),
                  label: _t('设置', 'Settings'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _sidebar(bool wide) => Container(
    width: wide ? 228 : 82,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: _line)),
    ),
    padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 12, vertical: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Brand(compact: !wide),
        const SizedBox(height: 42),
        if (wide)
          Padding(
            padding: EdgeInsets.only(left: 14, bottom: 15),
            child: Text(
              _t('工作空间', 'Workspace'),
              style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: _muted),
            ),
          ),
        for (var index = 0; index < 4; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: _navIndex == index
                  ? const Color(0xFFEAF4EC)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _selectNavigation(index),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 15 : 14,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        [
                          Icons.grid_view_rounded,
                          Icons.translate_rounded,
                          Icons.folder_zip_outlined,
                          Icons.tune_rounded,
                        ][index],
                        size: 21,
                        color: _navIndex == index ? _green : _muted,
                      ),
                      if (wide) ...[
                        const SizedBox(width: 12),
                        Text(
                          _en
                              ? [
                                  'Projects',
                                  'Tasks',
                                  'Exports',
                                  'Settings',
                                ][index]
                              : ['我的项目', '翻译任务', '导出记录', '偏好设置'][index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _navIndex == index
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _navIndex == index ? _green : _muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (wide)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.public_rounded, color: _green, size: 22),
                const SizedBox(height: 10),
                Text(
                  _t('让表达，跨越语言', 'Make every word travel'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  _t(
                    '从一句中文，到世界的每一种声音。',
                    'From your words to a world of languages.',
                  ),
                  style: TextStyle(fontSize: 11, height: 1.8, color: _muted),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: wide
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFFE7EFE0),
              child: Text(
                'L',
                style: TextStyle(color: _green, fontWeight: FontWeight.w700),
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('本地工作空间', 'Local workspace'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'LANGPACK STUDIO',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.2,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _topbar(bool compact) => Container(
    height: compact ? 56 : 72,
    padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 34),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        if (compact) ...[
          const _Brand(compact: true),
          const SizedBox(width: 13),
        ],
        if (!compact) ...[
          const Icon(Icons.home_outlined, size: 18, color: _muted),
          const SizedBox(width: 10),
          Text(
            _t('工作空间', 'Workspace'),
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right, size: 16, color: _muted),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        if (compact)
          Tooltip(
            message: _t('切换为英文', 'Switch to Chinese'),
            child: OutlinedButton(
              key: const ValueKey('interface-locale-switch'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(52, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
              ),
              onPressed: () => c.setInterfaceLocale(_en ? 'zh' : 'en'),
              child: Text(_en ? '中文' : 'EN'),
            ),
          )
        else
          SegmentedButton<String>(
            key: const ValueKey('interface-locale-switch'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 'zh', label: Text('中文')),
              ButtonSegment(value: 'en', label: Text('EN')),
            ],
            selected: {c.settings.interfaceLocale},
            onSelectionChanged: (values) => c.setInterfaceLocale(values.first),
          ),
      ],
    ),
  );

  Widget _runningBanner() => Material(
    color: const Color(0xFFE5F2E9),
    child: InkWell(
      onTap: _openActiveProgress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_t('翻译进行中', 'Translating')} · ${c.completed}/${c.total} · ${c.activeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _green),
              ),
            ),
            Text(
              _t('查看', 'View'),
              style: const TextStyle(fontSize: 12, color: _green),
            ),
            const Icon(Icons.chevron_right, size: 17, color: _green),
          ],
        ),
      ),
    ),
  );

  Widget _content() {
    if ([
          _View.project,
          _View.input,
          _View.document,
          _View.languages,
          _View.progress,
          _View.review,
          _View.export,
        ].contains(_view) &&
        c.currentProject == null) {
      return _Empty(
        icon: Icons.folder_open_rounded,
        title: _t('先创建一个项目', 'Create a project first'),
        detail: _t(
          '把相关文案放在一起，管理它们的多语言版本。',
          'Keep related text and its translations together.',
        ),
        action: FilledButton.icon(
          onPressed: _newProject,
          icon: const Icon(Icons.add),
          label: Text(_t('新建项目', 'New project')),
        ),
      );
    }
    return switch (_view) {
      _View.home => _home(),
      _View.project => _project(),
      _View.input || _View.document => _inputPage(),
      _View.languages => _languages(),
      _View.progress => _progress(),
      _View.review => _review(),
      _View.export => _export(),
      _View.tasks => _tasks(),
      _View.exports => _exports(),
      _View.settings => _settings(),
    };
  }

  Widget _home() {
    final projects = c.projects
        .where(
          (p) => '${p.name} ${p.description}'.toLowerCase().contains(
            _search.toLowerCase(),
          ),
        )
        .toList();
    final totalEntries = c.projects.fold<int>(
      0,
      (sum, p) => sum + p.entries.length,
    );
    final totalLanguages = c.projects.expand((p) => p.locales).toSet().length;
    if (_compact) {
      return _mobileHome(projects, totalEntries, totalLanguages);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          eyebrow: 'YOUR WORDS, WORLDWIDE',
          title: _t('我的项目', 'My projects'),
          subtitle: _t(
            '在这里，管理每一句表达的多语言旅程。',
            'Manage every source string and its translations here.',
          ),
          action: FilledButton.icon(
            onPressed: _newProject,
            icon: const Icon(Icons.add, size: 18),
            label: Text(_t('新建项目', 'New project')),
          ),
        ),
        const SizedBox(height: 25),
        _hero(),
        const SizedBox(height: 23),
        _stats([
          _Stat(
            _t('项目总数', 'Projects'),
            '${c.projects.length}',
            Icons.folder_outlined,
          ),
          _Stat(
            _t('源文案', 'Source strings'),
            '$totalEntries',
            Icons.notes_rounded,
          ),
          _Stat(
            _t('覆盖语言', 'Languages'),
            '$totalLanguages',
            Icons.public_rounded,
          ),
        ]),
        const SizedBox(height: 30),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 14,
          children: [
            Text(
              _t('全部项目', 'All projects'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
            ),
            SizedBox(
              width: 270,
              child: TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: _t('搜索项目名称', 'Search projects'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (projects.isEmpty)
          _Panel(
            child: _Empty(
              icon: Icons.folder_open_outlined,
              title: _search.isEmpty
                  ? _t('你的第一个多语言项目', 'Your first localization project')
                  : _t('没有找到匹配的项目', 'No matching projects'),
              detail: _search.isEmpty
                  ? _t(
                      '创建项目，输入原文或导入文档，生成可以直接使用的语言包。',
                      'Create a project, enter English text or import a document, and build language packs.',
                    )
                  : _t('试试其他关键词。', 'Try another search.'),
              action: _search.isEmpty
                  ? OutlinedButton.icon(
                      onPressed: _newProject,
                      icon: const Icon(Icons.add),
                      label: Text(_t('创建项目', 'Create project')),
                    )
                  : null,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 600
                  ? 2
                  : 1;
              return Wrap(
                spacing: 18,
                runSpacing: 18,
                children: projects
                    .map(
                      (p) => SizedBox(
                        width:
                            (constraints.maxWidth - (count - 1) * 18) / count,
                        child: _projectCard(p),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        const SizedBox(height: 30),
        Text(
          _t(
            '从原文到语言包，只需四步',
            'From source text to language packs in four steps',
          ),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Wrap(
            spacing: 28,
            runSpacing: 22,
            children: [
              for (final item
                  in _en
                      ? [
                          (
                            '01',
                            'Enter text',
                            'Paste text or import a document',
                          ),
                          (
                            '02',
                            'Choose languages',
                            'Translate to several languages',
                          ),
                          ('03', 'Review', 'Check and edit each translation'),
                          ('04', 'Export', 'Save JSON files or a ZIP'),
                        ]
                      : [
                          ('01', '输入原文', '粘贴文本或本地解析文档'),
                          ('02', '选择语言', '一次多选，按需生成译文'),
                          ('03', '校对确认', '逐条检查，保留人工修改'),
                          ('04', '导出语言包', '独立 JSON 或完整 ZIP'),
                        ])
                SizedBox(
                  width: 225,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3E6),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          item.$1,
                          style: const TextStyle(color: _green, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.$3,
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _t(
            '文档在本地解析 · 译文可追溯来源 · 标准 UTF-8 JSON',
            'Documents parsed locally · Traceable translations · UTF-8 JSON',
          ),
          style: const TextStyle(fontSize: 11, color: _muted),
        ),
      ],
    );
  }

  Widget _mobileHome(
    List<Project> projects,
    int totalEntries,
    int totalLanguages,
  ) => Column(
    key: const ValueKey('mobile-home'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            _t('我的项目', 'My projects'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          TextButton.icon(
            onPressed: _newProject,
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.add, size: 18),
            label: Text(_t('新建项目', 'New project')),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _Panel(
        color: const Color(0xFFEDF5EA),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('开始翻译', 'Start translating'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: FilledButton.icon(
                key: const ValueKey('mobile-quick-input'),
                onPressed: () => _beginInput(false),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(_t('输入文案', 'Enter text')),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: OutlinedButton.icon(
                key: const ValueKey('mobile-quick-import'),
                onPressed: () => _beginInput(true),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(_t('导入文档', 'Import document')),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('mobile-project-search'),
        onChanged: (value) => setState(() => _search = value),
        decoration: InputDecoration(
          hintText: _t('搜索项目名称', 'Search projects'),
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
        ),
      ),
      const SizedBox(height: 12),
      if (projects.isEmpty)
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _search.isEmpty
                    ? _t('还没有项目', 'No projects yet')
                    : _t('没有找到匹配的项目', 'No matching projects'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _search.isEmpty
                    ? _t(
                        '输入文案或导入文档即可开始。',
                        'Enter text or import a document to begin.',
                      )
                    : _t('试试其他关键词。', 'Try another search.'),
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        )
      else
        for (final project in projects) ...[
          _projectCard(project),
          const SizedBox(height: 12),
        ],
      const SizedBox(height: 12),
      _stats([
        _Stat(
          _t('项目总数', 'Projects'),
          '${c.projects.length}',
          Icons.folder_outlined,
        ),
        _Stat(
          _t('源文案', 'Source strings'),
          '$totalEntries',
          Icons.notes_rounded,
        ),
        _Stat(_t('覆盖语言', 'Languages'), '$totalLanguages', Icons.public_rounded),
      ]),
    ],
  );

  Widget _hero() => LayoutBuilder(
    builder: (context, constraints) => Container(
      padding: EdgeInsets.all(constraints.maxWidth < 600 ? 25 : 36),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE4F0DE), Color(0xFFEFF5E6)],
        ),
        border: Border.all(color: const Color(0xFFD7E5D4)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LOCALIZE WITH CLARITY',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2.5,
                    color: _green,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  _t('你的表达，\n不止一种语言。', 'Your words,\nin every language.'),
                  style: TextStyle(
                    fontSize: constraints.maxWidth < 600 ? 29 : 36,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                    color: const Color(0xFF315A43),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _t(
                    '从原文到多语言交付，让每一句话都被世界读懂。',
                    'Turn your source text into language packs for your audience.',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF708D75),
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _beginInput(false),
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: Text(_t('输入文案', 'Enter text')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _beginInput(true),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: Text(_t('导入文档', 'Import document')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (constraints.maxWidth >= 700) ...[
            const SizedBox(width: 30),
            SizedBox(
              width: 250,
              height: 210,
              child: Stack(
                children: [
                  Positioned(
                    left: 12,
                    top: 20,
                    child: Transform.rotate(
                      angle: -.10,
                      child: _languagePaper(
                        '中文',
                        '你好，世界',
                        '{ hello_world }',
                        const Color(0xFFF7FAEE),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 86,
                    top: 78,
                    child: Transform.rotate(
                      angle: .07,
                      child: _languagePaper(
                        'ENGLISH',
                        'Hello, world',
                        '{ hello_world }',
                        Colors.white,
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 8,
                    top: 7,
                    child: Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFA1BA7D),
                      size: 32,
                    ),
                  ),
                  const Positioned(
                    left: 15,
                    bottom: 6,
                    child: Icon(
                      Icons.language,
                      color: Color(0xFF8FAF91),
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _languagePaper(String label, String text, String code, Color color) =>
      Container(
        width: 155,
        height: 128,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: const Color(0xFFD3E0CF)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C254A2C),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1.3,
                color: _muted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _green,
              ),
            ),
            const Spacer(),
            Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: _muted,
              ),
            ),
          ],
        ),
      );

  Widget _stats(List<_Stat> stats) => _Panel(
    padding: EdgeInsets.zero,
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          for (var index = 0; index < stats.length; index++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: index == 0
                      ? null
                      : const Border(left: BorderSide(color: _line)),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: _compact
                      ? 10
                      : constraints.maxWidth < 600
                      ? 15
                      : 25,
                  vertical: _compact ? 12 : 21,
                ),
                child: stats[index],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _projectCard(Project p) {
    final ratio = p.totalCount == 0 ? 0.0 : p.translatedCount / p.totalCount;
    if (_compact) return _mobileProjectCard(p, ratio);
    return _Panel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          c.openProject(p.id);
          _go(_View.project);
        },
        child: Padding(
          padding: const EdgeInsets.all(23),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF4E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.layers_outlined, color: _green),
                  ),
                  const Spacer(),
                  _Tag(
                    p.totalCount > 0 && ratio == 1
                        ? _t('译文齐全', 'Complete')
                        : _t('进行中', 'In progress'),
                    warm: ratio < 1,
                  ),
                  PopupMenuButton<String>(
                    tooltip: _t('项目操作', 'Project actions'),
                    iconSize: 19,
                    onSelected: (value) {
                      if (value == 'delete') _deleteProject(p);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(_t('删除项目', 'Delete project')),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.description.isEmpty
                    ? _t(
                        '为每一句原文，准备一个多语言版本。',
                        'Translate each source string into more languages.',
                      )
                    : p.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: _muted,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 17),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: p.locales
                    .map(
                      (locale) => _Tag(
                        _en
                            ? _localeLabel(locale, sourceLocale: p.sourceLocale)
                            : languageName(locale),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: const Color(0xFFEDF2EA),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.short_text, size: 15, color: _muted),
                  const SizedBox(width: 5),
                  Text(
                    _t(
                      '${p.entries.length} 条文案',
                      '${p.entries.length} strings',
                    ),
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                  const Spacer(),
                  Text(
                    _date(p.updatedAt),
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileProjectCard(Project p, double ratio) => _Panel(
    padding: EdgeInsets.zero,
    child: InkWell(
      key: ValueKey('mobile-project-card-${p.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        c.openProject(p.id);
        _go(_View.project);
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _t('项目操作', 'Project actions'),
                  icon: const Icon(CupertinoIcons.ellipsis, size: 20),
                  onPressed: () async {
                    final action = await _mobileActions(
                      p.name,
                      {'delete': _t('删除项目', 'Delete project')},
                      destructive: {'delete'},
                    );
                    if (action == 'delete' && mounted) {
                      await _deleteProject(p);
                    }
                  },
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Tag(
                  p.sourceLocale == 'en'
                      ? _t('英文原文', 'English source')
                      : _t('中文原文', 'Chinese source'),
                ),
                _Tag(
                  p.totalCount > 0 && ratio == 1
                      ? _t('译文齐全', 'Complete')
                      : _t('进行中', 'In progress'),
                  warm: ratio < 1,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: const Color(0xFFEDF2EA),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                '${p.entries.length} 条文案 · ${p.translatedCount}/${p.totalCount} 条译文',
                '${p.entries.length} ${p.entries.length == 1 ? 'string' : 'strings'} · ${p.translatedCount}/${p.totalCount} translations',
              ),
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            if (p.locales.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final locale in p.locales.take(3)) _Tag(locale),
                  if (p.locales.length > 3) _Tag('+${p.locales.length - 3}'),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Future<T?> _formModal<T>(
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) async {
    final TransitionRoute<T> route = _compact
        ? CupertinoModalPopupRoute<T>(
            builder: builder,
            barrierDismissible: false,
          )
        : DialogRoute<T>(
            context: context,
            builder: builder,
            barrierDismissible: barrierDismissible,
          );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  }

  Future<String?> _mobileActions(
    String title,
    Map<String, String> actions, {
    Set<String> destructive = const {},
    Set<String> disabled = const {},
  }) => showCupertinoModalPopup<String>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text(title),
      actions: [
        for (final action in actions.entries.where(
          (action) => !disabled.contains(action.key),
        ))
          CupertinoActionSheetAction(
            isDestructiveAction: destructive.contains(action.key),
            onPressed: () => Navigator.pop(context, action.key),
            child: Text(action.value),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: Text(_t('取消', 'Cancel')),
      ),
    ),
  );

  Widget _formFrame(
    BuildContext dialogContext, {
    required String title,
    required String doneLabel,
    required Widget child,
    required VoidCallback? onDone,
    bool busy = false,
    double width = 520,
  }) {
    final cancel = busy ? null : () => Navigator.pop(dialogContext);
    if (_compact) {
      return PopScope(
        canPop: !busy,
        child: IosFormSheet(
          title: title,
          cancelLabel: _t('取消', 'Cancel'),
          doneLabel: doneLabel,
          onCancel: cancel,
          onDone: onDone,
          busy: busy,
          child: child,
        ),
      );
    }
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(title),
        content: SizedBox(width: width, child: child),
        actions: [
          TextButton(onPressed: cancel, child: Text(_t('取消', 'Cancel'))),
          FilledButton(onPressed: onDone, child: Text(doneLabel)),
        ],
      ),
    );
  }

  Future<bool> _newProject() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final form = GlobalKey<FormState>();
    var sourceLocale = _en ? 'en' : 'zh-Hans';
    final result = await _formModal<bool>(
      (context) => StatefulBuilder(
        builder: (context, updateDialog) => _formFrame(
          context,
          title: _t('创建一个新项目', 'Create a new project'),
          doneLabel: _t('创建项目', 'Create project'),
          width: 390,
          onDone: () {
            if (form.currentState!.validate()) Navigator.pop(context, true);
          },
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: _t('项目名称', 'Project name'),
                    hintText: _t('例如：产品网站', 'For example: Product website'),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? _t('请填写项目名称', 'Enter a project name')
                      : null,
                ),
                const SizedBox(height: 13),
                TextField(
                  controller: description,
                  maxLength: 180,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _t('项目说明（选填）', 'Description (optional)'),
                    hintText: _t(
                      '这个项目的文案用于什么地方？',
                      'Where will these strings be used?',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _t('原文语言', 'Source language'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                if (_compact)
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<String>(
                      key: const ValueKey('new-project-source-locale'),
                      groupValue: sourceLocale,
                      children: {
                        'zh-Hans': Text(_t('中文', 'Chinese')),
                        'en': Text(_t('英文', 'English')),
                      },
                      onValueChanged: (value) {
                        if (value != null) {
                          updateDialog(() => sourceLocale = value);
                        }
                      },
                    ),
                  )
                else
                  SegmentedButton<String>(
                    key: const ValueKey('new-project-source-locale'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 'zh-Hans',
                        label: Text(_t('中文', 'Chinese')),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(_t('英文', 'English')),
                      ),
                    ],
                    selected: {sourceLocale},
                    onSelectionChanged: (values) =>
                        updateDialog(() => sourceLocale = values.first),
                  ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    '创建后原文语言不能更改。',
                    'The source language is fixed after project creation.',
                  ),
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == true && mounted) {
      c.createProject(
        name.text.trim(),
        description: description.text.trim(),
        sourceLocale: sourceLocale,
      );
      _go(_View.project);
    }
    name.dispose();
    description.dispose();
    return result == true;
  }

  Future<void> _deleteProject(Project project) async {
    if (c.running) {
      _notify(
        _t(
          '请先暂停翻译任务，再删除项目。',
          'Pause translation before deleting this project.',
        ),
      );
      return;
    }
    final yes = await showAdaptiveConfirmation(
      context: context,
      compact: _compact,
      title: _t('删除这个项目？', 'Delete this project?'),
      message: _t(
        '“${project.name}”的文案、译文和本地导出记录将被删除。已保存到设备的文件不受影响。',
        'The strings, translations, and local export history for “${project.name}” will be deleted. Saved files stay on your device.',
      ),
      cancelLabel: _t('取消', 'Cancel'),
      confirmLabel: _t('删除项目', 'Delete project'),
      destructive: true,
    );
    if (yes == true) {
      c.deleteProject(project.id);
      if (mounted) _go(_View.home);
    }
  }

  Future<void> _beginInput(bool document) async {
    _importGeneration++;
    _importing = false;
    final quickStart = _view == _View.home || _view == _View.tasks;
    if (quickStart) {
      final preferredSource = _en ? 'en' : 'zh-Hans';
      final matching = c.projects
          .where((project) => project.sourceLocale == preferredSource)
          .firstOrNull;
      if (matching != null) {
        c.openProject(matching.id);
      } else if (!await _newProject()) {
        return;
      }
    } else if (c.currentProject == null) {
      if (!await _newProject()) return;
    }
    if (!mounted) return;
    c.applyRecentLocales();
    _languageSearch = '';
    _input.clear();
    _inputError = null;
    _prefix.clear();
    _textBlocks = [];
    _documentBlocks = [];
    _go(document ? _View.document : _View.input);
  }

  Widget _project() {
    final p = c.currentProject!;
    if (_compact) return _mobileProject(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          eyebrow: 'PROJECT / LOCALIZATION',
          title: p.name,
          subtitle: p.description.isEmpty
              ? _t(
                  '你的原文与多语言版本，都在这里。',
                  'Your source text and translations live here.',
                )
              : p.description,
          back: () => _go(_View.home),
          action: FilledButton.icon(
            onPressed: () => _beginInput(false),
            icon: const Icon(Icons.add, size: 18),
            label: Text(_t('新增文案', 'Add strings')),
          ),
        ),
        const SizedBox(height: 12),
        _Tag(
          _t(
            '源语言：${p.sourceLocale == 'en' ? '英文' : '简体中文'}（${p.sourceLocale}）',
            'Source: ${p.sourceLocale == 'en' ? 'English' : 'Simplified Chinese'} (${p.sourceLocale})',
          ),
          icon: Icons.language,
        ),
        const SizedBox(height: 24),
        _stats([
          _Stat(
            _t('${_sourceName(p)}文案', 'Source strings'),
            '${p.entries.length}',
            Icons.notes_rounded,
          ),
          _Stat(
            _t('目标语言', 'Target languages'),
            '${p.locales.length}',
            Icons.public_rounded,
          ),
          _Stat(
            _t('译文齐全度', 'Translation progress'),
            '${p.totalCount == 0 ? 0 : (100 * p.translatedCount / p.totalCount).round()}%',
            Icons.check_circle_outline,
          ),
        ]),
        const SizedBox(height: 22),
        _Panel(
          color: const Color(0xFFEDF5EA),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('每一句原文，都能走得更远', 'Take every source string further'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _t(
                      '补齐缺失译文，保护人工修改和已经确认的内容。',
                      'Fill in missing translations while keeping edits and reviewed work.',
                    ),
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: p.selectedEntries.isEmpty || c.running
                    ? null
                    : () {
                        c.applyRecentLocales();
                        _languageSearch = '';
                        _go(_View.languages);
                      },
                icon: const Icon(Icons.translate, size: 18),
                label: Text(_t('翻译未完成项', 'Translate missing items')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _t(
                '项目文案 · ${p.entries.length}',
                'Project strings · ${p.entries.length}',
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _beginInput(true),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(_t('导入文档', 'Import document')),
                ),
                TextButton.icon(
                  onPressed: p.selectedEntries.isEmpty
                      ? null
                      : () {
                          _reviewIndex = 0;
                          _go(_View.review);
                        },
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(_t('校对', 'Review')),
                ),
                OutlinedButton.icon(
                  onPressed: p.selectedEntries.isEmpty
                      ? null
                      : () => _go(_View.export),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(_t('导出语言包', 'Export language packs')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (p.entries.isEmpty)
          _Panel(
            child: _Empty(
              icon: Icons.edit_note_rounded,
              title: _t('第一条文案，从这里开始', 'Start with your first string'),
              detail: p.sourceLocale == 'en'
                  ? _t(
                      '输入英文或导入英文文档，生成你的第一组语言包。',
                      'Enter English text or import an English document to create language packs.',
                    )
                  : _t(
                      '输入中文或导入中文文档，生成你的第一组语言包。',
                      'Enter Chinese text or import a Chinese document to create language packs.',
                    ),
              action: FilledButton(
                onPressed: () => _beginInput(false),
                child: Text(_t('添加文案', 'Add strings')),
              ),
            ),
          )
        else
          _Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: p.entries.every((entry) => entry.selected),
                        onChanged: c.running
                            ? null
                            : (value) {
                                for (final entry in p.entries) {
                                  c.selectEntry(entry, value == true);
                                }
                              },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _t(
                            '已选择 ${p.selectedEntries.length} 条用于翻译和导出',
                            '${p.selectedEntries.length} selected for translation and export',
                          ),
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ),
                      const _Tag('snake_case'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (var index = 0; index < p.entries.length; index++)
                  _entryRow(p.entries[index], index),
              ],
            ),
          ),
        const SizedBox(height: 20),
        _Notice(
          _t(
            '项目数据保存在当前设备或浏览器。导出语言包后可交付使用；各端数据暂不自动同步。',
            'Project data is saved on this device or browser. Export language packs to share them. Data does not sync across devices.',
          ),
          icon: Icons.devices_outlined,
        ),
      ],
    );
  }

  Widget _mobileProject(Project p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PageHeading(
        title: p.name,
        subtitle: p.description.isEmpty
            ? _t('管理原文和语言包。', 'Manage strings and language packs.')
            : p.description,
        back: () => _go(_View.home),
      ),
      const SizedBox(height: 10),
      Semantics(
        label: _t(
          '源语言：${p.sourceLocale == 'en' ? '英文' : '简体中文'}（${p.sourceLocale}）',
          'Source: ${p.sourceLocale == 'en' ? 'English' : 'Simplified Chinese'} (${p.sourceLocale})',
        ),
        excludeSemantics: true,
        child: _Tag(
          p.sourceLocale == 'en'
              ? _t('英文原文', 'English source')
              : _t('中文原文', 'Chinese source'),
          icon: Icons.language,
        ),
      ),
      const SizedBox(height: 14),
      _Panel(
        color: const Color(0xFFEDF5EA),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: FilledButton.icon(
                onPressed: p.entries.isEmpty
                    ? () => _beginInput(false)
                    : p.selectedEntries.isEmpty || c.running
                    ? null
                    : () {
                        c.applyRecentLocales();
                        _languageSearch = '';
                        _go(_View.languages);
                      },
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: Icon(
                  p.entries.isEmpty ? Icons.add : Icons.translate,
                  size: 18,
                ),
                label: Text(
                  p.entries.isEmpty
                      ? _t('新增文案', 'Add strings')
                      : _t('翻译未完成项', 'Translate missing items'),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                if (p.entries.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _beginInput(false),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.add, size: 17),
                    label: Text(_t('新增文案', 'Add strings')),
                  ),
                TextButton.icon(
                  onPressed: () => _beginInput(true),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.upload_file, size: 17),
                  label: Text(_t('导入文档', 'Import document')),
                ),
                if (p.entries.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: p.selectedEntries.isEmpty
                        ? null
                        : () {
                            _reviewIndex = 0;
                            _go(_View.review);
                          },
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.fact_check_outlined, size: 17),
                    label: Text(_t('校对', 'Review')),
                  ),
                  TextButton.icon(
                    onPressed: p.selectedEntries.isEmpty
                        ? null
                        : () => _go(_View.export),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.file_download_outlined, size: 17),
                    label: Text(_t('导出语言包', 'Export language packs')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _stats([
        _Stat(
          _t('${_sourceName(p)}文案', 'Source strings'),
          '${p.entries.length}',
          Icons.notes_rounded,
        ),
        _Stat(
          _t('目标语言', 'Target languages'),
          '${p.locales.length}',
          Icons.public_rounded,
        ),
        _Stat(
          _t('译文齐全度', 'Translation progress'),
          '${p.totalCount == 0 ? 0 : (100 * p.translatedCount / p.totalCount).round()}%',
          Icons.check_circle_outline,
        ),
      ]),
      const SizedBox(height: 18),
      Text(
        _t(
          '项目文案 · ${p.entries.length}',
          'Project strings · ${p.entries.length}',
        ),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      if (p.entries.isEmpty)
        _Panel(
          child: Text(
            p.sourceLocale == 'en'
                ? _t(
                    '输入英文或导入英文文档，开始翻译。',
                    'Enter English text or import an English document to begin.',
                  )
                : _t(
                    '输入中文或导入中文文档，开始翻译。',
                    'Enter Chinese text or import a Chinese document to begin.',
                  ),
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        )
      else
        _Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: p.entries.every((entry) => entry.selected),
                      onChanged: c.running
                          ? null
                          : (value) {
                              for (final entry in p.entries) {
                                c.selectEntry(entry, value == true);
                              }
                            },
                    ),
                    Expanded(
                      child: Text(
                        _t(
                          '已选择 ${p.selectedEntries.length} 条用于翻译和导出',
                          '${p.selectedEntries.length} selected for translation and export',
                        ),
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (var index = 0; index < p.entries.length; index++)
                _entryRow(p.entries[index], index),
            ],
          ),
        ),
    ],
  );

  Widget _entryRow(Entry entry, int index) {
    final p = c.currentProject!;
    final done = p.locales
        .where(
          (locale) =>
              entry.translations[locale]?.text.trim().isNotEmpty == true,
        )
        .length;
    if (_compact) return _mobileEntryRow(entry, done, p);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: entry.selected,
            onChanged: c.running
                ? null
                : (value) => c.selectEntry(entry, value == true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.source,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 5),
                Text(
                  entry.key,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _green,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: p.locales
                      .map(
                        (locale) => _Tag(
                          _localeLabel(locale),
                          warm:
                              entry.translations[locale]?.text
                                  .trim()
                                  .isNotEmpty !=
                              true,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Text(
                '$done/${p.locales.length}',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
              IconButton(
                tooltip: _t('校对这条文案', 'Review this string'),
                onPressed: () {
                  if (!entry.selected) c.selectEntry(entry, true);
                  _reviewIndex = _entries.indexWhere((e) => e.id == entry.id);
                  _go(_View.review);
                },
                icon: const Icon(Icons.chevron_right, color: _green),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: _t('文案操作', 'String actions'),
            onSelected: (action) {
              if (action == 'edit') {
                _editEntrySource(entry);
              } else if (!c.running) {
                c.deleteEntry(entry);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(_t('编辑原文', 'Edit source')),
              ),
              PopupMenuItem(
                value: 'delete',
                enabled: !c.running,
                child: Text(_t('删除文案', 'Delete string')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobileEntryRow(Entry entry, int done, Project p) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: InkWell(
      onTap: () {
        if (!entry.selected) c.selectEntry(entry, true);
        _reviewIndex = _entries.indexWhere((item) => item.id == entry.id);
        _go(_View.review);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: entry.selected,
              onChanged: c.running
                  ? null
                  : (value) => c.selectEntry(entry, value == true),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.source,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$done/${p.locales.length}',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                  if (p.locales.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final locale in p.locales.take(3))
                          _Tag(
                            locale,
                            warm:
                                entry.translations[locale]?.text
                                    .trim()
                                    .isNotEmpty !=
                                true,
                          ),
                        if (p.locales.length > 3)
                          _Tag('+${p.locales.length - 3}'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: _t('文案操作', 'String actions'),
              icon: const Icon(CupertinoIcons.ellipsis, size: 20),
              onPressed: () async {
                final action = await _mobileActions(
                  _t('文案操作', 'String actions'),
                  {
                    'edit': _t('编辑原文', 'Edit source'),
                    'delete': _t('删除文案', 'Delete string'),
                  },
                  destructive: {'delete'},
                  disabled: {if (c.running) 'delete'},
                );
                if (!mounted) return;
                if (action == 'edit') {
                  await _editEntrySource(entry);
                } else if (action == 'delete' && !c.running) {
                  c.deleteEntry(entry);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget _workflow(
    int index,
    String title,
    String subtitle, {
    VoidCallback? back,
  }) => _compact
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeading(
              title: title,
              subtitle: subtitle,
              back: back ?? () => _go(_View.project),
            ),
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('mobile-workflow-progress'),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF5EA),
                border: Border.all(color: _line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    '${index + 1}/4',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (index + 1) / 4,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFDCE9D8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeading(
              title: title,
              subtitle: subtitle,
              back: back ?? () => _go(_View.project),
              eyebrow: 'CREATE A LANGUAGE PACK',
            ),
            const SizedBox(height: 24),
            _Panel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 17),
              child: Row(
                children: [
                  for (var step = 0; step < 4; step++)
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: step <= index
                                  ? _green
                                  : const Color(0xFFEDF2E9),
                              shape: BoxShape.circle,
                            ),
                            child: step < index
                                ? const Icon(
                                    Icons.check,
                                    size: 15,
                                    color: Colors.white,
                                  )
                                : Text(
                                    '${step + 1}',
                                    style: TextStyle(
                                      color: step <= index
                                          ? Colors.white
                                          : _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (_en
                                ? [
                                    'Add content',
                                    'Choose languages',
                                    'Review',
                                    'Export',
                                  ]
                                : ['添加内容', '选择语言', '翻译校对', '导出语言包'])[step],
                            style: TextStyle(
                              fontSize: 11,
                              color: step <= index ? _green : _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );

  Widget _inputPage() {
    final document = _view == _View.document;
    final blocks = _blocks;
    final project = c.currentProject!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflow(
          0,
          document
              ? _t('从文档开始，一次翻译全文', 'Import a document to translate')
              : project.sourceLocale == 'en'
              ? _t('添加你的英文文案', 'Add your English text')
              : _t('添加你的中文文案', 'Add your Chinese text'),
          _t(
            '每一段表达，都值得被更多人读懂。',
            'Make every message understandable in more languages.',
          ),
        ),
        _columns(
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(_t('文本输入', 'Text input')),
                      avatar: const Icon(Icons.edit_note, size: 18),
                      selected: !document,
                      onSelected: (_) => _go(_View.input),
                    ),
                    ChoiceChip(
                      label: Text(_t('文档导入', 'Import document')),
                      avatar: const Icon(Icons.upload_file, size: 18),
                      selected: document,
                      onSelected: (_) => _go(_View.document),
                    ),
                  ],
                ),
                const SizedBox(height: 23),
                if (document)
                  _documentPicker()
                else ...[
                  Text(
                    _t(
                      '${_sourceName(project)}原文',
                      '${_sourceName(project)} source text',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 11),
                  TextField(
                    key: const ValueKey('source-input'),
                    controller: _input,
                    minLines: _compact ? 6 : 10,
                    maxLines: _compact ? 6 : 18,
                    onChanged: _parseText,
                    decoration: InputDecoration(
                      hintText: project.sourceLocale == 'en'
                          ? _t(
                              '在这里输入英文文案，例如：\n\nSign in\nWelcome to our product\nHello, {name}',
                              'Enter English text here, for example:\n\nSign in\nWelcome to our product\nHello, {name}',
                            )
                          : _t(
                              '在这里输入中文文案，例如：\n\n登录\n欢迎使用我们的产品\n你好，{name}',
                              'Enter Chinese text here, for example:\n\n登录\n欢迎使用我们的产品\n你好，{name}',
                            ),
                      alignLabelWithHint: true,
                      errorText: _inputError,
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _t('拆分方式', 'Split by'),
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                      ChoiceChip(
                        label: Text(_t('按行', 'Line')),
                        selected: _split == 'line',
                        onSelected: (_) {
                          _split = 'line';
                          _parseText(_input.text);
                        },
                      ),
                      ChoiceChip(
                        label: Text(_t('按空行段落', 'Paragraph')),
                        selected: _split == 'paragraph',
                        onSelected: (_) {
                          _split = 'paragraph';
                          _parseText(_input.text);
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                TextField(
                  controller: _prefix,
                  maxLength: 24,
                  decoration: InputDecoration(
                    labelText: _t('Key 前缀（选填）', 'Key prefix (optional)'),
                    hintText: 'auth → auth_login',
                    helperText: _compact
                        ? _t('可在校对时修改 Key。', 'You can edit keys during review.')
                        : _t(
                            '常见文案自动语义命名，自定义文案可在校对时修改。',
                            'Common strings get suggested keys. You can edit keys during review.',
                          ),
                    helperMaxLines: _compact ? 3 : 1,
                  ),
                ),
                const SizedBox(height: 15),
                _Notice(
                  _t(
                    '文档文件在本地解析。只有点击开始翻译后，选中的原文才会发送给翻译服务。',
                    'Documents are parsed on your device. Selected source text is sent to translation services only after you start translation.',
                  ),
                  icon: Icons.privacy_tip_outlined,
                ),
              ],
            ),
          ),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('内容预览', 'Content preview'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _Tag(
                      _t(
                        '${blocks.where((b) => b.selected).length} / ${blocks.length} 段',
                        '${blocks.where((b) => b.selected).length} / ${blocks.length} blocks',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    '勾选需要翻译的段落，点击内容可编辑。',
                    'Select the blocks to translate. Tap a block to edit it.',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 15),
                if (blocks.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.subject_rounded,
                            size: 37,
                            color: Color(0xFFB0C3AE),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            _t(
                              '添加内容后，段落会出现在这里',
                              'Your content will appear here',
                            ),
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          final all = blocks.every((b) => b.selected);
                          for (final block in blocks) {
                            block.selected = !all;
                          }
                        }),
                        child: Text(
                          blocks.every((b) => b.selected)
                              ? _t('取消全选', 'Deselect all')
                              : _t('全选', 'Select all'),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: blocks.where((b) => b.selected).length < 2
                            ? null
                            : _mergeBlocks,
                        icon: const Icon(Icons.merge_type, size: 17),
                        label: Text(_t('合并所选', 'Merge selected')),
                      ),
                      TextButton.icon(
                        onPressed: blocks.any((b) => b.selected)
                            ? _splitBlocks
                            : null,
                        icon: const Icon(Icons.call_split, size: 17),
                        label: Text(_t('按句拆分', 'Split sentences')),
                      ),
                    ],
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 520),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: blocks.length,
                      itemBuilder: (_, index) =>
                          _blockRow(blocks[index], index),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _footer(
          TextButton.icon(
            onPressed: () => _go(_View.project),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(_t('返回项目', 'Back to project')),
          ),
          FilledButton.icon(
            onPressed:
                _importing || blocks.every((b) => !b.selected) || blocks.isEmpty
                ? null
                : _commitBlocks,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(_t('下一步：选择语言', 'Next: choose languages')),
          ),
        ),
      ],
    );
  }

  void _parseText(String text) {
    try {
      final blocks = c.splitText(text, mode: _split);
      setState(() {
        _textBlocks = blocks;
        _inputError = null;
      });
    } catch (error) {
      setState(() {
        _textBlocks = [];
        _inputError = error.toString();
      });
      _notify(error.toString(), error: true);
    }
  }

  Widget _documentPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: _compact ? 16 : 24,
          vertical: _compact ? 20 : 36,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBF5),
          border: Border.all(color: const Color(0xFFCBDEC8)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.upload_file_outlined,
              size: _compact ? 32 : 43,
              color: _green,
            ),
            SizedBox(height: _compact ? 10 : 15),
            Text(
              _t('选择需要翻译的文档', 'Choose a document to translate'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: _compact ? 6 : 9),
            Text(
              _t(
                'TXT · Markdown · DOCX\n最大 10 MB，最多 1,000 个内容块',
                'TXT · Markdown · DOCX\nUp to 10 MB and 1,000 content blocks',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _muted, height: 1.9),
            ),
            SizedBox(height: _compact ? 12 : 20),
            FilledButton.icon(
              onPressed: _importing
                  ? null
                  : () => _guard(() async {
                      final generation = ++_importGeneration;
                      final projectId = c.currentProject?.id;
                      bool ownsImport() =>
                          mounted &&
                          generation == _importGeneration &&
                          c.currentProject?.id == projectId &&
                          _view == _View.document;
                      setState(() => _importing = true);
                      try {
                        final result = await c.pickDocument();
                        if (ownsImport() && result.isNotEmpty) {
                          setState(() => _documentBlocks = result);
                        }
                      } catch (_) {
                        if (ownsImport()) {
                          setState(() => _documentBlocks = []);
                          rethrow;
                        }
                      } finally {
                        if (ownsImport()) setState(() => _importing = false);
                      }
                    }),
              icon: _importing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(
                _importing
                    ? _t('正在解析…', 'Parsing…')
                    : _t('选择文件', 'Choose file'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      Text(
        _t(
          'Word 正文和表格会按内容块提取。暂不支持 PDF、图片扫描件和旧版 DOC，复杂排版不还原。',
          'Word paragraphs and tables are extracted as blocks. PDF, scanned images, and old DOC files are not supported.',
        ),
        style: const TextStyle(fontSize: 11, height: 1.8, color: _muted),
      ),
    ],
  );

  Widget _blockRow(DocumentBlock block, int index) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Checkbox(
            value: block.selected,
            onChanged: (value) =>
                setState(() => block.selected = value == true),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _editBlock(block),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    block.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => _editBlock(block),
          tooltip: _t('编辑段落', 'Edit block'),
          icon: const Icon(Icons.edit_outlined, size: 17, color: _muted),
        ),
      ],
    ),
  );

  Future<void> _editBlock(DocumentBlock block) async {
    final text = await _textDialog(
      _t('编辑段落', 'Edit block'),
      block.text,
      lines: 8,
    );
    if (text != null && text.trim().isNotEmpty && mounted) {
      setState(() => block.text = text.trim());
    }
  }

  void _mergeBlocks() {
    final selected = _blocks.where((b) => b.selected).toList();
    if (selected.length < 2) return;
    final first = _blocks.indexOf(selected.first);
    setState(() {
      _blocks.removeWhere((b) => b.selected);
      _blocks.insert(
        first,
        DocumentBlock(selected.map((b) => b.text).join('\n')),
      );
    });
  }

  void _splitBlocks() {
    final next = <DocumentBlock>[];
    for (final block in _blocks) {
      if (!block.selected) {
        next.add(block);
        continue;
      }
      final pieces = RegExp(r'[^。！？!?；;\n]+[。！？!?；;]?|\n')
          .allMatches(block.text)
          .map((match) => match.group(0)!.trim())
          .where((part) => part.isNotEmpty);
      next.addAll(
        pieces.map((piece) => DocumentBlock(piece, type: block.type)),
      );
    }
    if (next.length > 1000) {
      _notify('拆分后超过 1,000 个内容块，请减少内容。', error: true);
      return;
    }
    setState(() {
      if (_view == _View.document) {
        _documentBlocks = next;
      } else {
        _textBlocks = next;
      }
    });
  }

  void _commitBlocks() {
    try {
      final selected = _blocks.where((b) => b.selected).toList();
      if (selected.isEmpty) return;
      c.addBlocks(selected, prefix: _prefix.text.trim());
      _go(_View.languages);
    } catch (error) {
      _notify(error.toString(), error: true);
    }
  }

  Widget _languages() {
    final p = c.currentProject!;
    final plan = c.incrementalPlan();
    final selectedLocales = c.batchLocales;
    final availableLanguages = targetLanguagesFor(p.sourceLocale);
    final query = _languageSearch.trim().toLowerCase();
    final visibleLanguages = availableLanguages
        .where(
          (language) =>
              '${language.code} ${language.name} ${language.nativeName} ${_englishLanguageNames[language.code] ?? ''}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflow(
          1,
          _t('为你的内容，选择目的地', 'Choose target languages'),
          _t(
            '一次选择多种语言，每种语言使用相同的 Key。',
            'Choose several languages. Every pack will use the same keys.',
          ),
        ),
        _columns(
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('目标语言', 'Target languages'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: c.running
                          ? null
                          : () => c.setBatchLocales(
                              selectedLocales.length ==
                                      availableLanguages.length
                                  ? []
                                  : availableLanguages
                                        .map((l) => l.code)
                                        .toList(),
                            ),
                      child: Text(
                        selectedLocales.length == availableLanguages.length
                            ? _t('取消全选', 'Deselect all')
                            : _t('选择全部', 'Select all'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                _Notice(
                  _t(
                    '${_sourceName(p)} · 源语言，导出时可包含 ${p.sourceLocale}.json。另有 ${availableLanguages.length} 种目标语言可选。',
                    '${_sourceName(p)} is the source language. You can include ${p.sourceLocale}.json when exporting. ${availableLanguages.length} target languages are available.',
                  ),
                  icon: Icons.language,
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    'MyMemory 不支持巴西葡萄牙语、菲律宾语和书面挪威语，请为这些语言启用支持它们的平台。',
                    'MyMemory does not support Brazilian Portuguese, Filipino, or Norwegian Bokmål. Enable another provider for those languages.',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: _muted,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('language-search'),
                  initialValue: _languageSearch,
                  onChanged: (value) => setState(() => _languageSearch = value),
                  decoration: InputDecoration(
                    labelText: _t('搜索目标语言', 'Search target languages'),
                    hintText: _t('中文名、原生名称或语言代码', 'Name or language code'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _t(
                        '已选 ${selectedLocales.length} / ${availableLanguages.length} 种',
                        '${selectedLocales.length} / ${availableLanguages.length} selected',
                      ),
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    if (query.isNotEmpty && visibleLanguages.isNotEmpty)
                      TextButton(
                        onPressed: c.running
                            ? null
                            : () => c.setBatchLocales([
                                ...selectedLocales,
                                ...visibleLanguages.map(
                                  (language) => language.code,
                                ),
                              ]),
                        child: Text(_t('选择搜索结果', 'Select results')),
                      ),
                  ],
                ),
                if (visibleLanguages.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(_t('没有匹配的目标语言', 'No matching languages')),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 480),
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final count = constraints.maxWidth > 440 ? 2 : 1;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: visibleLanguages.map((language) {
                            final selected = selectedLocales.contains(
                              language.code,
                            );
                            return SizedBox(
                              width:
                                  (constraints.maxWidth - (count - 1) * 12) /
                                  count,
                              child: InkWell(
                                onTap: c.running
                                    ? null
                                    : () {
                                        final locales = [...selectedLocales];
                                        if (selected) {
                                          locales.remove(language.code);
                                        } else {
                                          locales.add(language.code);
                                        }
                                        c.setBatchLocales(locales);
                                      },
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFFEEF6E9)
                                        : Colors.white,
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF9ABC9D)
                                          : _line,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? const Color(0xFFDFEDD9)
                                              : _canvas,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          language.badge,
                                          style: const TextStyle(
                                            color: _green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _languageLabel(language),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              language.nativeName,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: _muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked,
                                        color: selected
                                            ? _green
                                            : const Color(0xFFC9D7C8),
                                        size: 21,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('本次翻译', 'This translation'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                _summary(
                  _t('源文案', 'Source strings'),
                  _t(
                    '${p.selectedEntries.length} 条',
                    '${p.selectedEntries.length} ${p.selectedEntries.length == 1 ? 'string' : 'strings'}',
                  ),
                ),
                _summary(
                  _t('目标语言', 'Target languages'),
                  _t(
                    '${selectedLocales.length} 种',
                    '${selectedLocales.length} languages',
                  ),
                ),
                const Divider(height: 30),
                Text(
                  _t('需要新增翻译', 'New translations needed'),
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 10),
                Text(
                  _t(
                    '${plan.uniquePending} 组原文与语言',
                    '${plan.uniquePending} source/language pairs',
                  ),
                  style: const TextStyle(
                    fontSize: 29,
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _summary(
                  _t('保留已有结果', 'Keep existing results'),
                  '${plan.retained}',
                ),
                _summary(
                  _t('复用项目译文', 'Reuse project translations'),
                  '${plan.reusable}',
                ),
                _summary(
                  _t('本批重复文案', 'Repeated strings'),
                  '${plan.pending - plan.uniquePending}',
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: selectedLocales
                      .map((code) => _Tag(_localeLabel(code)))
                      .toList(),
                ),
                const SizedBox(height: 25),
                _Notice(
                  _t(
                    '仅新增或变化且没有可复用译文的原文会发送；同批相同内容合并处理。本次${c.settings.providerFallback ? '启用顺序：${c.settings.providerOrder.join(' → ')}；仅额度耗尽或语言不支持时切换。' : '只使用首选平台 ${c.settings.providerOrder.first}，自动备用已关闭。'}',
                    'Only new or changed source text without reusable translations is sent. Duplicate content is combined. ${c.settings.providerFallback ? 'Provider order: ${c.settings.providerOrder.join(' → ')}.' : 'Only ${c.settings.providerOrder.first} is used; fallback is off.'}',
                  ),
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 14),
                Text(
                  _t(
                    '长段落自动拆分后合并；人工修改、已确认内容和已有成功结果会受到保护。',
                    'Long paragraphs are split and rejoined automatically. Edits, reviewed content, and completed translations are preserved.',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: _muted,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 23),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        selectedLocales.isEmpty ||
                            p.selectedEntries.isEmpty ||
                            c.running
                        ? null
                        : _startTranslation,
                    icon: const Icon(Icons.translate, size: 18),
                    label: Text(_t('开始增量翻译', 'Start translation')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => _go(_View.project),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: Text(_t('返回项目', 'Back to project')),
        ),
      ],
    );
  }

  Widget _summary(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  void _startTranslation({bool retry = false, bool resume = false}) {
    _go(_View.progress);
    _guard(() => c.startTranslation(retryFailedOnly: retry, resume: resume));
  }

  Widget _progress() {
    final ratio = c.total == 0 ? 0.0 : c.completed / c.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflow(
          2,
          _t('让每一句话，拥有更多可能', 'Translating your content'),
          _t(
            '翻译结果逐条保存，可以随时暂停，再继续。',
            'Results are saved as they arrive. Pause and resume whenever you need.',
          ),
        ),
        _Panel(
          child: Column(
            children: [
              const SizedBox(height: 15),
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F2E1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  c.running
                      ? Icons.translate
                      : c.paused
                      ? Icons.pause_rounded
                      : Icons.task_alt_rounded,
                  color: _green,
                  size: 39,
                ),
              ),
              const SizedBox(height: 23),
              Text(
                c.running
                    ? _t('正在连接世界的语言', 'Translation in progress')
                    : c.paused
                    ? _t('翻译已暂停', 'Translation paused')
                    : c.failed > 0
                    ? _t('部分内容需要再试一次', 'Some items need another try')
                    : _t('译文已准备好', 'Translations are ready'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 11),
              Text(
                c.running
                    ? c.activeLabel
                    : c.paused
                    ? _t(
                        '已完成的结果已保留，恢复后继续处理未完成项。',
                        'Completed results are saved. Resume to finish pending items.',
                      )
                    : _t('接下来，花一点时间校对你的译文。', 'Next, review your translations.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 27),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: const Color(0xFFEDF3E9),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _t(
                              '${c.completed} / ${c.total} 已处理 · 复用 ${c.reused} 条',
                              '${c.completed} / ${c.total} processed · ${c.reused} reused',
                            ),
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(100 * ratio).round()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    for (final locale in c.activeBatchLocales)
                      _localeProgress(locale),
                  ],
                ),
              ),
              const SizedBox(height: 27),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (c.running)
                    OutlinedButton.icon(
                      onPressed: c.pauseTranslation,
                      icon: const Icon(Icons.pause, size: 18),
                      label: Text(_t('暂停翻译', 'Pause translation')),
                    ),
                  if (!c.running && c.paused)
                    FilledButton.icon(
                      onPressed: () => _startTranslation(resume: true),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text(_t('继续翻译', 'Resume translation')),
                    ),
                  if (!c.running && c.failed > 0)
                    OutlinedButton.icon(
                      onPressed: () => _startTranslation(retry: true),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(
                        _t('重试失败项 (${c.failed})', 'Retry failed (${c.failed})'),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () {
                      _reviewIndex = 0;
                      _go(_View.review);
                    },
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(_t('进入翻译校对', 'Review translations')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        if (c.error != null) ...[
          const SizedBox(height: 18),
          _Notice(
            _localizeError(c.error!),
            icon: Icons.error_outline,
            warm: true,
          ),
        ],
        const SizedBox(height: 20),
        _Notice(
          _t(
            '额度耗尽或语言不支持时，可按设置尝试后续平台；鉴权或配置错误会停止。成功译文逐条保存，来源会显示在校对页。',
            'When a provider runs out of quota or lacks a language, the next enabled provider may be tried. Authentication and configuration errors stop the task. Successful translations are saved individually.',
          ),
          icon: Icons.shield_outlined,
        ),
      ],
    );
  }

  Widget _localeProgress(String locale) {
    final entries = _entries;
    final done = entries
        .where((e) => e.translations[locale]?.text.trim().isNotEmpty == true)
        .length;
    final errors = entries
        .where(
          (e) => e.translations[locale]?.status == TranslationStatus.failed,
        )
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              _localeLabel(locale),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: entries.isEmpty ? 0 : done / entries.length,
                minHeight: 4,
                backgroundColor: const Color(0xFFEDF3E9),
              ),
            ),
          ),
          const SizedBox(width: 15),
          SizedBox(
            width: 80,
            child: Text(
              errors > 0
                  ? _t('$done 完成 · $errors 失败', '$done done · $errors failed')
                  : '$done / ${entries.length}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                color: errors > 0 ? const Color(0xFFA7803C) : _muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _review() {
    final p = c.currentProject!;
    final entries = _entries;
    if (entries.isEmpty) {
      return _Empty(
        icon: Icons.fact_check_outlined,
        title: _t('还没有待校对的文案', 'No strings to review'),
        detail: _t(
          '先为项目添加内容，或在项目列表中勾选文案。',
          'Add content or select strings in the project.',
        ),
        action: OutlinedButton(
          onPressed: () => _go(_View.project),
          child: Text(_t('返回项目', 'Back to project')),
        ),
      );
    }
    if (p.locales.isEmpty) {
      return _Empty(
        icon: Icons.public_rounded,
        title: _t('先选择目标语言', 'Choose target languages first'),
        detail: _t(
          '选择语言后就可以逐条翻译与校对。',
          'Then you can translate and review each string.',
        ),
        action: FilledButton(
          onPressed: () => _go(_View.languages),
          child: Text(_t('选择语言', 'Choose languages')),
        ),
      );
    }
    _reviewIndex = _reviewIndex.clamp(0, entries.length - 1);
    if (!p.locales.contains(_locale)) _locale = p.locales.first;
    final entry = entries[_reviewIndex];
    final value = entry.translations[_locale] ?? TranslationValue();
    final issues = c.validate();
    final ownIssues = issues
        .where(
          (issue) =>
              issue.entryId == entry.id &&
              (issue.locale == null || issue.locale == _locale),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflow(
          2,
          _t('好译文，值得再看一眼', 'Review each translation'),
          _t(
            '逐条校对，让每一种语言都准确表达你的意思。',
            'Check each string so every language says what you mean.',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: p.locales
              .map(
                (code) => ChoiceChip(
                  key: ValueKey('review-locale-$code'),
                  showCheckmark: false,
                  label: Text(_localeLabel(code)),
                  selected: code == _locale,
                  onSelected: (_) => setState(() => _locale = code),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        _columns(
          _Panel(
            padding: const EdgeInsets.all(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (_, index) {
                  final item = entries[index];
                  final selected = index == _reviewIndex;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Material(
                      color: selected
                          ? const Color(0xFFEAF4E7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: ListTile(
                        selected: selected,
                        selectedColor: _green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        onTap: () => setState(() => _reviewIndex = index),
                        title: Text(
                          item.source,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.6),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            item.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: _muted,
                            ),
                          ),
                        ),
                        trailing: Icon(
                          item.translations[_locale]?.reviewed == true
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 16,
                          color: item.translations[_locale]?.reviewed == true
                              ? _green
                              : const Color(0xFFB8C9B4),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_reviewIndex + 1}'.padLeft(2, '0'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: _muted,
                      ),
                    ),
                    Text(
                      '${_sourceName(p)} →',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      _localeLabel(_locale),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _Tag(
                      _translationLabel(value),
                      warm: value.status == TranslationStatus.failed,
                    ),
                  ],
                ),
                const SizedBox(height: 23),
                Text(
                  _t('${_sourceName(p)}原文', '${_sourceName(p)} source'),
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F7F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    entry.source,
                    style: const TextStyle(fontSize: 15, height: 1.9),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _editEntrySource(entry),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: Text(
                      _t('编辑原文', 'Edit source'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                TextFormField(
                  key: ValueKey('key-${entry.id}'),
                  initialValue: entry.key,
                  decoration: InputDecoration(
                    labelText: _t('资源 Key', 'Resource key'),
                    prefixIcon: const Icon(Icons.key_outlined, size: 18),
                    helperText: _t(
                      '小写英文、数字和下划线；以字母开头。',
                      'Start with a letter; use lowercase letters, numbers, and underscores.',
                    ),
                  ),
                  onChanged: (text) => c.updateEntryKey(entry, text),
                ),
                const SizedBox(height: 21),
                _TranslationEditor(
                  key: ValueKey('translation-${entry.id}-$_locale'),
                  text: value.text,
                  label: _t(
                    '${languageName(_locale)}译文',
                    '${_localeLabel(_locale)} translation',
                  ),
                  onChanged: (text) => c.editTranslation(entry, _locale, text),
                ),
                const SizedBox(height: 13),
                if (value.error.isNotEmpty) ...[
                  _Notice(
                    _localizeError(value.error),
                    icon: Icons.error_outline,
                    warm: true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (ownIssues.isNotEmpty) ...[
                  _Notice(
                    ownIssues
                        .map((issue) => _localizeError(issue.message))
                        .join('\n'),
                    icon: Icons.rule_rounded,
                    warm: true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_compact)
                  _mobileReviewActions(entry, value)
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: value.reviewed,
                            onChanged: value.text.trim().isEmpty
                                ? null
                                : (checked) => c.reviewTranslation(
                                    entry,
                                    _locale,
                                    checked == true,
                                  ),
                          ),
                          InkWell(
                            onTap: value.text.trim().isEmpty
                                ? null
                                : () => c.reviewTranslation(
                                    entry,
                                    _locale,
                                    !value.reviewed,
                                  ),
                            child: Text(
                              _t('已人工校对确认', 'Reviewed and confirmed'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: c.running
                            ? null
                            : () => _retranslate(entry, value),
                        icon: const Icon(Icons.refresh, size: 17),
                        label: Text(_t('重新翻译', 'Translate again')),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                const Divider(),
                _reviewEntryNavigation(entries.length),
              ],
            ),
          ),
          leftFlex: 1,
          rightFlex: 2,
        ),
        const SizedBox(height: 19),
        InkWell(
          onTap: _showIssues,
          borderRadius: BorderRadius.circular(12),
          child: _Notice(
            issues.isEmpty
                ? _t(
                    '完整性检查通过：Key 唯一、译文齐全、占位符一致。语义准确性仍需人工检查。',
                    'Integrity check passed: keys are unique, translations are present, and placeholders match. Review meaning manually.',
                  )
                : _t(
                    '发现 ${issues.length} 项完整性问题，点击查看。补齐译文与占位符后即可正式导出。',
                    '${issues.length} integrity issues found. Tap to review before export.',
                  ),
            icon: issues.isEmpty ? Icons.verified_outlined : Icons.rule_rounded,
            warm: issues.isNotEmpty,
          ),
        ),
        const SizedBox(height: 24),
        _footer(
          TextButton.icon(
            onPressed: () => _go(_View.project),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(_t('返回项目', 'Back to project')),
          ),
          FilledButton.icon(
            onPressed: () {
              _draft = false;
              _go(_View.export);
            },
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(_t('下一步：导出语言包', 'Next: export language packs')),
          ),
        ),
      ],
    );
  }

  Widget _mobileReviewActions(Entry entry, TranslationValue value) {
    final canConfirm = value.text.trim().isNotEmpty;
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Row(
      key: const ValueKey('review-action-bar'),
      children: [
        Expanded(
          child: MergeSemantics(
            child: Semantics(
              checked: value.reviewed,
              child: OutlinedButton(
                key: const ValueKey('review-confirmation-toggle'),
                onPressed: canConfirm
                    ? () => c.reviewTranslation(entry, _locale, !value.reviewed)
                    : null,
                style: style.copyWith(
                  backgroundColor: WidgetStatePropertyAll(
                    value.reviewed
                        ? const Color(0xFFE0F1E6)
                        : const Color(0xFFF5F8F4),
                  ),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: value.reviewed ? _green : _line),
                  ),
                ),
                child: Text(
                  value.reviewed
                      ? _t('已确认', 'Confirmed')
                      : _t('确认译文', 'Confirm'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('review-retranslate'),
            onPressed: c.running ? null : () => _retranslate(entry, value),
            style: style,
            child: Text(_t('重新翻译', 'Retranslate'), textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }

  Widget _reviewEntryNavigation(int count) {
    final buttonStyle = _compact
        ? TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: const TextStyle(fontSize: 13),
          )
        : null;
    final previous = TextButton.icon(
      key: const ValueKey('review-entry-previous'),
      style: buttonStyle,
      onPressed: _reviewIndex == 0
          ? null
          : () => setState(() => _reviewIndex--),
      icon: Icon(Icons.chevron_left, size: _compact ? 18 : null),
      label: Text(_t('上一条', 'Previous')),
    );
    final next = TextButton.icon(
      key: const ValueKey('review-entry-next'),
      style: buttonStyle,
      onPressed: _reviewIndex == count - 1
          ? null
          : () => setState(() => _reviewIndex++),
      icon: Icon(Icons.chevron_right, size: _compact ? 18 : null),
      label: Text(_t('下一条', 'Next')),
    );
    if (!_compact) return _footer(previous, next);
    return Row(
      key: const ValueKey('review-entry-navigation'),
      children: [
        Expanded(child: previous),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '${_reviewIndex + 1} / $count',
            key: const ValueKey('review-entry-counter'),
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        Expanded(child: next),
      ],
    );
  }

  String _translationLabel(TranslationValue value) {
    if (value.reviewed) return _t('已人工确认', 'Confirmed');
    if (value.edited) return _t('人工编辑 · 待确认', 'Edited · review needed');
    if (value.status == TranslationStatus.failed) {
      return _t('翻译失败', 'Translation failed');
    }
    if (value.status == TranslationStatus.translating) {
      return _t('翻译中', 'Translating');
    }
    if (value.text.trim().isEmpty) return _t('待翻译', 'Pending');
    return '${value.provider.isEmpty ? _t('译文', 'Translation') : value.provider} · ${_t('待校对', 'Review needed')}';
  }

  Future<void> _retranslate(Entry entry, TranslationValue value) async {
    if (value.edited || value.reviewed) {
      final yes = await showAdaptiveConfirmation(
        context: context,
        compact: _compact,
        title: _t('替换人工校对过的译文？', 'Replace the reviewed translation?'),
        message: _t(
          '原文将重新发送给翻译服务。新译文成功返回后替换当前内容，失败时保留现有译文。',
          'The source will be sent again. A successful result replaces the current translation; a failed request keeps it.',
        ),
        cancelLabel: _t('取消', 'Cancel'),
        confirmLabel: _t('重新翻译并替换', 'Translate and replace'),
        destructive: true,
      );
      if (yes != true || !mounted) return;
    }
    await _guard(
      () => c.startTranslation(
        entryId: entry.id,
        locale: _locale,
        overwrite: true,
      ),
    );
  }

  Future<void> _editEntrySource(Entry entry) async {
    final text = await _textDialog(
      _t(
        '编辑${_sourceName(c.currentProject!)}原文',
        'Edit ${_sourceName(c.currentProject!)} source',
      ),
      entry.source,
      lines: 7,
      helper: _t(
        '修改原文后，旧译文会失效，需要重新翻译或校对。',
        'Changing the source invalidates old translations. Translate or review them again.',
      ),
    );
    if (text != null && text.trim().isNotEmpty) {
      c.updateEntrySource(entry, text.trim());
    }
  }

  Future<String?> _textDialog(
    String title,
    String initial, {
    int lines = 4,
    String? helper,
    bool allowEmpty = false,
  }) async {
    final text = TextEditingController(text: initial);
    final form = GlobalKey<FormState>();
    final result = await _formModal<String>(
      (context) => _formFrame(
        context,
        title: title,
        doneLabel: _t('保存', 'Save'),
        onDone: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, text.text);
          }
        },
        child: Form(
          key: form,
          child: TextFormField(
            controller: text,
            autofocus: true,
            minLines: lines,
            maxLines: 14,
            validator: (value) =>
                !allowEmpty && (value == null || value.trim().isEmpty)
                ? _t('请输入内容', 'Enter some text')
                : null,
            decoration: InputDecoration(helperText: helper, helperMaxLines: 3),
          ),
        ),
      ),
    );
    text.dispose();
    return result;
  }

  void _showIssues() {
    final issues = c.validate();
    final title = _t('语言包完整性检查', 'Language pack integrity check');
    final content = SizedBox(
      width: 520,
      child: issues.isEmpty
          ? Text(
              _t(
                'Key 唯一、译文齐全、占位符一致。翻译的语义准确性仍需人工检查。',
                'Keys are unique, translations are complete, and placeholders match. Meaning still needs human review.',
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: issues.length,
                separatorBuilder: (_, index) => const Divider(),
                itemBuilder: (_, index) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.error_outline,
                    color: Color(0xFFA8803D),
                    size: 20,
                  ),
                  title: Text(
                    _localizeError(issues[index].message),
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: issues[index].locale == null
                      ? null
                      : Text(_localeLabel(issues[index].locale!)),
                ),
              ),
            ),
    );
    if (_compact) {
      _formModal<void>(
        (context) => IosFormSheet(
          title: title,
          cancelLabel: _t('取消', 'Cancel'),
          doneLabel: _t('知道了', 'OK'),
          showCancel: false,
          onDone: () => Navigator.pop(context),
          child: content,
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('知道了', 'OK')),
          ),
        ],
      ),
    );
  }

  Widget _export() {
    final p = c.currentProject!;
    final issues = c.validate();
    Map<String, String> files = {};
    String? previewError;
    try {
      files = c.previewPackages(draft: _draft);
    } catch (error) {
      previewError = error.toString();
    }
    final names = files.keys.where((name) => name.endsWith('.json')).toList();
    if (!names.contains(_previewFile)) {
      _previewFile = names.isEmpty ? '' : names.first;
    }
    final preview = files[_previewFile] ?? '';
    final canExport =
        !c.running &&
        !_saving &&
        files.isNotEmpty &&
        (_draft || issues.isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflow(
          3,
          _t('把语言，带到你的产品中', 'Bring languages into your product'),
          _t(
            '每种语言独立成包，所有文案使用相同的 Key。',
            'Export one pack per language with the same keys.',
          ),
          back: () => _go(_View.review),
        ),
        _columns(
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('准备导出的语言包', 'Language packs ready to export'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                for (final name in names)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _line)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.data_object, size: 22, color: _green),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  '${_entries.length} 个 Key · ${utf8.encode(files[name]!).length} 字节',
                                  '${_entries.length} keys · ${utf8.encode(files[name]!).length} bytes',
                                ),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: _green,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 17),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _t(
                      '包含${_sourceName(p)}源语言包',
                      'Include ${_sourceName(p)} source pack',
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    _t(
                      '一并导出 ${p.sourceLocale}.json',
                      'Also export ${p.sourceLocale}.json',
                    ),
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                  value: c.settings.includeSource,
                  onChanged: c.running
                      ? null
                      : (value) => _guard(
                          () => c.saveSettings(
                            email: c.settings.email,
                            apiBaseUrl: c.settings.apiBaseUrl,
                            includeSource: value,
                          ),
                        ),
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _t('导出草稿', 'Export draft'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    _t(
                      '允许缺失译文，ZIP 内附完整性报告',
                      'Allow missing translations and include an integrity report in the ZIP',
                    ),
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                  value: _draft,
                  onChanged: (value) => setState(() => _draft = value),
                ),
                const SizedBox(height: 15),
                if (previewError != null)
                  _Notice(
                    _localizeError(previewError),
                    icon: Icons.error_outline,
                    warm: true,
                  )
                else
                  InkWell(
                    onTap: _showIssues,
                    child: _Notice(
                      issues.isEmpty
                          ? _t(
                              '完整性检查通过，可以正式导出。',
                              'Integrity check passed. Ready to export.',
                            )
                          : _t(
                              '还有 ${issues.length} 项待处理问题。可返回校对，或导出带报告的草稿 ZIP。',
                              '${issues.length} issues remain. Return to review or export a draft ZIP with a report.',
                            ),
                      icon: issues.isEmpty
                          ? Icons.verified_outlined
                          : Icons.rule_rounded,
                      warm: issues.isNotEmpty,
                    ),
                  ),
                const SizedBox(height: 18),
                const Text(
                  '格式：UTF-8 · JSON · 2 空格缩进\n命名：snake_case · 按 Key 排序',
                  style: TextStyle(fontSize: 11, color: _muted, height: 1.9),
                ),
              ],
            ),
          ),
          Column(
            children: [
              _Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 19,
                        vertical: 13,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF0F5EC),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.code_rounded,
                            size: 20,
                            color: _green,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _t('JSON 预览', 'JSON preview'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          if (names.isNotEmpty)
                            Flexible(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _previewFile,
                                underline: const SizedBox.shrink(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _green,
                                  fontFamily: 'monospace',
                                ),
                                items: names
                                    .map(
                                      (name) => DropdownMenuItem(
                                        value: name,
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (name) =>
                                    setState(() => _previewFile = name!),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 270,
                        maxHeight: 420,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(23),
                        child: SelectableText(
                          preview.isEmpty
                              ? _t(
                                  '// 语言包预览将在这里显示',
                                  '// Language pack preview will appear here',
                                )
                              : preview,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.9,
                            color: Color(0xFF4F785C),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t(
                                '${utf8.encode(preview).length} 字节 · UTF-8',
                                '${utf8.encode(preview).length} bytes · UTF-8',
                              ),
                              style: const TextStyle(
                                fontSize: 10,
                                color: _muted,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: preview.isEmpty
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: preview),
                                    );
                                    _notify(_t('JSON 已复制', 'JSON copied'));
                                  },
                            icon: const Icon(Icons.copy_outlined, size: 15),
                            label: Text(
                              _t('复制', 'Copy'),
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _Panel(
                color: const Color(0xFFECF5E7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t('你的语言包，已井然有序', 'Your language packs are ready'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _t(
                        '${p.name} · ${_entries.length} 个 Key · ${p.locales.length} 种目标语言',
                        '${p.name} · ${_entries.length} keys · ${p.locales.length} target languages',
                      ),
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(height: 19),
                    FilledButton.icon(
                      onPressed: canExport
                          ? () => _saveExport(() => c.exportZip(draft: _draft))
                          : null,
                      icon: const Icon(Icons.folder_zip_outlined, size: 19),
                      label: Text(
                        _saving
                            ? _t('正在保存…', 'Saving…')
                            : _draft
                            ? _t('保存草稿语言包 .zip', 'Save draft .zip')
                            : _t('保存全部语言包 .zip', 'Save all packs .zip'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: canExport && !_draft && _previewFile.isNotEmpty
                          ? () => _saveExport(
                              () => c.exportJson(
                                _previewFile.replaceAll('.json', ''),
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: Text(_t('保存当前 JSON', 'Save current JSON')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _footer(
          TextButton.icon(
            onPressed: () => _go(_View.review),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(_t('返回校对', 'Back to review')),
          ),
          TextButton.icon(
            onPressed: () => _go(_View.exports),
            icon: const Icon(Icons.history, size: 18),
            label: Text(_t('查看导出记录', 'View exports')),
          ),
        ),
      ],
    );
  }

  Future<void> _saveExport(Future<bool> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
    } catch (error) {
      _notify(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tasks() {
    final projects = c.projects.where((p) => p.entries.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          eyebrow: 'TRANSLATION TASKS',
          title: _t('翻译任务', 'Translation tasks'),
          subtitle: _t(
            '每一种语言的进度、失败与重试，都有迹可循。',
            'Track progress, failures, and retries for each language.',
          ),
          action: FilledButton.icon(
            onPressed: () => _beginInput(false),
            icon: const Icon(Icons.add, size: 18),
            label: Text(_t('新建翻译', 'New translation')),
          ),
        ),
        const SizedBox(height: 25),
        if (c.total > 0) ...[
          _Panel(
            color: const Color(0xFFEBF4E7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.translate, color: _green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.running
                            ? _t('翻译进行中', 'Translation in progress')
                            : c.paused
                            ? _t('已暂停的任务', 'Paused task')
                            : c.failed > 0
                            ? _t('最近任务 · 部分失败', 'Recent task · some failed')
                            : _t('最近任务 · 已完成', 'Recent task · complete'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (c.activeProjectId != null &&
                        c.projects.any(
                          (project) => project.id == c.activeProjectId,
                        ))
                      TextButton(
                        onPressed: _openActiveProgress,
                        child: Text(_t('查看任务', 'View task')),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: (c.completed / c.total).clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFFDCE9D8),
                  minHeight: 5,
                ),
                const SizedBox(height: 13),
                Text(
                  _t(
                    '已处理 ${c.completed}/${c.total} · 失败 ${c.failed}',
                    '${c.completed}/${c.total} processed · ${c.failed} failed',
                  ),
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 23),
        ],
        if (projects.isEmpty)
          _Panel(
            child: _Empty(
              icon: Icons.translate_rounded,
              title: _t('从一段原文开始', 'Start with some source text'),
              detail: _t(
                '添加项目文案、选择目标语言，然后开始第一次真实翻译。',
                'Add strings, choose target languages, and start translating.',
              ),
              action: OutlinedButton(
                onPressed: () => _beginInput(false),
                child: Text(_t('开始翻译', 'Start translating')),
              ),
            ),
          )
        else
          _Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: projects
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.all(21),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.language_rounded,
                            size: 28,
                            color: _green,
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  _t(
                                    '${p.entries.length} 条文案 · ${p.locales.length} 种语言 · 已有 ${p.translatedCount}/${p.totalCount} 条译文',
                                    '${p.entries.length} strings · ${p.locales.length} languages · ${p.translatedCount}/${p.totalCount} translations',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _muted,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () {
                              c.openProject(p.id);
                              _go(_View.project);
                            },
                            child: Text(_t('查看项目', 'View project')),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 26),
        _taskHistory(),
      ],
    );
  }

  Widget _taskHistory() {
    final records = <(Project, TaskRecord)>[
      for (final project in c.projects)
        for (final record in project.jobs) (project, record),
    ]..sort((a, b) => b.$2.createdAt.compareTo(a.$2.createdAt));
    if (records.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('任务记录', 'Task history'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 15),
        _Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final pair in records.take(40))
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _line)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        pair.$2.status == 'completed' && pair.$2.failed == 0
                            ? Icons.task_alt_rounded
                            : Icons.history_rounded,
                        color: _green,
                        size: 25,
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pair.$1.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _t(
                                '${_taskStatus(pair.$2)} · 已处理 ${pair.$2.completed}/${pair.$2.total} · 复用 ${pair.$2.reused} · 失败 ${pair.$2.failed}',
                                '${_taskStatus(pair.$2)} · ${pair.$2.completed}/${pair.$2.total} processed · ${pair.$2.reused} reused · ${pair.$2.failed} failed',
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                                height: 1.8,
                              ),
                            ),
                            Text(
                              '${pair.$2.provider.isEmpty ? _t('翻译服务', 'Provider') : pair.$2.provider} · ${_date(pair.$2.createdAt)}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          c.openProject(pair.$1.id);
                          _go(_View.project);
                        },
                        child: Text(_t('查看文案', 'View strings')),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _taskStatus(TaskRecord record) => switch (record.status) {
    'running' => _t('翻译中', 'Translating'),
    'paused' => _t('已暂停', 'Paused'),
    'stopped' => _t('已停止', 'Stopped'),
    _ => record.failed > 0 ? _t('部分失败', 'Some failed') : _t('已完成', 'Completed'),
  };

  Widget _exports() {
    final records = <(Project, ExportRecord)>[];
    for (final project in c.projects) {
      for (final record in project.exports) {
        records.add((project, record));
      }
    }
    records.sort((a, b) => b.$2.createdAt.compareTo(a.$2.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          eyebrow: 'EXPORT HISTORY',
          title: _t('导出记录', 'Exports'),
          subtitle: _t(
            '每一次交付，都可以重新获取。保留最近的语言包快照。',
            'Save recent language pack snapshots again whenever you need.',
          ),
        ),
        const SizedBox(height: 25),
        if (records.isEmpty)
          _Panel(
            child: _Empty(
              icon: Icons.folder_zip_outlined,
              title: _t('语言包准备好时，就来这里', 'Your exports will appear here'),
              detail: _t(
                '完成翻译校对并保存后，语言包快照会出现在这里。',
                'Review and save a language pack to create a snapshot.',
              ),
              action: OutlinedButton(
                onPressed: () => _go(_View.home),
                child: Text(_t('返回我的项目', 'Back to projects')),
              ),
            ),
          )
        else
          _Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: records.map((pair) {
                final project = pair.$1;
                final record = pair.$2;
                return Container(
                  padding: const EdgeInsets.all(21),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _line)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF0F4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.data_object_rounded,
                          color: Color(0xFF648C9C),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              _t(
                                '${project.name} · ${record.files.length} 个文件 · ${record.draft ? '草稿' : '正式'} · ${_date(record.createdAt)}',
                                '${project.name} · ${record.files.length} files · ${record.draft ? 'Draft' : 'Final'} · ${_date(record.createdAt)}',
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => _saveExport(() => c.downloadRecord(record)),
                        tooltip: _t('重新保存语言包', 'Save language pack again'),
                        icon: const Icon(
                          Icons.file_download_outlined,
                          color: _green,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _providerSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_compact)
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            final provider = await _mobileActions(
              _t('首选翻译平台', 'Preferred provider'),
              {for (final provider in translationProviders) provider: provider},
            );
            if (provider == null || !mounted) return;
            await _guard(
              () => c.saveProviderOrder([
                provider,
                ...c.settings.providerOrder.where((value) => value != provider),
              ]),
            );
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _t('首选翻译平台', 'Preferred provider'),
            ),
            child: Row(
              children: [
                Expanded(child: Text(c.settings.providerOrder.first)),
                const Icon(CupertinoIcons.chevron_down, size: 16),
              ],
            ),
          ),
        )
      else
        DropdownButtonFormField<String>(
          key: ValueKey('primary-${c.settings.providerOrder.first}'),
          initialValue: c.settings.providerOrder.first,
          decoration: InputDecoration(
            labelText: _t('首选翻译平台', 'Preferred provider'),
          ),
          items: translationProviders
              .map(
                (provider) =>
                    DropdownMenuItem(value: provider, child: Text(provider)),
              )
              .toList(),
          onChanged: (provider) {
            if (provider == null) return;
            _guard(
              () => c.saveProviderOrder([
                provider,
                ...c.settings.providerOrder.where((value) => value != provider),
              ]),
            );
          },
        ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          _t('启用按顺序备用', 'Enable ordered fallback'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          _t(
            '仅额度耗尽或语言不支持时切换；鉴权和配置错误会停止。',
            'Switch only when quota is exhausted or a language is unsupported. Authentication and configuration errors stop the task.',
          ),
          style: const TextStyle(fontSize: 11),
        ),
        value: c.settings.providerFallback,
        onChanged: (value) => _guard(
          () => c.saveProviderOrder(c.settings.providerOrder, fallback: value),
        ),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < translationProviders.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        _providerRow(translationProviders[i]),
      ],
    ],
  );

  Future<void> _openSettingsDetail(String title, WidgetBuilder builder) =>
      Navigator.of(context).push<void>(
        CupertinoPageRoute<void>(
          builder: (_) => SettingsDetailPage(
            title: title,
            english: _en,
            listenable: c,
            builder: builder,
          ),
        ),
      );

  String _providerStatus(String provider) {
    final credentials = c.credentialsFor(provider);
    if (provider == 'MyMemory' && credentials.isEmpty) {
      return _t('可匿名使用', 'Anonymous');
    }
    if (!providerCredentialsReady(provider, credentials)) {
      return credentials.isEmpty
          ? _t('未配置', 'Not configured')
          : _t('待完善', 'Incomplete');
    }
    final status = c.credentialValidationFor(provider).status;
    return switch (status) {
      'checking' => _t('验证中…', 'Checking…'),
      'valid' => _t('已验证', 'Verified'),
      'invalid' => _t('验证未通过', 'Check failed'),
      _ => _t('已配置', 'Configured'),
    };
  }

  Widget _providerRow(String provider) {
    final order = c.settings.providerOrder;
    final validation = c.credentialValidationFor(provider);
    final status = Text(
      _providerStatus(provider),
      key: ValueKey('provider-summary-$provider'),
      style: TextStyle(
        fontSize: 12,
        color: validation.status == 'invalid'
            ? const Color(0xFF9B4B39)
            : validation.status == 'valid'
            ? _green
            : _muted,
      ),
    );
    final name = Text(
      provider,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
    return Row(
      children: [
        Semantics(
          label: _t('启用 $provider', 'Enable $provider'),
          child: Checkbox(
            key: ValueKey('provider-enable-$provider'),
            value: order.contains(provider),
            onChanged: (enabled) => _guard(
              () => c.saveProviderOrder(
                enabled == true
                    ? [...order, provider]
                    : order.where((value) => value != provider).toList(),
              ),
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            button: true,
            child: InkWell(
              key: ValueKey('provider-details-$provider'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openSettingsDetail(
                provider,
                (_) => _providerDetail(provider),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 220 ||
                                MediaQuery.textScalerOf(context).scale(1) >
                                    1.2) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  name,
                                  const SizedBox(height: 4),
                                  status,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: name),
                                const SizedBox(width: 8),
                                status,
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        CupertinoIcons.chevron_forward,
                        size: 16,
                        color: _muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _myMemorySettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: ValueKey('email-${c.settings.email}'),
        initialValue: c.settings.email,
        readOnly: true,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: _t(
            'MyMemory 联系邮箱（选填）',
            'MyMemory contact email (optional)',
          ),
          hintText: 'you@example.com',
          helperText: _t(
            '仅填写你自己的有效邮箱，会随翻译请求发送。',
            'Use your own valid email. It is sent with translation requests.',
          ),
          helperMaxLines: 2,
        ),
        onFieldSubmitted: (value) => _saveSettings(email: value),
      ),
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed: () async {
          final email = await _textDialog(
            _t('设置 MyMemory 联系邮箱', 'Set MyMemory contact email'),
            c.settings.email,
            lines: 1,
            allowEmpty: true,
            helper: _t(
              '提交后会随翻译请求发送。留空使用匿名额度。',
              'It will be sent with requests. Leave blank for anonymous use.',
            ),
          );
          if (email != null) await _saveSettings(email: email.trim());
        },
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: Text(_t('修改联系邮箱', 'Change contact email')),
      ),
    ],
  );

  Widget _providerDetail(String provider) {
    final order = c.settings.providerOrder;
    final index = order.indexOf(provider);
    final configured = providerCredentialsReady(
      provider,
      c.credentialsFor(provider),
    );
    final hasCredentialData = c.credentialsFor(provider).isNotEmpty;
    final validation = c.credentialValidationFor(provider);
    final description = switch (provider) {
      'MyMemory' => _t(
        '可匿名使用；联系邮箱与私有词库密钥可选。支持 31 种目标语言；私有词库密钥不代表额度增加。',
        'Anonymous use is available. Contact email and private memory key are optional. Supports 31 target languages; a private memory key does not increase quota.',
      ),
      'ZTAITrans' => _t(
        '自备 API 密钥或开发者访问码；不再提供匿名共享额度。',
        'Use your own API key or a developer access code. Shared anonymous quota is no longer available.',
      ),
      'DeepL' => _t(
        '请选择控制台对应的 free / pro 接口。新注册 Developer 额度为总计 100 万字符；旧 Free 为每月 50 万，具体以账户为准。',
        'Choose the free or pro endpoint shown in your DeepL console. Character allowances depend on your account plan.',
      ),
      'Azure' => _t(
        'F0 层每月 200 万字符，到限停止；其他定价层以账户配置为准。',
        'The F0 tier has a monthly character allowance. Other limits depend on your account.',
      ),
      'Google' => _t(
        'Basic 每月 50 万 NMT 字符抵扣，需启用结算，超额收费；请在账户设置用量限额。',
        'Billing must be enabled. Check your account for credits and set usage limits.',
      ),
      'Baidu' => _t(
        '百度通用翻译：标准版每月 5 万、高级版 100 万、尊享版 200 万字符，超额收费；扩展语种可能需企业尊享版。',
        'Baidu pricing and language support depend on your account tier. Check your console and set usage limits.',
      ),
      'Tencent' => _t(
        '腾讯文本翻译仅适用于既有账户，免费资源包已停发；服务将于 2027 年 10 月 1 日停用。当前支持 15 种目标语言。',
        'Tencent Text Translation is available only to existing accounts. The free package has ended and service ends on October 1, 2027. Currently supports 15 target languages.',
      ),
      _ => _t(
        '阿里云通用版主账户每月 100 万字符，子账户共享；超额后付费，使用前请设置限额。',
        'Alibaba Cloud allowance is shared across subaccounts. Usage beyond the allowance is billed. Set limits before use.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('平台介绍', 'About this provider'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: _muted,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (provider == 'MyMemory') ...[
          _Panel(child: _myMemorySettings()),
          const SizedBox(height: 14),
        ],
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('配置与验证', 'Configuration and verification'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 6),
              Text(
                configured
                    ? (c.credentialsSaved(provider)
                          ? _t(
                              '凭据：•••••• · 已在本机保存',
                              'Credentials: •••••• · Saved on this device',
                            )
                          : _t(
                              '凭据：•••••• · 仅本次会话',
                              'Credentials: •••••• · This session only',
                            ))
                    : provider == 'MyMemory'
                    ? _t(
                        '匿名模式（未配置私有词库密钥）',
                        'Anonymous mode (no private memory key)',
                      )
                    : hasCredentialData
                    ? _t('凭据尚未填写完整', 'Credentials are incomplete')
                    : _t('尚未配置凭据', 'Credentials not configured'),
                style: const TextStyle(fontSize: 13, color: _muted),
              ),
              const SizedBox(height: 6),
              Text(
                '${validation.status == 'checking'
                    ? _t('当前验证', 'Current check')
                    : validation.status == 'unverified'
                    ? _t('验证状态', 'Verification status')
                    : _t('上次验证', 'Last check')}${_en ? ': ' : '：'}${_validationLabel(validation)}',
                key: ValueKey('validation-status-$provider'),
                style: TextStyle(
                  fontSize: 13,
                  color: validation.status == 'valid'
                      ? _green
                      : validation.status == 'invalid'
                      ? const Color(0xFF9B4B39)
                      : _muted,
                ),
              ),
              Text(
                _validationMessage(validation),
                style: const TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.6,
                ),
              ),
              if (validation.billableCharacters != null)
                Text(
                  validation.billableCharacters == 1
                      ? _t(
                          '本次验证最多可能产生 1 字符用量',
                          'This check may use up to 1 billable character',
                        )
                      : _t(
                          '本次验证字符用量：0',
                          'Billable characters for this check: 0',
                        ),
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: () => _providerCredentialDialog(provider),
                    child: Text(_t('配置 $provider', 'Configure $provider')),
                  ),
                  if (configured || provider == 'MyMemory')
                    TextButton(
                      key: ValueKey('revalidate-$provider'),
                      onPressed: validation.status == 'checking'
                          ? null
                          : () => unawaited(
                              c.validateProviderCredentials(
                                provider,
                                force: true,
                              ),
                            ),
                      child: Text(
                        validation.status == 'checking'
                            ? _t('验证中…', 'Checking…')
                            : _t('重新验证 $provider', 'Recheck $provider'),
                      ),
                    ),
                  if (hasCredentialData)
                    TextButton(
                      onPressed: () =>
                          _guard(() => c.clearProviderCredentials(provider)),
                      child: Text(
                        _t('清除 $provider 凭据', 'Clear $provider credentials'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (index >= 0) ...[
          const SizedBox(height: 14),
          _Panel(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  _t('备用顺序：${index + 1}', 'Fallback order: ${index + 1}'),
                  style: const TextStyle(fontSize: 14),
                ),
                if (index > 0)
                  TextButton.icon(
                    onPressed: () {
                      final updated = [...order];
                      updated[index] = updated[index - 1];
                      updated[index - 1] = provider;
                      _guard(() => c.saveProviderOrder(updated));
                    },
                    icon: const Icon(CupertinoIcons.arrow_up, size: 16),
                    label: Text(_t('上移 $provider', 'Move $provider up')),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _validationLabel(CredentialValidation validation) {
    if (!_en) return validation.label;
    return switch (validation.status) {
      'checking' => 'Checking',
      'valid' =>
        validation.method == 'metadata'
            ? 'Authorization checked (no test translation)'
            : validation.method == 'translation'
            ? 'One-character test passed'
            : 'Anonymous mode needs no key',
      'invalid' => 'Credentials or configuration invalid',
      'limited' => 'Check limited',
      'unavailable' => 'Not verified',
      _ => 'Not checked',
    };
  }

  String _validationMessage(CredentialValidation validation) {
    if (!_en) return validation.message;
    return switch (validation.status) {
      'checking' =>
        'Checking now. Some providers may use one billable character.',
      'valid' =>
        validation.method == 'metadata'
            ? 'Authorization or catalog access passed. Translation in every target language was not tested.'
            : validation.method == 'anonymous'
            ? 'No credentials are needed. Service availability and remaining quota were not checked.'
            : 'A minimal test translation passed. Check remaining quota and plan details in your provider console.',
      'invalid' =>
        'The provider did not accept these credentials or settings. Check them and try again.',
      'limited' =>
        'Rate, balance, or quota limits may prevent verification. Try later or check the provider console.',
      'unavailable' =>
        'Verification could not be completed. Check the provider or proxy connection and try again.',
      _ => 'These credentials have not been checked in this session.',
    };
  }

  String _credentialLabel(String provider, String field) => switch (field) {
    'apiKey' =>
      provider == 'MyMemory'
          ? _t(
              '私有词库 API 密钥（可留空匿名）',
              'Private memory API key (blank for anonymous use)',
            )
          : _t('API 密钥', 'API key'),
    'developerToken' => _t('开发者访问码', 'Developer access code'),
    'tenantId' => _t('Tenant ID（选填）', 'Tenant ID (optional)'),
    'region' =>
      provider == 'Tencent'
          ? _t('区域（默认 ap-guangzhou）', 'Region (default: ap-guangzhou)')
          : _t('区域（选填，如 eastasia）', 'Region (optional, e.g. eastasia)'),
    'appId' => 'App ID',
    'secretId' => 'Secret ID',
    'secretKey' => 'Secret Key',
    'accessKeyId' => 'AccessKey ID',
    'accessKeySecret' => 'AccessKey Secret',
    _ => field,
  };

  Future<void> _providerCredentialDialog(String provider) async {
    final current = c.credentialsFor(provider);
    final controllers = {
      for (final field
          in providerCredentialFields[provider] ?? const <String>[])
        if (field != 'plan')
          field: TextEditingController(
            text:
                current[field] ??
                (provider == 'Tencent' && field == 'region'
                    ? 'ap-guangzhou'
                    : ''),
          ),
    };
    var developer = current.containsKey('developerToken');
    var remember = c.credentialsSaved(provider), saving = false;
    var plan = current['plan'] == 'pro' ? 'pro' : 'free';
    String? error;
    await _formModal<void>(
      (dialogContext) => StatefulBuilder(
        builder: (context, update) => _formFrame(
          dialogContext,
          title: _t('配置 $provider', 'Configure $provider'),
          doneLabel: _compact
              ? _t('保存', 'Save')
              : _t('保存配置', 'Save configuration'),
          width: 420,
          busy: saving,
          onDone: saving
              ? null
              : () async {
                  update(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    await c.saveProviderCredentials(provider, {
                      for (final entry in controllers.entries)
                        if (provider != 'ZTAITrans' ||
                            (developer
                                ? entry.key == 'developerToken'
                                : entry.key != 'developerToken'))
                          entry.key: entry.value.text,
                      if (provider == 'DeepL') 'plan': plan,
                    }, remember: remember);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (failure) {
                    if (dialogContext.mounted) {
                      update(() {
                        error = failure is FormatException
                            ? _localizeError(failure.message)
                            : _t(
                                '请检查必填凭据和配置，然后重试。',
                                'Check required credentials and settings, then try again.',
                              );
                        saving = false;
                      });
                    }
                  }
                },
          child: FocusScope(
            canRequestFocus: !saving,
            descendantsAreFocusable: !saving,
            child: AbsorbPointer(
              absorbing: saving,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (provider == 'ZTAITrans')
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_t('开发者访问码模式', 'Developer access code mode')),
                      value: developer,
                      onChanged: (value) => update(() => developer = value),
                    ),
                  for (final field in controllers.keys.where(
                    (field) =>
                        provider != 'ZTAITrans' ||
                        (developer
                            ? field == 'developerToken'
                            : field != 'developerToken'),
                  ))
                    TextField(
                      key: ValueKey('credential-$provider-$field'),
                      controller: controllers[field],
                      obscureText: providerSecretFields.contains(field),
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _credentialLabel(provider, field),
                      ),
                    ),
                  if (provider == 'Alibaba')
                    Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        _t(
                          '服务区域固定为 cn-hangzhou，签名由代理完成。',
                          'The service region is fixed to cn-hangzhou. The proxy signs requests.',
                        ),
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    ),
                  if (provider == 'DeepL' && _compact) ...[
                    const SizedBox(height: 16),
                    Text(_t('账户接口', 'Account endpoint')),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<String>(
                        groupValue: plan,
                        children: {
                          'free': Text(_t('免费接口', 'Free')),
                          'pro': Text(_t('标准接口', 'Pro')),
                        },
                        onValueChanged: (value) =>
                            update(() => plan = value ?? 'free'),
                      ),
                    ),
                  ] else if (provider == 'DeepL')
                    DropdownButtonFormField<String>(
                      initialValue: plan,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('账户接口', 'Account endpoint'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'free',
                          child: Text(
                            _t('免费接口 · api-free', 'Free endpoint · api-free'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'pro',
                          child: Text(_t('标准接口 · api', 'Pro endpoint · api')),
                        ),
                      ],
                      onChanged: (value) =>
                          update(() => plan = value ?? 'free'),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      '保存后自动验证。部分平台将试译“好”→英语，可能产生 1 字符用量；重新验证也可能计费。',
                      'Credentials are checked after saving. Some providers run a one-character test translation, which may be billable. Rechecking may also incur usage.',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: _muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_compact)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t(
                                  '在本机保存凭据',
                                  'Save credentials on this device',
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _t(
                                  '默认仅本次会话。本机保存不额外加密；共享设备请保持关闭。',
                                  'By default, credentials last only for this session. Device storage adds no encryption; leave this off on shared devices.',
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        CupertinoSwitch(
                          value: remember,
                          onChanged: (value) => update(() => remember = value),
                        ),
                      ],
                    )
                  else
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: remember,
                      title: Text(
                        _t('在本机保存凭据', 'Save credentials on this device'),
                      ),
                      subtitle: Text(
                        _t(
                          '默认仅本次会话。本机保存不额外加密；共享设备请保持关闭。',
                          'By default, credentials last only for this session. Device storage adds no encryption; leave this off on shared devices.',
                        ),
                      ),
                      onChanged: (value) =>
                          update(() => remember = value == true),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: Color(0xFF9B4B39)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PageHeading(
        eyebrow: 'WORKSPACE PREFERENCES',
        title: _t('偏好设置', 'Settings'),
        subtitle: _t('让工作台，更贴近你的使用习惯。', 'Make this workspace work for you.'),
      ),
      const SizedBox(height: 25),
      _columns(
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('翻译服务', 'Translation services'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _t(
                  '勾选启用平台，点击平台查看配置和验证。',
                  'Select providers, then open a row to configure and verify.',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: _muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              _providerSettings(),
            ],
          ),
        ),
        Column(
          children: [
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('连接与导出', 'Connection and export'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: ValueKey('base-${c.settings.apiBaseUrl}'),
                    initialValue:
                        !kIsWeb && c.settings.apiBaseUrl.trim().isEmpty
                        ? defaultBackupServiceOrigin
                        : c.settings.apiBaseUrl,
                    readOnly: true,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: _t('翻译代理服务', 'Translation proxy'),
                      hintText: kIsWeb
                          ? _t('使用当前网站的同源服务', 'Use this website’s service')
                          : _t('内置在线服务（无需配置）', 'Built-in online service'),
                      helperText: kIsWeb
                          ? _t(
                              'Web 使用同源代理转发你配置的凭据，不将凭据写入项目或导出。',
                              'The website forwards your credentials through its proxy. They are not stored in projects or exports.',
                            )
                          : _t(
                              '默认使用与在线工作台相同的代理。付费平台需自备密钥，可按需切换自定义服务器。',
                              'Uses the online workspace proxy. Paid providers require your own keys; you can set a custom server.',
                            ),
                      helperMaxLines: 3,
                    ),
                    onFieldSubmitted: (value) => _saveSettings(baseUrl: value),
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () async {
                        final base = await _textDialog(
                          _t(
                            '自定义翻译代理（选填）',
                            'Custom translation proxy (optional)',
                          ),
                          c.settings.apiBaseUrl,
                          lines: 1,
                          allowEmpty: true,
                          helper: _t(
                            '留空使用内置在线代理。自定义地址需为提供翻译代理的 HTTPS 根域名；密钥在平台配置中填写。',
                            'Leave blank to use the built-in proxy. A custom URL must be an HTTPS origin for a compatible translation proxy.',
                          ),
                        );
                        if (base != null) {
                          await _saveSettings(baseUrl: base.trim());
                        }
                      },
                      icon: const Icon(Icons.link, size: 16),
                      label: Text(_t('自定义服务器（可选）', 'Custom server (optional)')),
                    ),
                    if (c.settings.apiBaseUrl.trim().isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _saveSettings(baseUrl: ''),
                        icon: const Icon(Icons.restore, size: 16),
                        label: Text(_t('恢复内置在线服务', 'Restore built-in service')),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _backupConfigured == true
                              ? _t(
                                  '开发者访问码已验证，可使用授权服务',
                                  'Developer access code verified. Authorized service is available.',
                                )
                              : _t(
                                  '开发者服务需访问码授权；自备密钥可独立配置。',
                                  'Developer service requires an access code. You can also configure your own key.',
                                ),
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _checkBackupConnection,
                        child: Text(_t('检测服务', 'Check service')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: c.settings.includeSource,
                    onChanged: (value) => _saveSettings(includeSource: value),
                    title: Text(
                      _t('默认包含源语言包', 'Include source pack by default'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      _t(
                        '导出时同时生成项目源语言 JSON',
                        'Export a JSON file for the project’s source language',
                      ),
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ),
                  const Divider(),
                  _summary(_t('Key 命名', 'Key format'), 'snake_case'),
                  _summary(_t('导出格式', 'Export format'), 'UTF-8 JSON / ZIP'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Panel(
              padding: EdgeInsets.zero,
              child: ListTile(
                key: const ValueKey('settings-privacy-policy'),
                leading: const Icon(CupertinoIcons.shield, color: _green),
                title: Text(_t('隐私协议', 'Privacy policy')),
                subtitle: Text(_t('数据使用与存储说明', 'How data is used and stored')),
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 16),
                onTap: () => _openSettingsDetail(
                  _t('隐私协议', 'Privacy policy'),
                  (_) => PrivacyPolicyContent(english: _en),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _Panel(
              color: Color(0xFFEEF4E9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.devices_rounded, color: _green, size: 25),
                  const SizedBox(height: 12),
                  Text(
                    _t('一个工作台，陪伴每一块屏幕', 'One workspace, every screen'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _t(
                      'iOS · Android · Windows · macOS · Linux · Web\n项目数据保存在当前设备，各端暂不自动同步。卸载应用或清理浏览器数据前，请保存需要保留的语言包。',
                      'iOS · Android · Windows · macOS · Linux · Web\nProject data stays on this device and does not sync across platforms. Save any language packs you need before uninstalling the app or clearing browser data.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _muted,
                      height: 1.9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _checkBackupConnection() async {
    final generation = ++_backupCheckGeneration;
    final base = c.settings.apiBaseUrl;
    final credentialRevision = c.providerCredentialRevision;
    bool isCurrent() =>
        mounted &&
        generation == _backupCheckGeneration &&
        base == c.settings.apiBaseUrl &&
        credentialRevision == c.providerCredentialRevision;
    try {
      final result = await c.checkBackup();
      if (isCurrent()) setState(() => _backupConfigured = result);
    } catch (error) {
      if (isCurrent()) _notify(error.toString(), error: true);
    }
  }

  Future<void> _saveSettings({
    String? email,
    String? baseUrl,
    bool? includeSource,
  }) => _guard(() async {
    _backupCheckGeneration++;
    await c.saveSettings(
      email: email ?? c.settings.email,
      apiBaseUrl: baseUrl ?? c.settings.apiBaseUrl,
      includeSource: includeSource ?? c.settings.includeSource,
    );
    if (mounted) setState(() => _backupConfigured = null);
  });

  Widget _columns(
    Widget left,
    Widget right, {
    int leftFlex = 3,
    int rightFlex = 2,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 800) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            SizedBox(height: _compact ? 14 : 20),
            right,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: leftFlex, child: left),
          const SizedBox(width: 23),
          Expanded(flex: rightFlex, child: right),
        ],
      );
    },
  );

  Widget _footer(Widget left, Widget right) => _compact
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: right,
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: left),
          ],
        )
      : Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 12,
          children: [left, right],
        );

  String _date(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
}

/// Keeps the editing selection stable when progress and persistence notify.
class _TranslationEditor extends StatefulWidget {
  const _TranslationEditor({
    super.key,
    required this.text,
    required this.label,
    required this.onChanged,
  });
  final String text;
  final String label;
  final ValueChanged<String> onChanged;
  @override
  State<_TranslationEditor> createState() => _TranslationEditorState();
}

class _TranslationEditorState extends State<_TranslationEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(covariant _TranslationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    minLines: 5,
    maxLines: 16,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: '在这里编辑译文，或点击重新翻译。',
      alignLabelWithHint: true,
    ),
    style: const TextStyle(fontSize: 15, height: 1.8),
    onChanged: widget.onChanged,
  );
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.translate_rounded,
          size: 21,
          color: Colors.white,
        ),
      ),
      if (!compact) ...[
        const SizedBox(width: 12),
        const Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '译包 LangPack',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'WORDS WITHOUT BORDERS',
                  style: TextStyle(
                    fontSize: 7,
                    letterSpacing: 1.1,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.action,
    this.back,
  });
  final String title;
  final String subtitle;
  final String? eyebrow;
  final Widget? action;
  final VoidCallback? back;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = MediaQuery.sizeOf(context).width < 650;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null && !compact) ...[
            Text(
              eyebrow!,
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1.7,
                color: _muted,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (back != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: IconButton.filledTonal(
                    onPressed: back,
                    tooltip: '返回',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEAF2E5),
                      foregroundColor: _green,
                    ),
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                ),
                SizedBox(width: compact ? 8 : 11),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: compact
                            ? 22
                            : constraints.maxWidth < 600
                            ? 25
                            : 30,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.7,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: compact ? 5 : 9),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: _muted,
                        height: compact ? 1.5 : 1.8,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null && !compact && constraints.maxWidth > 600) ...[
                const SizedBox(width: 20),
                action!,
              ],
            ],
          ),
          if (action != null && (compact || constraints.maxWidth <= 600)) ...[
            SizedBox(height: compact ? 10 : 17),
            action!,
          ],
        ],
      );
    },
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding, this.color = Colors.white});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding:
        padding ??
        EdgeInsets.all(MediaQuery.sizeOf(context).width < 650 ? 16 : 24),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.warm = false, this.icon});
  final String label;
  final bool warm;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: warm ? const Color(0xFFF7F1E4) : const Color(0xFFEDF4E8),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: warm ? const Color(0xFFAA894B) : _green),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: warm ? const Color(0xFFA08041) : _green,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {required this.icon, this.warm = false});
  final String text;
  final IconData icon;
  final bool warm;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warm ? const Color(0xFFFCF6EA) : const Color(0xFFF1F6ED),
      border: Border.all(
        color: warm ? const Color(0xFFEBDDBE) : const Color(0xFFDEEBDA),
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: warm ? const Color(0xFFA17C37) : _green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: warm ? const Color(0xFF9A7B43) : const Color(0xFF678168),
              height: 1.8,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        if (constraints.maxWidth > 170) ...[
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _green, size: 22),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: MediaQuery.sizeOf(context).width < 650 ? 22 : 28,
                  fontWeight: FontWeight.w500,
                  color: _green,
                ),
              ),
              const SizedBox(height: 5),
              Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 650;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 18 : 45,
        horizontal: compact ? 4 : 15,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            children: [
              Container(
                width: compact ? 48 : 65,
                height: compact ? 48 : 65,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF4E7),
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Icon(icon, size: compact ? 25 : 31, color: _green),
              ),
              SizedBox(height: compact ? 11 : 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: compact ? 7 : 12),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: _muted,
                  height: compact ? 1.5 : 1.9,
                ),
              ),
              if (action != null) ...[
                SizedBox(height: compact ? 12 : 22),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
