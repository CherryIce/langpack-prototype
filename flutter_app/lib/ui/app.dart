import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import '../services/translation_service.dart' show defaultBackupServiceOrigin;

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
          content: Text(text),
          backgroundColor: error ? const Color(0xFF9B4B39) : _ink,
          duration: Duration(seconds: error ? 7 : 4),
        ),
      );
    });
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
    _View.home => '我的项目',
    _View.project => c.currentProject?.name ?? '项目',
    _View.input => '文本输入',
    _View.document => '文档导入',
    _View.languages => '目标语言',
    _View.progress => '翻译任务',
    _View.review => '翻译校对',
    _View.export => '导出语言包',
    _View.tasks => '翻译任务',
    _View.exports => '导出记录',
    _View.settings => '偏好设置',
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
                              compact ? 20 : 34,
                              compact ? 25 : 34,
                              compact ? 20 : 34,
                              40,
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
              selectedIndex: _navIndex,
              onDestinationSelected: _selectNavigation,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: '我的项目',
                ),
                NavigationDestination(
                  icon: Icon(Icons.translate_rounded),
                  label: '翻译任务',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_zip_outlined),
                  label: '导出记录',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: '设置',
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
          const Padding(
            padding: EdgeInsets.only(left: 14, bottom: 15),
            child: Text(
              '工作空间',
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
                          ['我的项目', '翻译任务', '导出记录', '偏好设置'][index],
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.public_rounded, color: _green, size: 22),
                SizedBox(height: 10),
                Text(
                  '让表达，跨越语言',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  '从一句中文，到世界的每一种声音。',
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本地工作空间', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 3),
                  Text(
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
    height: compact ? 62 : 72,
    padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 34),
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
          const Text('工作空间', style: TextStyle(fontSize: 12, color: _muted)),
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
        const _Tag('本地工作空间', icon: Icons.devices_outlined),
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
                '翻译进行中 · ${c.completed}/${c.total} · ${c.activeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _green),
              ),
            ),
            const Text('查看', style: TextStyle(fontSize: 12, color: _green)),
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
        title: '先创建一个项目',
        detail: '把相关文案放在一起，管理它们的多语言版本。',
        action: FilledButton.icon(
          onPressed: _newProject,
          icon: const Icon(Icons.add),
          label: const Text('新建项目'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          eyebrow: 'YOUR WORDS, WORLDWIDE',
          title: '我的项目',
          subtitle: '在这里，管理每一句表达的多语言旅程。',
          action: FilledButton.icon(
            onPressed: _newProject,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建项目'),
          ),
        ),
        const SizedBox(height: 25),
        _hero(),
        const SizedBox(height: 23),
        _stats([
          _Stat('项目总数', '${c.projects.length}', Icons.folder_outlined),
          _Stat('中文文案', '$totalEntries', Icons.notes_rounded),
          _Stat('覆盖语言', '$totalLanguages', Icons.public_rounded),
        ]),
        const SizedBox(height: 30),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 14,
          children: [
            const Text(
              '全部项目',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
            ),
            SizedBox(
              width: 270,
              child: TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: const InputDecoration(
                  hintText: '搜索项目名称',
                  prefixIcon: Icon(Icons.search, size: 20),
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
              title: _search.isEmpty ? '你的第一个多语言项目' : '没有找到匹配的项目',
              detail: _search.isEmpty
                  ? '创建项目，输入中文或导入文档，生成可以直接使用的语言包。'
                  : '试试其他关键词。',
              action: _search.isEmpty
                  ? OutlinedButton.icon(
                      onPressed: _newProject,
                      icon: const Icon(Icons.add),
                      label: const Text('创建项目'),
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
        const Text(
          '从中文到语言包，只需四步',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Wrap(
            spacing: 28,
            runSpacing: 22,
            children: [
              for (final item in [
                ('01', '输入中文', '粘贴文本或本地解析文档'),
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
        const Text(
          '文档在本地解析 · 译文可追溯来源 · 标准 UTF-8 JSON',
          style: TextStyle(fontSize: 11, color: _muted),
        ),
      ],
    );
  }

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
                  '你的表达，\n不止一种语言。',
                  style: TextStyle(
                    fontSize: constraints.maxWidth < 600 ? 29 : 36,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                    color: const Color(0xFF315A43),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '从中文文案到多语言交付，让每一句话都被世界读懂。',
                  style: TextStyle(
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
                      label: const Text('输入文案'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _beginInput(true),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('导入文档'),
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
                  horizontal: constraints.maxWidth < 600 ? 15 : 25,
                  vertical: 21,
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
                    p.totalCount > 0 && ratio == 1 ? '译文齐全' : '进行中',
                    warm: ratio < 1,
                  ),
                  PopupMenuButton<String>(
                    tooltip: '项目操作',
                    iconSize: 19,
                    onSelected: (value) {
                      if (value == 'delete') _deleteProject(p);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'delete', child: Text('删除项目')),
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
                p.description.isEmpty ? '为每一句中文，准备一个多语言版本。' : p.description,
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
                    .map((locale) => _Tag(languageName(locale)))
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
                    '${p.entries.length} 条文案',
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

  Future<bool> _newProject() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('创建一个新项目'),
        content: SizedBox(
          width: 390,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: '项目名称',
                    hintText: '例如：产品网站',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写项目名称' : null,
                ),
                const SizedBox(height: 13),
                TextField(
                  controller: description,
                  maxLength: 180,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '项目说明（选填）',
                    hintText: '这个项目的文案用于什么地方？',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('创建项目'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      c.createProject(name.text.trim(), description: description.text.trim());
      _go(_View.project);
    }
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      name.dispose();
      description.dispose();
    });
    return result == true;
  }

  Future<void> _deleteProject(Project project) async {
    if (c.running) {
      _notify('请先暂停翻译任务，再删除项目。');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个项目？'),
        content: Text('“${project.name}”的文案、译文和本地导出记录将被删除。已保存到设备的文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除项目'),
          ),
        ],
      ),
    );
    if (yes == true) {
      c.deleteProject(project.id);
      if (mounted) _go(_View.home);
    }
  }

  Future<void> _beginInput(bool document) async {
    _importGeneration++;
    _importing = false;
    if (c.currentProject == null) {
      if (c.projects.isNotEmpty) {
        c.openProject(c.projects.first.id);
      } else if (!await _newProject()) {
        return;
      }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          eyebrow: 'PROJECT / LOCALIZATION',
          title: p.name,
          subtitle: p.description.isEmpty
              ? '你的中文文案与多语言版本，都在这里。'
              : p.description,
          back: () => _go(_View.home),
          action: FilledButton.icon(
            onPressed: () => _beginInput(false),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增文案'),
          ),
        ),
        const SizedBox(height: 24),
        _stats([
          _Stat('中文文案', '${p.entries.length}', Icons.notes_rounded),
          _Stat('目标语言', '${p.locales.length}', Icons.public_rounded),
          _Stat(
            '译文齐全度',
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '每一句中文，都能走得更远',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 7),
                  Text(
                    '补齐缺失译文，保护人工修改和已经确认的内容。',
                    style: TextStyle(fontSize: 12, color: _muted),
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
                label: const Text('翻译未完成项'),
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
              '项目文案 · ${p.entries.length}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _beginInput(true),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('导入文档'),
                ),
                TextButton.icon(
                  onPressed: p.selectedEntries.isEmpty
                      ? null
                      : () {
                          _reviewIndex = 0;
                          _go(_View.review);
                        },
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('校对'),
                ),
                OutlinedButton.icon(
                  onPressed: p.selectedEntries.isEmpty
                      ? null
                      : () => _go(_View.export),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('导出语言包'),
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
              title: '第一条文案，从这里开始',
              detail: '输入中文或导入文档，生成你的第一组语言包。',
              action: FilledButton(
                onPressed: () => _beginInput(false),
                child: const Text('添加文案'),
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
                          '已选择 ${p.selectedEntries.length} 条用于翻译和导出',
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
        const _Notice(
          '项目数据保存在当前设备或浏览器。导出语言包后可交付使用；各端数据暂不自动同步。',
          icon: Icons.devices_outlined,
        ),
      ],
    );
  }

  Widget _entryRow(Entry entry, int index) {
    final p = c.currentProject!;
    final done = p.locales
        .where(
          (locale) =>
              entry.translations[locale]?.text.trim().isNotEmpty == true,
        )
        .length;
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
                          languageName(locale),
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
                tooltip: '校对这条文案',
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
            tooltip: '文案操作',
            onSelected: (action) {
              if (action == 'edit') {
                _editEntrySource(entry);
              } else if (!c.running) {
                c.deleteEntry(entry);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑原文')),
              PopupMenuItem(
                value: 'delete',
                enabled: !c.running,
                child: const Text('删除文案'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _workflow(
    int index,
    String title,
    String subtitle, {
    VoidCallback? back,
  }) => Column(
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
                        color: step <= index ? _green : const Color(0xFFEDF2E9),
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
                                color: step <= index ? Colors.white : _muted,
                                fontSize: 12,
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ['添加内容', '选择语言', '翻译校对', '导出语言包'][step],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflow(
          0,
          document ? '从文档开始，一次翻译全文' : '添加你的中文文案',
          '每一段表达，都值得被更多人读懂。',
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
                      label: const Text('文本输入'),
                      avatar: const Icon(Icons.edit_note, size: 18),
                      selected: !document,
                      onSelected: (_) => _go(_View.input),
                    ),
                    ChoiceChip(
                      label: const Text('文档导入'),
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
                  const Text(
                    '中文原文',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 11),
                  TextField(
                    controller: _input,
                    minLines: 10,
                    maxLines: 18,
                    onChanged: _parseText,
                    decoration: InputDecoration(
                      hintText: '在这里输入中文文案，例如：\n\n登录\n欢迎使用我们的产品\n你好，{name}',
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
                      const Text(
                        '拆分方式',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                      ChoiceChip(
                        label: const Text('按行'),
                        selected: _split == 'line',
                        onSelected: (_) {
                          _split = 'line';
                          _parseText(_input.text);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('按空行段落'),
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
                  decoration: const InputDecoration(
                    labelText: 'Key 前缀（选填）',
                    hintText: '例如 auth → auth_login',
                    helperText: '常见文案自动语义命名，自定义文案可在校对时修改。',
                  ),
                ),
                const SizedBox(height: 15),
                const _Notice(
                  '文档文件在本地解析。只有点击开始翻译后，选中的原文才会发送给翻译服务。',
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
                    const Expanded(
                      child: Text(
                        '内容预览',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _Tag(
                      '${blocks.where((b) => b.selected).length} / ${blocks.length} 段',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '勾选需要翻译的段落，点击内容可编辑。',
                  style: TextStyle(fontSize: 12, height: 1.7, color: _muted),
                ),
                const SizedBox(height: 15),
                if (blocks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.subject_rounded,
                            size: 37,
                            color: Color(0xFFB0C3AE),
                          ),
                          SizedBox(height: 15),
                          Text(
                            '添加内容后，段落会出现在这里',
                            style: TextStyle(fontSize: 12, color: _muted),
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
                          blocks.every((b) => b.selected) ? '取消全选' : '全选',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: blocks.where((b) => b.selected).length < 2
                            ? null
                            : _mergeBlocks,
                        icon: const Icon(Icons.merge_type, size: 17),
                        label: const Text('合并所选'),
                      ),
                      TextButton.icon(
                        onPressed: blocks.any((b) => b.selected)
                            ? _splitBlocks
                            : null,
                        icon: const Icon(Icons.call_split, size: 17),
                        label: const Text('按句拆分'),
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
            label: const Text('返回项目'),
          ),
          FilledButton.icon(
            onPressed:
                _importing || blocks.every((b) => !b.selected) || blocks.isEmpty
                ? null
                : _commitBlocks,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('下一步：选择语言'),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBF5),
          border: Border.all(color: const Color(0xFFCBDEC8)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Icon(Icons.upload_file_outlined, size: 43, color: _green),
            const SizedBox(height: 15),
            const Text(
              '选择需要翻译的文档',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 9),
            const Text(
              'TXT · Markdown · DOCX\n最大 10 MB，最多 1,000 个内容块',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _muted, height: 1.9),
            ),
            const SizedBox(height: 20),
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
              label: Text(_importing ? '正在解析…' : '选择文件'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      const Text(
        'Word 正文和表格会按内容块提取。暂不支持 PDF、图片扫描件和旧版 DOC，复杂排版不还原。',
        style: TextStyle(fontSize: 11, height: 1.8, color: _muted),
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
          tooltip: '编辑段落',
          icon: const Icon(Icons.edit_outlined, size: 17, color: _muted),
        ),
      ],
    ),
  );

  Future<void> _editBlock(DocumentBlock block) async {
    final text = await _textDialog('编辑段落', block.text, lines: 8);
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
    final query = _languageSearch.trim().toLowerCase();
    final visibleLanguages = supportedLanguages
        .where(
          (language) =>
              '${language.code} ${language.name} ${language.nativeName}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflow(1, '为你的内容，选择目的地', '一次选择多种语言，每种语言使用相同的 Key。'),
        _columns(
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '目标语言',
                        style: TextStyle(
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
                                      supportedLanguages.length
                                  ? []
                                  : supportedLanguages
                                        .map((l) => l.code)
                                        .toList(),
                            ),
                      child: Text(
                        selectedLocales.length == supportedLanguages.length
                            ? '取消全选'
                            : '选择全部',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                const _Notice(
                  '简体中文 · 源语言，导出时可包含 zh-Hans.json。另有 34 种目标语言可选。',
                  icon: Icons.language,
                ),
                const SizedBox(height: 8),
                const Text(
                  'MyMemory 不支持巴西葡萄牙语、菲律宾语和书面挪威语，请为这些语言启用支持它们的平台。',
                  style: TextStyle(fontSize: 11, color: _muted, height: 1.6),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('language-search'),
                  initialValue: _languageSearch,
                  onChanged: (value) => setState(() => _languageSearch = value),
                  decoration: const InputDecoration(
                    labelText: '搜索目标语言',
                    hintText: '中文名、原生名称或语言代码',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '已选 ${selectedLocales.length} / ${supportedLanguages.length} 种',
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
                        child: const Text('选择搜索结果'),
                      ),
                  ],
                ),
                if (visibleLanguages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('没有匹配的目标语言'),
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
                                              language.name,
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
                const Text(
                  '本次翻译',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 22),
                _summary('中文文案', '${p.selectedEntries.length} 条'),
                _summary('目标语言', '${selectedLocales.length} 种'),
                const Divider(height: 30),
                const Text(
                  '需要新增翻译',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 10),
                Text(
                  '${plan.uniquePending} 组原文与语言',
                  style: const TextStyle(
                    fontSize: 29,
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _summary('保留已有结果', '${plan.retained} 条'),
                _summary('复用项目译文', '${plan.reusable} 条'),
                _summary('本批重复文案', '${plan.pending - plan.uniquePending} 条'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: selectedLocales
                      .map((code) => _Tag(languageName(code)))
                      .toList(),
                ),
                const SizedBox(height: 25),
                _Notice(
                  '仅新增或变化且没有可复用译文的原文会发送；同批相同内容合并处理。'
                  '本次${c.settings.providerFallback ? '启用顺序：${c.settings.providerOrder.join(' → ')}；仅额度耗尽或语言不支持时切换。' : '只使用首选平台 ${c.settings.providerOrder.first}，自动备用已关闭。'}',
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 14),
                const Text(
                  '长段落自动拆分后合并；人工修改、已确认内容和已有成功结果会受到保护。',
                  style: TextStyle(fontSize: 11, color: _muted, height: 1.8),
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
                    label: const Text('开始增量翻译'),
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
          label: const Text('返回项目'),
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
        _workflow(2, '让每一句话，拥有更多可能', '翻译结果逐条保存，可以随时暂停，再继续。'),
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
                    ? '正在连接世界的语言'
                    : c.paused
                    ? '翻译已暂停'
                    : c.failed > 0
                    ? '部分内容需要再试一次'
                    : '译文已准备好',
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
                    ? '已完成的结果已保留，恢复后继续处理未完成项。'
                    : '接下来，花一点时间校对你的译文。',
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
                            '${c.completed} / ${c.total} 已处理 · 复用 ${c.reused} 条',
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
                      label: const Text('暂停翻译'),
                    ),
                  if (!c.running && c.paused)
                    FilledButton.icon(
                      onPressed: () => _startTranslation(resume: true),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('继续翻译'),
                    ),
                  if (!c.running && c.failed > 0)
                    OutlinedButton.icon(
                      onPressed: () => _startTranslation(retry: true),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text('重试失败项 (${c.failed})'),
                    ),
                  FilledButton.icon(
                    onPressed: () {
                      _reviewIndex = 0;
                      _go(_View.review);
                    },
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('进入翻译校对'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        if (c.error != null) ...[
          const SizedBox(height: 18),
          _Notice(c.error!, icon: Icons.error_outline, warm: true),
        ],
        const SizedBox(height: 20),
        const _Notice(
          '额度耗尽或语言不支持时，可按设置尝试后续平台；鉴权或配置错误会停止。成功译文逐条保存，来源会显示在校对页。',
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
              languageName(locale),
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
                  ? '$done 完成 · $errors 失败'
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
        title: '还没有待校对的文案',
        detail: '先为项目添加内容，或在项目列表中勾选文案。',
        action: OutlinedButton(
          onPressed: () => _go(_View.project),
          child: const Text('返回项目'),
        ),
      );
    }
    if (p.locales.isEmpty) {
      return _Empty(
        icon: Icons.public_rounded,
        title: '先选择目标语言',
        detail: '选择语言后就可以逐条翻译与校对。',
        action: FilledButton(
          onPressed: () => _go(_View.languages),
          child: const Text('选择语言'),
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
        _workflow(2, '好译文，值得再看一眼', '逐条校对，让每一种语言都准确表达你的意思。'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: p.locales
              .map(
                (code) => ChoiceChip(
                  label: Text(languageName(code)),
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
                    const Text('中文 →', style: TextStyle(fontSize: 13)),
                    Text(
                      languageName(_locale),
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
                const Text(
                  '中文原文',
                  style: TextStyle(fontSize: 11, color: _muted),
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
                    label: const Text('编辑原文', style: TextStyle(fontSize: 11)),
                  ),
                ),
                TextFormField(
                  key: ValueKey('key-${entry.id}'),
                  initialValue: entry.key,
                  decoration: const InputDecoration(
                    labelText: '资源 Key',
                    prefixIcon: Icon(Icons.key_outlined, size: 18),
                    helperText: '小写英文、数字和下划线；以字母开头。',
                  ),
                  onChanged: (text) => c.updateEntryKey(entry, text),
                ),
                const SizedBox(height: 21),
                _TranslationEditor(
                  key: ValueKey('translation-${entry.id}-$_locale'),
                  text: value.text,
                  label: '${languageName(_locale)}译文',
                  onChanged: (text) => c.editTranslation(entry, _locale, text),
                ),
                const SizedBox(height: 13),
                if (value.error.isNotEmpty) ...[
                  _Notice(value.error, icon: Icons.error_outline, warm: true),
                  const SizedBox(height: 12),
                ],
                if (ownIssues.isNotEmpty) ...[
                  _Notice(
                    ownIssues.map((issue) => issue.message).join('\n'),
                    icon: Icons.rule_rounded,
                    warm: true,
                  ),
                  const SizedBox(height: 12),
                ],
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
                          child: const Text(
                            '已人工校对确认',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: c.running
                          ? null
                          : () => _retranslate(entry, value),
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('重新翻译'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                _footer(
                  TextButton.icon(
                    onPressed: _reviewIndex == 0
                        ? null
                        : () => setState(() => _reviewIndex--),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一条'),
                  ),
                  TextButton.icon(
                    onPressed: _reviewIndex == entries.length - 1
                        ? null
                        : () => setState(() => _reviewIndex++),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一条'),
                  ),
                ),
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
                ? '完整性检查通过：Key 唯一、译文齐全、占位符一致。语义准确性仍需人工检查。'
                : '发现 ${issues.length} 项完整性问题，点击查看。补齐译文与占位符后即可正式导出。',
            icon: issues.isEmpty ? Icons.verified_outlined : Icons.rule_rounded,
            warm: issues.isNotEmpty,
          ),
        ),
        const SizedBox(height: 24),
        _footer(
          TextButton.icon(
            onPressed: () => _go(_View.project),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('返回项目'),
          ),
          FilledButton.icon(
            onPressed: () {
              _draft = false;
              _go(_View.export);
            },
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('下一步：导出语言包'),
          ),
        ),
      ],
    );
  }

  String _translationLabel(TranslationValue value) {
    if (value.reviewed) return '已人工确认';
    if (value.edited) return '人工编辑 · 待确认';
    if (value.status == TranslationStatus.failed) return '翻译失败';
    if (value.status == TranslationStatus.translating) return '翻译中';
    if (value.text.trim().isEmpty) return '待翻译';
    return '${value.provider.isEmpty ? '译文' : value.provider} · 待校对';
  }

  Future<void> _retranslate(Entry entry, TranslationValue value) async {
    if (value.edited || value.reviewed) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('替换人工校对过的译文？'),
          content: const Text('原文将重新发送给翻译服务。新译文成功返回后替换当前内容，失败时保留现有译文。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重新翻译并替换'),
            ),
          ],
        ),
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
      '编辑中文原文',
      entry.source,
      lines: 7,
      helper: '修改原文后，旧译文会失效，需要重新翻译或校对。',
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
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: text,
            autofocus: true,
            minLines: lines,
            maxLines: 14,
            decoration: InputDecoration(helperText: helper, helperMaxLines: 3),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (allowEmpty || text.text.trim().isNotEmpty) {
                Navigator.pop(context, text.text);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), text.dispose);
    return result;
  }

  void _showIssues() {
    final issues = c.validate();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('语言包完整性检查'),
        content: SizedBox(
          width: 520,
          child: issues.isEmpty
              ? const Text('Key 唯一、译文齐全、占位符一致。翻译的语义准确性仍需人工检查。')
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
                        issues[index].message,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: issues[index].locale == null
                          ? null
                          : Text(languageName(issues[index].locale!)),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
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
          '把语言，带到你的产品中',
          '每种语言独立成包，所有文案使用相同的 Key。',
          back: () => _go(_View.review),
        ),
        _columns(
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '准备导出的语言包',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                                '${_entries.length} 个 Key · ${utf8.encode(files[name]!).length} 字节',
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
                  title: const Text('包含中文源语言包', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    '一并导出 zh-Hans.json',
                    style: TextStyle(fontSize: 11, color: _muted),
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
                  title: const Text('导出草稿', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    '允许缺失译文，ZIP 内附完整性报告',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                  value: _draft,
                  onChanged: (value) => setState(() => _draft = value),
                ),
                const SizedBox(height: 15),
                if (previewError != null)
                  _Notice(previewError, icon: Icons.error_outline, warm: true)
                else
                  InkWell(
                    onTap: _showIssues,
                    child: _Notice(
                      issues.isEmpty
                          ? '完整性检查通过，可以正式导出。'
                          : '还有 ${issues.length} 项待处理问题。可返回校对，或导出带报告的草稿 ZIP。',
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
                          const Expanded(
                            child: Text(
                              'JSON 预览',
                              style: TextStyle(fontSize: 13),
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
                          preview.isEmpty ? '// 语言包预览将在这里显示' : preview,
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
                              '${utf8.encode(preview).length} 字节 · UTF-8',
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
                                    _notify('JSON 已复制');
                                  },
                            icon: const Icon(Icons.copy_outlined, size: 15),
                            label: const Text(
                              '复制',
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
                    const Text(
                      '你的语言包，已井然有序',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '${p.name} · ${_entries.length} 个 Key · ${p.locales.length} 种目标语言',
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
                            ? '正在保存…'
                            : _draft
                            ? '保存草稿语言包 .zip'
                            : '保存全部语言包 .zip',
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
                      label: const Text('保存当前 JSON'),
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
            label: const Text('返回校对'),
          ),
          TextButton.icon(
            onPressed: () => _go(_View.exports),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('查看导出记录'),
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
          title: '翻译任务',
          subtitle: '每一种语言的进度、失败与重试，都有迹可循。',
          action: FilledButton.icon(
            onPressed: () => _beginInput(false),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建翻译'),
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
                            ? '翻译进行中'
                            : c.paused
                            ? '已暂停的任务'
                            : c.failed > 0
                            ? '最近任务 · 部分失败'
                            : '最近任务 · 已完成',
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
                        child: const Text('查看任务'),
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
                  '已处理 ${c.completed}/${c.total} · 失败 ${c.failed}',
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
              title: '从一段中文开始',
              detail: '添加项目文案、选择目标语言，然后开始第一次真实翻译。',
              action: OutlinedButton(
                onPressed: () => _beginInput(false),
                child: const Text('开始翻译'),
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
                                  '${p.entries.length} 条文案 · ${p.locales.length} 种语言 · 已有 ${p.translatedCount}/${p.totalCount} 条译文',
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
                            child: const Text('查看项目'),
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
        const Text(
          '任务记录',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                              '${_taskStatus(pair.$2)} · 已处理 ${pair.$2.completed}/${pair.$2.total} · 复用 ${pair.$2.reused} · 失败 ${pair.$2.failed}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                                height: 1.8,
                              ),
                            ),
                            Text(
                              '${pair.$2.provider.isEmpty ? '翻译服务' : pair.$2.provider} · ${_date(pair.$2.createdAt)}',
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
                        child: const Text('查看文案'),
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
    'running' => '翻译中',
    'paused' => '已暂停',
    'stopped' => '已停止',
    _ => record.failed > 0 ? '部分失败' : '已完成',
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
        const _PageHeading(
          eyebrow: 'EXPORT HISTORY',
          title: '导出记录',
          subtitle: '每一次交付，都可以重新获取。保留最近的语言包快照。',
        ),
        const SizedBox(height: 25),
        if (records.isEmpty)
          _Panel(
            child: _Empty(
              icon: Icons.folder_zip_outlined,
              title: '语言包准备好时，就来这里',
              detail: '完成翻译校对并保存后，语言包快照会出现在这里。',
              action: OutlinedButton(
                onPressed: () => _go(_View.home),
                child: const Text('返回我的项目'),
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
                              '${project.name} · ${record.files.length} 个文件 · ${record.draft ? '草稿' : '正式'} · ${_date(record.createdAt)}',
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
                        tooltip: '重新保存语言包',
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
      DropdownButtonFormField<String>(
        key: ValueKey('primary-${c.settings.providerOrder.first}'),
        initialValue: c.settings.providerOrder.first,
        decoration: const InputDecoration(labelText: '首选翻译平台'),
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
        title: const Text('启用按顺序备用', style: TextStyle(fontSize: 13)),
        subtitle: const Text(
          '仅额度耗尽或语言不支持时切换；鉴权和配置错误会停止。',
          style: TextStyle(fontSize: 11),
        ),
        value: c.settings.providerFallback,
        onChanged: (value) => _guard(
          () => c.saveProviderOrder(c.settings.providerOrder, fallback: value),
        ),
      ),
      for (final provider in translationProviders) _providerCard(provider),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              _backupConfigured == true
                  ? '开发者访问码已验证，可使用授权服务'
                  : '开发者服务需访问码授权；自备密钥可独立配置。',
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _checkBackupConnection,
            child: const Text('检测服务'),
          ),
        ],
      ),
    ],
  );

  Widget _providerCard(String provider) {
    final order = c.settings.providerOrder;
    final index = order.indexOf(provider);
    final configured = providerCredentialsReady(
      provider,
      c.credentialsFor(provider),
    );
    final hasCredentialData = c.credentialsFor(provider).isNotEmpty;
    final description = switch (provider) {
      'MyMemory' => '可匿名使用；联系邮箱与私有词库密钥可选。支持 31 种目标语言；私有词库密钥不代表额度增加。',
      'ZTAITrans' => '自备 API 密钥或开发者访问码；不再提供匿名共享额度。',
      'DeepL' =>
        '请选择控制台对应的 free / pro 接口。新注册 Developer 额度为总计 100 万字符；旧 Free 为每月 50 万，具体以账户为准。',
      'Azure' => 'F0 层每月 200 万字符，到限停止；其他定价层以账户配置为准。',
      'Google' => 'Basic 每月 50 万 NMT 字符抵扣，需启用结算，超额收费；请在账户设置用量限额。',
      'Baidu' => '百度通用翻译：标准版每月 5 万、高级版 100 万、尊享版 200 万字符，超额收费；扩展语种可能需企业尊享版。',
      'Tencent' =>
        '腾讯文本翻译仅适用于既有账户，免费资源包已停发；服务将于 2027 年 10 月 1 日停用。当前支持 15 种目标语言。',
      _ => '阿里云通用版主账户每月 100 万字符，子账户共享；超额后付费，使用前请设置限额。',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: index >= 0,
                key: ValueKey('provider-enable-$provider'),
                onChanged: (enabled) => _guard(
                  () => c.saveProviderOrder(
                    enabled == true
                        ? [...order, provider]
                        : order.where((value) => value != provider).toList(),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '$provider${index < 0 ? '' : ' · 顺序 ${index + 1}'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (index > 0)
                IconButton(
                  tooltip: '上移 $provider',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: () {
                    final updated = [...order];
                    updated[index] = updated[index - 1];
                    updated[index - 1] = provider;
                    _guard(() => c.saveProviderOrder(updated));
                  },
                ),
            ],
          ),
          Text(
            description,
            style: const TextStyle(fontSize: 11, color: _muted, height: 1.7),
          ),
          ...[
            const SizedBox(height: 6),
            Text(
              configured
                  ? (c.credentialsSaved(provider)
                        ? '凭据：•••••• · 已在本机保存'
                        : '凭据：•••••• · 仅本次会话')
                  : provider == 'MyMemory'
                  ? '匿名模式（未配置私有词库密钥）'
                  : hasCredentialData
                  ? '凭据尚未填写完整'
                  : '尚未配置凭据',
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () => _providerCredentialDialog(provider),
                  child: Text('配置 $provider'),
                ),
                if (hasCredentialData)
                  TextButton(
                    onPressed: () =>
                        _guard(() => c.clearProviderCredentials(provider)),
                    child: Text('清除 $provider 凭据'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _credentialLabel(String provider, String field) => switch (field) {
    'apiKey' => provider == 'MyMemory' ? '私有词库 API 密钥（可留空匿名）' : 'API 密钥',
    'developerToken' => '开发者访问码',
    'tenantId' => 'Tenant ID（选填）',
    'region' =>
      provider == 'Tencent' ? '区域（默认 ap-guangzhou）' : '区域（选填，如 eastasia）',
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
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('配置 $provider'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (provider == 'ZTAITrans')
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开发者访问码模式'),
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
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        '服务区域固定为 cn-hangzhou，签名由代理完成。',
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ),
                  if (provider == 'DeepL')
                    DropdownButtonFormField<String>(
                      initialValue: plan,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '账户接口'),
                      items: const [
                        DropdownMenuItem(
                          value: 'free',
                          child: Text('免费接口 · api-free'),
                        ),
                        DropdownMenuItem(
                          value: 'pro',
                          child: Text('标准接口 · api'),
                        ),
                      ],
                      onChanged: (value) =>
                          update(() => plan = value ?? 'free'),
                    ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    title: const Text('在本机保存凭据'),
                    subtitle: const Text('默认仅本次会话。本机保存不额外加密；共享设备请保持关闭。'),
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
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
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
                                ? failure.message
                                : '请检查必填凭据和配置，然后重试。';
                            saving = false;
                          });
                        }
                      }
                    },
              child: const Text('保存配置'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _PageHeading(
        eyebrow: 'WORKSPACE PREFERENCES',
        title: '偏好设置',
        subtitle: '让工作台，更贴近你的使用习惯。',
      ),
      const SizedBox(height: 25),
      _columns(
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '翻译服务',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              const _Notice(
                '选中的原文仅发送给已启用的平台。MyMemory 无需密钥，其他平台使用你配置的密钥或开发者访问码；凭据默认只在本次会话使用。',
                icon: Icons.shield_outlined,
              ),
              const SizedBox(height: 23),
              TextFormField(
                key: ValueKey('email-${c.settings.email}'),
                initialValue: c.settings.email,
                readOnly: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'MyMemory 联系邮箱（选填）',
                  hintText: 'you@example.com',
                  helperText: '仅填写你自己的有效邮箱，会随翻译请求发送。',
                  helperMaxLines: 2,
                ),
                onFieldSubmitted: (value) => _saveSettings(email: value),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  final email = await _textDialog(
                    '设置 MyMemory 联系邮箱',
                    c.settings.email,
                    lines: 1,
                    allowEmpty: true,
                    helper: '提交后会随翻译请求发送。留空使用匿名额度。',
                  );
                  if (email != null) await _saveSettings(email: email.trim());
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('修改联系邮箱'),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 14),
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
                  const Text(
                    '连接与导出',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                      labelText: '翻译代理服务',
                      hintText: kIsWeb ? '使用当前网站的同源服务' : '内置在线服务（无需配置）',
                      helperText: kIsWeb
                          ? 'Web 使用同源代理转发你配置的凭据，不将凭据写入项目或导出。'
                          : '默认使用与在线工作台相同的代理。付费平台需自备密钥，可按需切换自定义服务器。',
                      helperMaxLines: 3,
                    ),
                    onFieldSubmitted: (value) => _saveSettings(baseUrl: value),
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () async {
                        final base = await _textDialog(
                          '自定义翻译代理（选填）',
                          c.settings.apiBaseUrl,
                          lines: 1,
                          allowEmpty: true,
                          helper:
                              '留空使用内置在线代理。自定义地址需为提供翻译代理的 HTTPS 根域名；密钥在平台配置中填写。',
                        );
                        if (base != null) {
                          await _saveSettings(baseUrl: base.trim());
                        }
                      },
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('自定义服务器（可选）'),
                    ),
                    if (c.settings.apiBaseUrl.trim().isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _saveSettings(baseUrl: ''),
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('恢复内置在线服务'),
                      ),
                  ],
                  const SizedBox(height: 18),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: c.settings.includeSource,
                    onChanged: (value) => _saveSettings(includeSource: value),
                    title: const Text(
                      '默认包含中文源语言包',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      '导出时同时生成 zh-Hans.json',
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                  ),
                  const Divider(),
                  _summary('Key 命名', 'snake_case'),
                  _summary('导出格式', 'UTF-8 JSON / ZIP'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _Panel(
              color: Color(0xFFEEF4E9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.devices_rounded, color: _green, size: 25),
                  SizedBox(height: 12),
                  Text(
                    '一个工作台，陪伴每一块屏幕',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 9),
                  Text(
                    'iOS · Android · Windows · macOS · Linux · Web\n项目数据保存在当前设备，各端暂不自动同步。卸载应用或清理浏览器数据前，请保存需要保留的语言包。',
                    style: TextStyle(fontSize: 12, color: _muted, height: 1.9),
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
          children: [left, const SizedBox(height: 20), right],
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

  Widget _footer(Widget left, Widget right) => Wrap(
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
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
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
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: constraints.maxWidth < 600 ? 25 : 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.7,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _muted,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null && constraints.maxWidth > 600) ...[
              const SizedBox(width: 20),
              action!,
            ],
          ],
        ),
        if (action != null && constraints.maxWidth <= 600) ...[
          const SizedBox(height: 17),
          action!,
        ],
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
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
                style: const TextStyle(
                  fontSize: 28,
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 15),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Column(
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF4E7),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Icon(icon, size: 31, color: _green),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _muted, height: 1.9),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    ),
  );
}
