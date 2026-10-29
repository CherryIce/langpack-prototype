import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import 'document_service.dart';

class ExportService {
  final _documents = DocumentService();

  List<ValidationIssue> validate(Project project) {
    final issues = <ValidationIssue>[];
    final entries = project.selectedEntries.toList();
    final keys = <String>{};
    if (entries.isEmpty) {
      issues.add(const ValidationIssue('请至少选择一条文案。', type: 'empty'));
    }
    if (project.locales.isEmpty) {
      issues.add(const ValidationIssue('请至少选择一种目标语言。', type: 'language'));
    }
    for (final locale in project.locales.toSet()) {
      if (!supportedLanguages.any((language) => language.code == locale)) {
        issues.add(
          ValidationIssue('目标语言不受支持：$locale', locale: locale, type: 'language'),
        );
      }
    }
    for (final entry in entries) {
      void issue(String message, String type, [String? locale]) => issues.add(
        ValidationIssue(message, entryId: entry.id, locale: locale, type: type),
      );
      if (!RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(entry.key)) {
        issue('key 需以小写英文字母开头，仅包含小写字母、数字和下划线，最多 80 字符。', 'key');
      }
      if (!keys.add(entry.key)) issue('存在重复 key：${entry.key}', 'duplicate');
      if (entry.source.trim().isEmpty) issue('中文原文不能为空。', 'source');
      final expected = _documents.placeholders(entry.source);
      for (final locale in project.locales.toSet()) {
        final value = entry.translations[locale];
        if (value == null || value.text.trim().isEmpty) {
          issue('该语言译文尚未补全。', 'missing', locale);
          continue;
        }
        if (value.status == TranslationStatus.translating) {
          issue('该语言仍在翻译中。', 'translating', locale);
        } else if (value.status == TranslationStatus.failed &&
            !value.edited &&
            !value.reviewed) {
          issue('该译文请求失败，请重试或人工确认现有内容。', 'translation', locale);
        } else if (value.provider == 'LegacyDemo' &&
            !value.edited &&
            !value.reviewed) {
          issue('历史演示译文需重译或人工确认。', 'legacy', locale);
        }
        if (!listEquals(expected, _documents.placeholders(value.text))) {
          issue('译文中的占位符与原文不一致。', 'placeholders', locale);
        }
      }
    }
    return issues;
  }

  Map<String, String> packages(
    Project project, {
    bool includeSource = true,
    bool draft = false,
  }) {
    final issues = validate(project);
    if (!draft && issues.isNotEmpty) {
      throw FormatException('请先修复 ${issues.length} 项校验问题，再正式导出。');
    }
    // A draft may have missing translations; invalid keys still cannot form a
    // lossless JSON object and must be fixed before either kind of export.
    if (issues.any(
      (issue) => [
        'key',
        'duplicate',
        'language',
        'empty',
        'source',
      ].contains(issue.type),
    )) {
      throw const FormatException('请先修复 key、原文、文案选择和目标语言，再导出语言包。');
    }
    final entries = project.selectedEntries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final files = <String, String>{};
    final locales = <String>{if (includeSource) 'zh-Hans', ...project.locales};
    const encoder = JsonEncoder.withIndent('  ');
    for (final locale in locales) {
      final values = <String, String>{
        for (final entry in entries)
          entry.key: locale == 'zh-Hans'
              ? entry.source
              : entry.translations[locale]?.text ?? '',
      };
      files['$locale.json'] = '${encoder.convert(values)}\n';
    }
    if (draft) {
      files['validation-report.json'] =
          '${encoder.convert({'draft': true, 'project': project.name, 'generatedAt': DateTime.now().toUtc().toIso8601String(), 'issues': issues.map((issue) => issue.toJson()).toList()})}\n';
    }
    return files;
  }

  Uint8List zip(Map<String, String> files) {
    if (files.isEmpty || files.length > 100) {
      throw const FormatException('导出文件数量无效。');
    }
    final archive = Archive();
    for (final entry in files.entries) {
      if (!RegExp(r'^[a-zA-Z0-9_-]+\.json$').hasMatch(entry.key)) {
        throw const FormatException('导出文件名无效。');
      }
      final bytes = utf8.encode(entry.value);
      archive.add(ArchiveFile(entry.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<bool> saveFile(String name, Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('导出内容为空。');
    if (!RegExp(r'^[^/\\\x00-\x1f]+\.(json|zip)$').hasMatch(name)) {
      throw const FormatException('请选择有效的 JSON 或 ZIP 文件名。');
    }
    // file_picker 11 writes supplied bytes on all native targets; on web its
    // Blob download intentionally returns null even after starting a download.
    final savedPath = await FilePicker.saveFile(
      dialogTitle: '导出语言包',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: [name.split('.').last],
      bytes: bytes,
    );
    return kIsWeb || savedPath != null;
  }
}
