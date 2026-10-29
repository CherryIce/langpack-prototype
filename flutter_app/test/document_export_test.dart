import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/document_service.dart';
import 'package:langpack/services/export_service.dart';

const _header =
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>';
const _footer = '</w:body></w:document>';

Uint8List docx(String body) {
  final bytes = utf8.encode('$_header$body$_footer');
  final archive = Archive()
    ..add(ArchiveFile('word/document.xml', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

int centralOffset(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  return view.getUint32(bytes.length - 6, Endian.little);
}

Project completeProject() => Project(
  name: '测试项目',
  locales: ['en', 'ja'],
  entries: [
    Entry(
      key: 'welcome',
      source: '欢迎，{name}',
      translations: {
        'en': TranslationValue(
          text: 'Welcome, {name}',
          provider: 'MyMemory',
          status: TranslationStatus.done,
        ),
        'ja': TranslationValue(
          text: 'ようこそ、{name}',
          provider: 'ZTAITrans',
          status: TranslationStatus.done,
        ),
      },
    ),
    Entry(
      key: 'login',
      source: '登录',
      translations: {
        'en': TranslationValue(
          text: 'Log in',
          provider: 'MyMemory',
          status: TranslationStatus.done,
        ),
        'ja': TranslationValue(
          text: 'ログイン',
          provider: 'MyMemory',
          status: TranslationStatus.done,
        ),
      },
    ),
  ],
);

void main() {
  final documents = DocumentService();
  final exports = ExportService();

  group('文本与 Markdown', () {
    test('按空行拆段，保留段内换行，按行模式逐行拆分', () {
      final input = '\uFEFF 第一行\r\n第二行\r\n  \r\n第三行 ';
      expect(documents.splitText(input).map((block) => block.text), [
        '第一行\n第二行',
        '第三行',
      ]);
      expect(
        documents.splitText(input, mode: 'line').map((block) => block.text),
        ['第一行', '第二行', '第三行'],
      );
    });
    test('Markdown 标题、列表与表格单元拆块，代码围栏不进入翻译', () {
      final blocks = documents.parseBytes(
        'text.md',
        Uint8List.fromList(
          utf8.encode(
            '# 标题\n\n段落第一行\n第二行\n\n- 列表\n\n```dart\nsecret();\n```\n\n| 姓名 | 年龄 |\n| --- | --- |\n| 小明 | 18 |',
          ),
        ),
      );
      expect(blocks.map((block) => block.text), [
        '标题',
        '段落第一行\n第二行',
        '列表',
        '姓名',
        '年龄',
        '小明',
        '18',
      ]);
      expect(blocks.first.type, 'heading');
      expect(blocks[2].type, 'list');
      expect(blocks.last.type, 'table-cell');
    });
    test('支持 UTF-16 BOM 和 UTF-8 BOM', () {
      final units = '中文'.codeUnits;
      final bytes = Uint8List.fromList([
        0xff,
        0xfe,
        for (final unit in units) ...[unit & 255, unit >> 8],
      ]);
      expect(documents.parseBytes('text.txt', bytes).single.text, '中文');
      expect(
        documents
            .parseBytes(
              'text.txt',
              Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('中文')]),
            )
            .single
            .text,
        '中文',
      );
    });
    test('拒绝乱码、空文档、不支持的格式和超限输入', () {
      expect(
        () => documents.parseBytes(
          'bad.txt',
          Uint8List.fromList([0xff, 0xfe, 0xff]),
        ),
        throwsFormatException,
      );
      expect(
        () => documents.parseBytes('bad.txt', Uint8List.fromList([0xff])),
        throwsFormatException,
      );
      expect(
        () => documents.parseBytes('empty.txt', Uint8List(0)),
        throwsFormatException,
      );
      expect(
        () => documents.parseBytes('file.pdf', Uint8List(0)),
        throwsFormatException,
      );
      expect(
        () => documents.parseBytes(
          'large.txt',
          Uint8List(DocumentService.maxFileBytes + 1),
        ),
        throwsFormatException,
      );
      expect(
        () => documents.splitText(List.filled(1001, '段落').join('\n\n')),
        throwsFormatException,
      );
    });
  });

  group('DOCX 本地解析与边界', () {
    test('正文、标题、表格、换行和制表符，不包含删除修订', () {
      final blocks = documents.parseBytes(
        'test.docx',
        docx(
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>标题</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>第一行</w:t><w:br/><w:t>第二行</w:t><w:tab/><w:t>内容</w:t></w:r><w:del><w:r><w:t>删除内容</w:t></w:r></w:del></w:p>'
          '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>单元格</w:t></w:r></w:p><w:p><w:r><w:t>另一段</w:t></w:r></w:p></w:tc></w:tr></w:tbl>',
        ),
      );
      expect(blocks.map((block) => block.text), [
        '标题',
        '第一行\n第二行\t内容',
        '单元格\n另一段',
      ]);
      expect(blocks.map((block) => block.type), [
        'heading',
        'paragraph',
        'table-cell',
      ]);
    });
    test('只读正文，不解压其他成员', () {
      final body = utf8.encode(
        '$_header<w:p><w:r><w:t>正文</w:t></w:r></w:p>$_footer',
      );
      final archive = Archive()
        ..add(
          ArchiveFile('word/media/ignored.bin', 10000, List.filled(10000, 1)),
        )
        ..add(ArchiveFile('word/document.xml', body.length, body));
      expect(
        documents
            .parseBytes(
              'test.docx',
              Uint8List.fromList(ZipEncoder().encode(archive)),
            )
            .single
            .text,
        '正文',
      );
    });
    test('表格单元中的整段删除修订不会进入翻译', () {
      final bytes = docx(
        '<w:tbl><w:tr><w:tc>'
        '<w:del><w:p><w:r><w:t>已删除段落</w:t></w:r></w:p></w:del>'
        '<w:p><w:r><w:t>保留段落</w:t></w:r></w:p>'
        '</w:tc></w:tr></w:tbl>',
      );
      expect(documents.parseBytes('test.docx', bytes).single.text, '保留段落');
    });
    test('支持未压缩的 DOCX 正文', () {
      final body = utf8.encode(
        '$_header<w:p><w:r><w:t>正文</w:t></w:r></w:p>$_footer',
      );
      final file = ArchiveFile('word/document.xml', body.length, body)
        ..compression = CompressionType.none;
      final archive = Archive()..add(file);
      final encoded = ZipEncoder().encode(archive, level: 0);
      expect(
        documents
            .parseBytes('test.docx', Uint8List.fromList(encoded))
            .single
            .text,
        '正文',
      );
    });
    test('拒绝中央目录声明超过 20 MB 的正文，尚未解压', () {
      final bytes = docx('<w:p><w:r><w:t>正文</w:t></w:r></w:p>');
      ByteData.sublistView(bytes).setUint32(
        centralOffset(bytes) + 24,
        DocumentService.maxDocumentBytes + 1,
        Endian.little,
      );
      expect(
        () => documents.parseBytes('test.docx', bytes),
        throwsFormatException,
      );
    });
    test('实际展开超过声明大小时中止解压', () {
      final bytes = docx(
        '<w:p><w:r><w:t>${List.filled(10000, '字').join()}</w:t></w:r></w:p>',
      );
      ByteData.sublistView(
        bytes,
      ).setUint32(centralOffset(bytes) + 24, 10, Endian.little);
      expect(
        () => documents.parseBytes('test.docx', bytes),
        throwsFormatException,
      );
    });
    test('拒绝加密、截断、CRC 错误、无正文、恶意实体声明', () {
      final encrypted = docx('<w:p/>');
      ByteData.sublistView(
        encrypted,
      ).setUint16(centralOffset(encrypted) + 8, 1, Endian.little);
      expect(
        () => documents.parseBytes('test.docx', encrypted),
        throwsFormatException,
      );
      final truncated = docx('<w:p/>');
      expect(
        () => documents.parseBytes(
          'test.docx',
          truncated.sublist(0, truncated.length - 7),
        ),
        throwsFormatException,
      );
      final corrupt = docx('<w:p/>');
      ByteData.sublistView(
        corrupt,
      ).setUint32(centralOffset(corrupt) + 16, 42, Endian.little);
      expect(
        () => documents.parseBytes('test.docx', corrupt),
        throwsFormatException,
      );
      final archive = Archive()..add(ArchiveFile('empty.txt', 3, [1, 2, 3]));
      expect(
        () => documents.parseBytes(
          'test.docx',
          Uint8List.fromList(ZipEncoder().encode(archive)),
        ),
        throwsFormatException,
      );
      expect(
        () => documents.parseBytes(
          'test.docx',
          docx('<!DOCTYPE malicious><w:p/>'),
        ),
        throwsFormatException,
      );
    });
    test('兼容更换了 XML namespace 前缀的标准文档', () {
      final source = '$_header<w:p><w:r><w:t>兼容</w:t></w:r></w:p>$_footer'
          .replaceAll('xmlns:w=', 'xmlns:other=')
          .replaceAll('<w:', '<other:')
          .replaceAll('</w:', '</other:');
      final body = utf8.encode(source);
      final archive = Archive()
        ..add(ArchiveFile('word/document.xml', body.length, body));
      expect(
        documents
            .parseBytes(
              'test.docx',
              Uint8List.fromList(ZipEncoder().encode(archive)),
            )
            .single
            .text,
        '兼容',
      );
    });
  });

  group('唯一 key 与占位符', () {
    test('常见语义 key、稳定自定义 key、英文 key 和安全前缀', () {
      expect(documents.uniqueKey(' 登录。 ', []), 'login');
      final key = documents.uniqueKey('一段自定义中文', []);
      expect(key, startsWith('text_'));
      expect(documents.uniqueKey('一段自定义中文', []), key);
      expect(documents.uniqueKey('Hello world!', []), 'hello_world');
      expect(
        documents.uniqueKey('登录', [], prefix: '123 页'),
        startsWith('text_123_'),
      );
    });
    test('相同语义或 hash 冲突时追加确定后缀，再追加计数', () {
      final first = documents.uniqueKey('登录', ['login']);
      expect(first, startsWith('login_'));
      expect(documents.uniqueKey('登录', ['login', first]), '${first}_2');
      expect(
        documents.uniqueKey('登录', ['login', first, '${first}_2']),
        '${first}_3',
      );
    });
    test('占位符按数量校验，支持复合与printf格式，忽略字面百分号', () {
      expect(
        documents.placeholders(
          '欢迎 {{ name }} {user.name} %1\$s %02d %% {user.name}',
        ),
        ['%02d', '%1\$s', '{user.name}', '{user.name}', '{{name}}'],
      );
    });
  });

  group('JSON 与 ZIP', () {
    test('正式导出含独立中文/目标语言，key排序且UTF8无损', () {
      final project = completeProject();
      expect(exports.validate(project), isEmpty);
      final files = exports.packages(project);
      expect(files.keys, ['zh-Hans.json', 'en.json', 'ja.json']);
      expect(jsonDecode(files['en.json']!).keys, ['login', 'welcome']);
      expect(jsonDecode(files['ja.json']!)['login'], 'ログイン');
      final zip = ZipDecoder().decodeBytes(exports.zip(files));
      expect(zip.files.map((file) => file.name), files.keys);
      for (final file in zip.files) {
        expect(utf8.decode(file.readBytes()!), files[file.name]);
      }
      expect(exports.packages(project, includeSource: false).keys, [
        'en.json',
        'ja.json',
      ]);
    });
    test('未选条目不导出，重复locale只生成一次', () {
      final project = completeProject();
      project.entries.first.selected = false;
      project.locales.add('en');
      final files = exports.packages(project);
      expect(files.length, 3);
      expect(jsonDecode(files['en.json']!).keys, ['login']);
    });
    test('译文缺失、失败与占位符变更会阻止正式导出', () {
      final project = completeProject();
      project.entries[0].translations['en']!.text = 'Welcome';
      project.entries[0].translations['ja']!.status = TranslationStatus.failed;
      project.entries[1].translations.remove('en');
      expect(
        exports.validate(project).map((issue) => issue.type),
        containsAll(['placeholders', 'translation', 'missing']),
      );
      expect(() => exports.packages(project), throwsFormatException);
      final files = exports.packages(project, draft: true);
      final report = jsonDecode(files['validation-report.json']!);
      expect(report['draft'], true);
      expect(report['issues'], hasLength(3));
    });
    test('人工修订或确认过的失败译文允许导出，但仍检查占位符', () {
      final project = completeProject();
      project.entries[0].translations['en']!
        ..status = TranslationStatus.failed
        ..reviewed = true;
      expect(exports.validate(project), isEmpty);
      project.entries[0].translations['en']!.text = 'Welcome';
      expect(exports.validate(project).single.type, 'placeholders');
    });
    test('无效和重复key连草稿也拒绝，不能静默覆盖', () {
      final project = completeProject();
      project.entries[0].key = 'login';
      expect(exports.validate(project).single.type, 'duplicate');
      expect(
        () => exports.packages(project, draft: true),
        throwsFormatException,
      );
      project.entries[0].key = 'UPPER';
      expect(exports.validate(project).single.type, 'key');
    });
    test('空项目、未选语言、未知语言及不安全ZIP名称拒绝', () {
      final project = Project(name: '空', locales: []);
      expect(exports.validate(project).map((issue) => issue.type), [
        'empty',
        'language',
      ]);
      final other = completeProject()..locales.add('../evil');
      expect(() => exports.packages(other, draft: true), throwsFormatException);
      expect(() => exports.zip({'../evil.json': '{}'}), throwsFormatException);
      expect(() => exports.zip({}), throwsFormatException);
    });
  });
}
