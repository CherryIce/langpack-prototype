// Explicit opt-in: these tests send sample Chinese copy to real translation APIs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:langpack/models.dart';
import 'package:langpack/services/document_service.dart';
import 'package:langpack/services/export_service.dart';
import 'package:langpack/services/translation_service.dart';

class _QuotaPrimary extends http.BaseClient {
  final _real = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host == 'api.mymemory.translated.net') {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'responseStatus': 403,
              'quotaFinished': true,
              'responseDetails':
                  'YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY',
              'responseData': {'translatedText': ''},
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return _real.send(request);
  }

  @override
  void close() => _real.close();
}

void main() {
  const run = bool.fromEnvironment('RUN_LIVE_TRANSLATION');
  const runPublicProxy = bool.fromEnvironment('RUN_PUBLIC_PROXY_TEST');
  const base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:4180',
  );
  const output = String.fromEnvironment(
    'LIVE_OUTPUT_DIR',
    defaultValue: '../outputs/flutter-live',
  );
  test(
    'native built-in public proxy works without any client credential or base URL',
    () async {
      final service = TranslationService(client: _QuotaPrimary());
      addTearDown(service.dispose);
      expect(await service.checkBackup(''), isTrue);
      final result = await service.translate('登录', 'en', token: CancelToken());
      expect(result.provider, 'ZTAITrans');
      expect(result.text.trim(), isNotEmpty);
      final dir = Directory(output)..createSync(recursive: true);
      File('${dir.path}/flutter-default-public-proxy.json').writeAsStringSync(
        jsonEncode({
          'origin': defaultBackupServiceOrigin,
          'configuredBaseUrl': '',
          'clientCredential': false,
          'quotaTrigger': 'simulated primary quota',
          'translation': 'real public ZTAITrans proxy',
          'text': result.text,
          'provider': result.provider,
          'testedAt': DateTime.now().toIso8601String(),
        }),
      );
    },
    skip: !runPublicProxy,
    timeout: const Timeout(Duration(minutes: 12)),
  );
  test(
    'real text translation through primary and configured backup',
    () async {
      final service = TranslationService();
      addTearDown(service.dispose);
      expect(await service.checkBackup(base), isTrue);
      final result = await service.translate(
        '登录',
        'en',
        token: CancelToken(),
        apiBaseUrl: base,
      );
      expect(result.text.trim(), isNotEmpty);
      expect(result.text, isNot(contains('WARNING')));
      final dir = Directory(output)..createSync(recursive: true);
      File('${dir.path}/real-text.json').writeAsStringSync(
        jsonEncode({
          'source': '登录',
          'locale': 'en',
          'text': result.text,
          'provider': result.provider,
          'requestCount': result.requestCount,
          'testedAt': DateTime.now().toIso8601String(),
        }),
      );
    },
    skip: !run,
    timeout: const Timeout(Duration(minutes: 12)),
  );

  test(
    'simulated primary quota to real backup, DOCX to independent JSON and ZIP',
    () async {
      final client = _QuotaPrimary();
      final service = TranslationService(client: client);
      addTearDown(service.dispose);
      final long =
          '${List.filled(9, '翻译完成后，请仔细检查每一种语言的表达和格式。').join()}\n欢迎 {name}，您有 %d 条消息。';
      final paragraphs = ['欢迎使用多语言翻译工作台。', '登录', long];
      final xml =
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${paragraphs.map((p) => '<w:p><w:r><w:t xml:space="preserve">$p</w:t></w:r></w:p>').join()}</w:body></w:document>';
      final archive = Archive()
        ..addFile(ArchiveFile.string('word/document.xml', xml));
      final docx = Uint8List.fromList(ZipEncoder().encode(archive));
      final documents = DocumentService();
      final blocks = documents.parseBytes('全流程验收.docx', docx);
      expect(blocks, hasLength(3));
      expect(utf8.encode(blocks.last.text).length, greaterThan(500));
      final project = Project(name: 'Flutter真实文档验收', locales: ['en', 'ja']);
      final used = <String>{};
      for (final block in blocks) {
        final key = documents.uniqueKey(block.text, used);
        used.add(key);
        project.entries.add(Entry(key: key, source: block.text));
      }
      for (final entry in project.entries) {
        for (final locale in project.locales) {
          final result = await service.translate(
            entry.source,
            locale,
            token: CancelToken(),
            apiBaseUrl: base,
          );
          expect(result.provider, 'ZTAITrans');
          entry.value(locale)
            ..text = result.text
            ..provider = result.provider
            ..status = TranslationStatus.done;
        }
      }
      final exporter = ExportService();
      expect(exporter.validate(project), isEmpty);
      // Exercise the same editing and review semantics used by the UI.
      project.entries[1].value('en').reviewed = true;
      final files = exporter.packages(project);
      expect(files.keys, containsAll(['en.json', 'ja.json', 'zh-Hans.json']));
      final zip = exporter.zip(files);
      final decoded = ZipDecoder().decodeBytes(zip);
      for (final name in ['en.json', 'ja.json', 'zh-Hans.json']) {
        final member = decoded.findFile(name)!;
        final values = jsonDecode(utf8.decode(member.content)) as Map;
        expect(values.length, 3);
        expect(
          values.values.every((value) => value.toString().trim().isNotEmpty),
          isTrue,
        );
      }
      final dir = Directory(output)..createSync(recursive: true);
      File('${dir.path}/sample.docx').writeAsBytesSync(docx);
      for (final file in files.entries) {
        File('${dir.path}/${file.key}').writeAsStringSync(file.value);
      }
      File('${dir.path}/langpack-real-docx.zip').writeAsBytesSync(zip);
      File('${dir.path}/real-document-report.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'testedAt': DateTime.now().toIso8601String(),
          'quotaTrigger': 'simulated MyMemory quota',
          'translations': 'real ZTAITrans via server-only proxy',
          'paragraphs': 3,
          'locales': project.locales,
          'longParagraphUtf8Bytes': utf8.encode(blocks.last.text).length,
          'validationIssues': 0,
          'files': files.keys.toList(),
          'zipBytes': zip.length,
        }),
      );
    },
    skip: !run,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
