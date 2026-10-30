import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/document_service.dart';
import 'services/export_service.dart';
import 'services/translation_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    TranslationService? translator,
    DocumentService? documents,
    ExportService? exporter,
  }) : _translator = translator ?? TranslationService(),
       _documents = documents ?? DocumentService(),
       _exporter = exporter ?? ExportService();
  static const storageKey = 'langpack_flutter_v1';
  final TranslationService _translator;
  final DocumentService _documents;
  final ExportService _exporter;
  SharedPreferences? _preferences;
  final List<Project> projects = [];
  Project? currentProject;
  AppSettings settings = AppSettings();
  bool loading = true, running = false, paused = false;
  bool _disposed = false, _storageHealthy = true;
  String? error;
  String message = '';
  int completed = 0, total = 0, failed = 0, reused = 0;
  String activeLabel = '';
  String? activeProjectId;
  CancelToken? _token;
  TaskRecord? _activeJob;
  final Map<String, TaskRecord> _lastBatchJobs = {};
  String? _batchProjectId;
  List<String>? _batchLocales;
  int _generation = 0;
  Timer? _saveTimer;
  Future<void> _saveQueue = Future.value();

  Future<void> initialize() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final raw = _preferences!.getString(storageKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['version'] != 1) {
          throw const FormatException('unsupported version');
        }
        projects.addAll(
          (data['projects'] as List).map(
            (item) => Project.fromJson(Map<String, dynamic>.from(item as Map)),
          ),
        );
        settings = AppSettings.fromJson(
          Map<String, dynamic>.from(data['settings'] as Map? ?? {}),
        );
      }
    } catch (_) {
      _storageHealthy = false;
      error = '本地数据未能读取，原始存档已保留。请导出当前工作备份。';
    }
    loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _changed({Project? project}) {
    (project ?? currentProject)?.updatedAt = DateTime.now();
    _notify();
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(flush()),
    );
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    if (!_storageHealthy || _preferences == null) return Future.value();
    final data = jsonEncode({
      'version': 1,
      'projects': projects.map((p) => p.toJson()).toList(),
      'settings': settings.toJson(),
    });
    _saveQueue = _saveQueue.then((_) async {
      try {
        if (!await _preferences!.setString(storageKey, data)) {
          throw StateError('write failed');
        }
      } catch (_) {
        error = '本地保存失败，可能已超出存储空间。请导出语言包备份。';
        _notify();
      }
    });
    return _saveQueue;
  }

  Project createProject(String name, {String description = ''}) {
    if (name.trim().isEmpty) throw ArgumentError('请输入项目名称。');
    final p = Project(
      name: name.trim(),
      description: description.trim(),
      locales: settings.recentLocales.isEmpty
          ? null
          : [...settings.recentLocales],
    );
    projects.insert(0, p);
    currentProject = p;
    _changed();
    return p;
  }

  void openProject(String id) {
    currentProject = projects.firstWhere((p) => p.id == id);
    _batchProjectId = null;
    _batchLocales = null;
    error = null;
    _notify();
  }

  void closeProject() {
    currentProject = null;
    _notify();
  }

  void deleteProject(String id) {
    _lastBatchJobs.remove(id);
    if (activeProjectId == id) {
      pauseTranslation();
      activeProjectId = null;
      _activeJob = null;
      paused = false;
      completed = total = failed = reused = 0;
      activeLabel = '';
      message = '';
    }
    projects.removeWhere((p) => p.id == id);
    if (currentProject?.id == id) currentProject = null;
    _changed();
  }

  void updateProject(String name, String description) {
    if (name.trim().isEmpty || currentProject == null) return;
    currentProject!
      ..name = name.trim()
      ..description = description.trim();
    _changed();
  }

  void setLocales(List<String> codes) {
    if (currentProject == null) return;
    if (running && activeProjectId == currentProject!.id) pauseTranslation();
    currentProject!.locales
      ..clear()
      ..addAll(normalizeTargetLocales(codes));
    _batchProjectId = null;
    _batchLocales = null;
    _changed();
  }

  List<String> get batchLocales =>
      _batchProjectId == currentProject?.id && _batchLocales != null
      ? List.unmodifiable(_batchLocales!)
      : List.unmodifiable(currentProject?.locales ?? <String>[]);

  List<String> get activeBatchLocales =>
      activeProjectId == currentProject?.id &&
          _activeJob?.locales.isNotEmpty == true
      ? List.unmodifiable(_activeJob!.locales)
      : List.unmodifiable(currentProject?.locales ?? <String>[]);

  void setBatchLocales(List<String> codes) {
    if (currentProject == null || running) return;
    _batchProjectId = currentProject!.id;
    _batchLocales = normalizeTargetLocales(codes);
    _notify();
  }

  void applyRecentLocales() {
    final recent = normalizeTargetLocales(settings.recentLocales);
    if (currentProject == null) return;
    setBatchLocales(recent.isEmpty ? currentProject!.locales : recent);
  }

  List<DocumentBlock> splitText(String text, {String mode = 'paragraph'}) =>
      _documents.splitText(text, mode: mode);
  Future<List<DocumentBlock>> pickDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'markdown', 'docx'],
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return [];
    final file = result.files.single;
    if (file.size > 10 * 1024 * 1024) {
      throw const FormatException('文档不能超过 10 MB。');
    }
    final stream = file.readStream;
    if (stream == null) throw const FormatException('文档无法读取，请重新选择。');
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (buffer.length + chunk.length > 10 * 1024 * 1024) {
        throw const FormatException('文档不能超过 10 MB。');
      }
      buffer.add(chunk);
    }
    // Native platforms parse off the UI isolate. Flutter Web's compute uses the
    // same event loop but the same input limits and pure parser still apply.
    return compute(_parseDocument, (file.name, buffer.takeBytes()));
  }

  void addBlocks(List<DocumentBlock> blocks, {String prefix = ''}) {
    final p = currentProject;
    if (p == null) return;
    final active = blocks
        .where((b) => b.selected && b.text.trim().isNotEmpty)
        .toList();
    if (p.entries.length + active.length > 1000) {
      throw const FormatException('每个项目最多支持 1000 条文案。');
    }
    final used = p.entries.map((e) => e.key).toSet();
    for (final b in active) {
      final key = _documents.uniqueKey(b.text, used, prefix: prefix);
      used.add(key);
      p.entries.add(Entry(key: key, source: b.text.trim()));
    }
    _changed();
  }

  void updateEntryKey(Entry entry, String key) {
    entry.key = key.trim();
    _changed();
  }

  void updateEntrySource(Entry entry, String source) {
    if (entry.source == source) return;
    entry.source = source;
    entry.sourceRevision++;
    entry.translations.clear();
    _changed();
  }

  void selectEntry(Entry entry, bool selected) {
    entry.selected = selected;
    _changed();
  }

  void deleteEntry(Entry entry) {
    currentProject?.entries.remove(entry);
    _changed();
  }

  void editTranslation(Entry entry, String locale, String text) {
    final value = entry.value(locale);
    value
      ..text = text
      ..edited = true
      ..reviewed = false
      ..provider = '人工编辑'
      ..sourceText = entry.source
      ..sourceRevision = entry.sourceRevision
      ..error = ''
      ..status = (text.trim().isEmpty
          ? TranslationStatus.pending
          : TranslationStatus.done);
    value.revision++;
    _changed();
  }

  void reviewTranslation(Entry entry, String locale, bool reviewed) {
    if (reviewed &&
        (entry.value(locale).text.trim().isEmpty ||
            !listEquals(
              _documents.placeholders(entry.source),
              _documents.placeholders(entry.value(locale).text),
            ))) {
      error = '请先补全译文，并修复与原文不一致的占位符，再确认校对。';
      _notify();
      return;
    }
    final value = entry.value(locale)..reviewed = reviewed;
    value.revision++;
    if (reviewed && value.text.trim().isNotEmpty) {
      value
        ..status = TranslationStatus.done
        ..sourceText = entry.source
        ..sourceRevision = entry.sourceRevision
        ..error = '';
    }
    _changed();
  }

  bool _boundTo(Entry entry, TranslationValue value) =>
      value.sourceText == entry.source &&
      value.sourceRevision == entry.sourceRevision;

  bool _retained(Entry entry, TranslationValue value) =>
      value.edited ||
      value.reviewed ||
      value.status == TranslationStatus.done &&
          value.text.trim().isNotEmpty &&
          (_boundTo(entry, value) ||
              value.sourceText == null && value.sourceRevision == null);

  Map<(String, String), TranslationValue?> _translationMemory(
    Project p, {
    String? source,
    String? locale,
  }) {
    final memory = <(String, String), TranslationValue?>{};
    for (final entry in p.entries) {
      if (source != null && entry.source != source) continue;
      for (final pair in entry.translations.entries) {
        if (locale != null && pair.key != locale) continue;
        final value = pair.value;
        if (value.edited ||
            value.status != TranslationStatus.done ||
            !['MyMemory', 'ZTAITrans'].contains(value.provider) ||
            !_boundTo(entry, value) ||
            value.text.trim().isEmpty ||
            !listEquals(
              _documents.placeholders(entry.source),
              _documents.placeholders(value.text),
            )) {
          continue;
        }
        final key = (entry.source, pair.key);
        if (!memory.containsKey(key)) {
          memory[key] = value;
        } else if (memory[key]?.text != value.text) {
          // Different translations can carry different context. Do not pick one.
          memory[key] = null;
        }
      }
    }
    return memory;
  }

  IncrementalPlan incrementalPlan() {
    final p = currentProject;
    if (p == null) return const IncrementalPlan();
    final memory = _translationMemory(p);
    final unique = <(String, String)>{};
    var retained = 0, reusable = 0, pending = 0;
    for (final entry in p.selectedEntries) {
      for (final code in batchLocales) {
        final value = entry.translations[code];
        if (value != null && _retained(entry, value)) {
          retained++;
        } else if (memory[(entry.source, code)] != null) {
          reusable++;
        } else {
          pending++;
          unique.add((entry.source, code));
        }
      }
    }
    return IncrementalPlan(
      retained: retained,
      reusable: reusable,
      pending: pending,
      uniquePending: unique.length,
    );
  }

  Future<void> startTranslation({
    bool retryFailedOnly = false,
    bool resume = false,
    String? entryId,
    String? locale,
    bool overwrite = false,
  }) async {
    final p = currentProject;
    if (p == null || running) return;
    final isContinuation = retryFailedOnly || resume;
    final savedBatch =
        _lastBatchJobs[p.id] ?? p.jobs.where((job) => job.batch).firstOrNull;
    final continuationLocales = savedBatch?.locales.isNotEmpty == true
        ? savedBatch!.locales
        : p.locales;
    final locales = normalizeTargetLocales(
      locale != null
          ? [locale]
          : isContinuation
          ? continuationLocales
          : batchLocales,
    );
    final targetEntries = p.selectedEntries
        .where((entry) => entryId == null || entry.id == entryId)
        .toList();
    if (locales.isEmpty ||
        targetEntries.isEmpty ||
        targetEntries.any((entry) => entry.source.trim().isEmpty)) {
      error = '请先选择文案及目标语言。';
      _notify();
      return;
    }
    final isNewBatch =
        !retryFailedOnly &&
        !resume &&
        !overwrite &&
        entryId == null &&
        locale == null;
    if (isNewBatch) {
      final sourceIssues = _exporter
          .validate(p)
          .where(
            (issue) =>
                ['key', 'duplicate', 'empty', 'source'].contains(issue.type),
          );
      if (sourceIssues.isNotEmpty) {
        error = sourceIssues.first.message;
        _notify();
        return;
      }
      settings.recentLocales
        ..clear()
        ..addAll(locales);
      _changed(project: p);
    }
    for (final code in locales) {
      if (!p.locales.contains(code)) p.locales.add(code);
    }
    final work = <_Work>[];
    final batchResults = <(String, String), (Entry, int, TranslationResult)>{};
    for (final entry in targetEntries) {
      for (final code in locales) {
        if (!p.locales.contains(code)) continue;
        final value = entry.value(code);
        if (retryFailedOnly && value.status != TranslationStatus.failed) {
          continue;
        }
        if (!overwrite && _retained(entry, value)) {
          continue;
        }
        work.add(
          _Work(
            entry,
            code,
            entry.source,
            entry.sourceRevision,
            value.revision,
          ),
        );
      }
    }
    if (work.isEmpty) {
      completed = total = failed = reused = 0;
      error = null;
      message = '没有待翻译文案，已保留成功及人工校对的结果。';
      _notify();
      return;
    }
    final generation = ++_generation, token = CancelToken();
    _token = token;
    running = true;
    paused = false;
    error = null;
    message = '';
    completed = 0;
    failed = 0;
    reused = 0;
    total = work.length;
    activeProjectId = p.id;
    final job = TaskRecord(
      total: total,
      locales: locales,
      batch: entryId == null && locale == null,
    );
    if (job.batch) _lastBatchJobs[p.id] = job;
    _activeJob = job;
    p.jobs.insert(0, job);
    if (p.jobs.length > 20) p.jobs.removeRange(20, p.jobs.length);
    _changed(project: p);
    try {
      for (final item in work) {
        if (token.cancelled || generation != _generation) break;
        if (!_canApply(p, item)) {
          completed++;
          continue;
        }
        final value = item.entry.value(item.locale)
          ..status = TranslationStatus.translating
          ..error = '';
        activeLabel = '${item.entry.key} → ${languageName(item.locale)}';
        _notify();
        try {
          final pair = (item.source, item.locale);
          final batch = batchResults[pair];
          final donor = batch?.$1.translations[item.locale];
          final freshResult =
              batch != null &&
                  p.entries.contains(batch.$1) &&
                  donor != null &&
                  donor.revision == batch.$2 &&
                  !donor.edited &&
                  _boundTo(batch.$1, donor)
              ? batch.$3
              : null;
          final remembered = overwrite
              ? null
              : _translationMemory(
                  p,
                  source: item.source,
                  locale: item.locale,
                )[pair];
          final reusedResult = overwrite ? null : freshResult;
          final result =
              reusedResult ??
              (remembered == null
                  ? await _translator.translate(
                      item.source,
                      item.locale,
                      token: token,
                      email: settings.email,
                      apiBaseUrl: settings.apiBaseUrl,
                      bypassCache: overwrite,
                      onStatus: (status) {
                        if (generation == _generation) {
                          message = status;
                          _notify();
                        }
                      },
                    )
                  : TranslationResult(
                      text: remembered.text,
                      provider: remembered.provider,
                      cached: true,
                    ));
          if (token.cancelled || generation != _generation) break;
          if (_canApply(p, item)) {
            value
              ..text = result.text
              ..provider = result.provider
              ..status = TranslationStatus.done
              ..edited = false
              ..reviewed = false
              ..sourceText = item.source
              ..sourceRevision = item.sourceRevision
              ..error = '';
            value.revision++;
            job.provider = result.provider;
            batchResults[pair] = (item.entry, value.revision, result);
            if (remembered != null || reusedResult != null) {
              reused++;
              job.reused = reused;
            }
          }
          completed++;
        } on TranslationFailure catch (failure) {
          if (token.cancelled || generation != _generation) break;
          if (_canApply(p, item)) {
            value
              ..status = TranslationStatus.failed
              ..error = failure.message;
          }
          failed++;
          completed++;
          if (failure.fatal || failure.quota) {
            error = failure.message;
            job.status = 'stopped';
            break;
          }
        } catch (_) {
          if (token.cancelled || generation != _generation) break;
          if (_canApply(p, item)) {
            value
              ..status = TranslationStatus.failed
              ..error = '翻译未完成，请检查网络后重试。';
          }
          failed++;
          completed++;
        }
        job
          ..completed = completed
          ..failed = failed;
        _changed(project: p);
        await flush();
      }
    } finally {
      if (generation == _generation) {
        running = false;
        for (final item in work) {
          final value = item.entry.translations[item.locale];
          if (value?.status == TranslationStatus.translating) {
            value!.status = TranslationStatus.pending;
          }
        }
        job
          ..completed = completed
          ..failed = failed;
        if (job.status == 'running') {
          job.status = token.cancelled ? 'paused' : 'completed';
        }
        message =
            error ??
            (failed > 0
                ? '翻译结束，$failed 项失败，可只重试失败项。'
                : '翻译完成，复用 $reused 条译文，可以校对和导出。');
        activeLabel = '';
        _changed(project: p);
        await flush();
      }
    }
  }

  bool _canApply(Project p, _Work item) =>
      projects.contains(p) &&
      p.entries.contains(item.entry) &&
      item.entry.selected &&
      p.locales.contains(item.locale) &&
      item.entry.source == item.source &&
      item.entry.sourceRevision == item.sourceRevision &&
      item.entry.value(item.locale).revision == item.translationRevision;
  void pauseTranslation() {
    if (!running) return;
    _token?.cancel();
    _generation++;
    running = false;
    paused = true;
    _activeJob
      ?..status = 'paused'
      ..completed = completed
      ..failed = failed;
    for (final p in projects) {
      for (final entry in p.entries) {
        for (final value in entry.translations.values) {
          if (value.status == TranslationStatus.translating) {
            value.status = TranslationStatus.pending;
          }
        }
      }
    }
    activeLabel = '';
    message = '翻译已暂停，成功结果已保留。继续时处理未完成项。';
    _changed();
    unawaited(flush());
  }

  List<ValidationIssue> validate() => currentProject == null
      ? [const ValidationIssue('请先选择项目。')]
      : _exporter.validate(currentProject!);
  Map<String, String> previewPackages({bool draft = false}) =>
      currentProject == null
      ? {}
      : _exporter.packages(
          currentProject!,
          includeSource: settings.includeSource,
          draft: draft,
        );
  Future<bool> exportZip({bool draft = false}) async {
    final p = currentProject;
    if (p == null) return false;
    try {
      final files = previewPackages(draft: draft);
      final name = '${_fileName(p.name)}${draft ? '_draft' : ''}.zip';
      final success = await _exporter.saveFile(name, _exporter.zip(files));
      if (success) {
        _recordExport(p, ExportRecord(name: name, files: files, draft: draft));
      }
      return success;
    } catch (failure) {
      error = _friendlyError(failure);
      _notify();
      return false;
    }
  }

  Future<bool> exportJson(String locale) async {
    final p = currentProject;
    if (p == null) return false;
    try {
      final files = previewPackages(), name = '$locale.json';
      if (!files.containsKey(name)) throw const FormatException('请先选择该语言。');
      final success = await _exporter.saveFile(
        name,
        Uint8List.fromList(utf8.encode(files[name]!)),
      );
      if (success) {
        _recordExport(p, ExportRecord(name: name, files: {name: files[name]!}));
      }
      return success;
    } catch (failure) {
      error = _friendlyError(failure);
      _notify();
      return false;
    }
  }

  void _recordExport(Project p, ExportRecord record) {
    p.exports.insert(0, record);
    if (p.exports.length > 20) p.exports.removeRange(20, p.exports.length);
    message = '语言包已导出，快照已保存。';
    _changed(project: p);
    unawaited(flush());
  }

  Future<bool> downloadRecord(ExportRecord record) async {
    try {
      final bytes = record.name.endsWith('.json') && record.files.length == 1
          ? Uint8List.fromList(utf8.encode(record.files.values.single))
          : _exporter.zip(record.files);
      return await _exporter.saveFile(record.name, bytes);
    } catch (failure) {
      error = _friendlyError(failure);
      _notify();
      return false;
    }
  }

  Future<void> saveSettings({
    required String email,
    required String apiBaseUrl,
    required bool includeSource,
  }) async {
    final cleanEmail = email.trim(),
        cleanBase = apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (cleanEmail.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
      throw const FormatException('请输入有效联系邮箱，或留空。');
    }
    if (cleanBase.isNotEmpty) {
      final uri = Uri.tryParse(cleanBase);
      final local =
          uri != null &&
          ['localhost', '127.0.0.1', '10.0.2.2', '::1'].contains(uri.host);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !(uri.scheme == 'https' || local && uri.scheme == 'http') ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        throw const FormatException(
          '请输入 HTTPS 服务域名。本机调试支持 localhost、127.0.0.1 或 10.0.2.2 的 HTTP 地址。',
        );
      }
      if (kIsWeb && uri.origin != Uri.base.origin) {
        throw const FormatException('Web 备用服务需要与当前应用同源部署。');
      }
    }
    if (running) pauseTranslation();
    settings = AppSettings(
      email: cleanEmail,
      apiBaseUrl: cleanBase,
      includeSource: includeSource,
      recentLocales: settings.recentLocales,
    );
    message = '设置已保存。';
    _changed();
    await flush();
  }

  Future<bool> checkBackup() => _translator.checkBackup(settings.apiBaseUrl);
  void clearError() {
    error = null;
    message = '';
    _notify();
  }

  String _fileName(String name) {
    final safe = name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff-]'), '_');
    return safe.isEmpty
        ? 'langpack'
        : safe.substring(0, safe.length.clamp(0, 60));
  }

  String _friendlyError(Object failure) =>
      failure is FormatException ? failure.message : '导出失败，请检查保存位置后重试。';
  @override
  void dispose() {
    _token?.cancel();
    _saveTimer?.cancel();
    unawaited(flush());
    _disposed = true;
    _translator.dispose();
    super.dispose();
  }
}

List<DocumentBlock> _parseDocument((String, Uint8List) input) =>
    DocumentService().parseBytes(input.$1, input.$2);

class _Work {
  const _Work(
    this.entry,
    this.locale,
    this.source,
    this.sourceRevision,
    this.translationRevision,
  );
  final Entry entry;
  final String locale, source;
  final int sourceRevision, translationRevision;
}
