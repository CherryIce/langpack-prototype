import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models.dart';

/// In-memory document parsing shared by mobile, desktop and web.
class DocumentService {
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxDocumentBytes = 20 * 1024 * 1024;
  static const maxBlocks = 1000;
  static const _wordNamespace =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  static final _placeholderPattern = RegExp(
    r'''\{\{\s*[\w.]+\s*\}\}|\{[\w.]+\}|%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdif@uoxXegGc]|%%''',
  );

  List<String> placeholders(String source) =>
      _placeholderPattern
          .allMatches(source)
          .map((match) => match.group(0)!.replaceAll(RegExp(r'\s+'), ''))
          .where((token) => token != '%%')
          .toList()
        ..sort();

  List<DocumentBlock> splitText(String text, {String mode = 'paragraph'}) {
    final clean = text
        .replaceFirst(RegExp('^\uFEFF'), '')
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .trim();
    if (clean.isEmpty) return [];
    if (utf8.encode(clean).length > maxDocumentBytes) {
      throw const FormatException('文本超过 20 MB 上限，请分批导入。');
    }
    final List<DocumentBlock> result;
    if (mode == 'markdown' || mode == 'md') {
      result = _markdown(clean);
    } else {
      final separator = mode == 'line' || mode == 'lines'
          ? RegExp(r'\n')
          : RegExp(r'\n[\t ]*\n+');
      result = clean
          .split(separator)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .map(DocumentBlock.new)
          .toList();
    }
    return _checkBlocks(result);
  }

  List<DocumentBlock> parseBytes(String name, Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('文档不能超过 10 MB，请缩小后重试。');
    }
    final extension = name.toLowerCase().split('.').last;
    late List<DocumentBlock> blocks;
    try {
      if (extension == 'docx') {
        blocks = _docx(_readDocumentXml(bytes));
      } else if (['txt', 'md', 'markdown'].contains(extension)) {
        blocks = splitText(
          _decodeText(bytes),
          mode: extension == 'txt' ? 'paragraph' : 'markdown',
        );
      } else {
        throw const FormatException(
          '请选择 TXT、Markdown 或 DOCX 文件，暂不支持 PDF 和旧版 DOC。',
        );
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('文档无法读取，请确认文件完整、未加密，并重新另存后导入。');
    }
    if (blocks.isEmpty) {
      throw const FormatException('没有找到可翻译的正文，图片和扫描文字暂不支持。');
    }
    return _checkBlocks(blocks);
  }

  String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) {
        throw const FormatException('UTF-16 文本不完整，请另存为 UTF-8。');
      }
      final data = ByteData.sublistView(bytes);
      final endian = bytes[0] == 0xff ? Endian.little : Endian.big;
      return String.fromCharCodes([
        for (var index = 2; index < bytes.length; index += 2)
          data.getUint16(index, endian),
      ]);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('文本编码无法识别，请另存为 UTF-8 或带 BOM 的 UTF-16。');
    }
  }

  List<DocumentBlock> _checkBlocks(List<DocumentBlock> blocks) {
    if (blocks.length > maxBlocks) {
      throw const FormatException('单次最多导入 1000 个内容块，请分批处理。');
    }
    return blocks;
  }

  List<DocumentBlock> _markdown(String text) {
    final result = <DocumentBlock>[];
    var pending = <String>[];
    String? fence;
    void flush() {
      if (pending.isNotEmpty) {
        result.add(DocumentBlock(pending.join('\n')));
        pending = [];
      }
    }

    for (final line in text.split('\n')) {
      final mark = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
      if (mark != null) {
        flush();
        final kind = mark.group(1)![0];
        if (fence == null) {
          fence = kind;
        } else if (fence == kind) {
          fence = null;
        }
        continue;
      }
      if (fence != null) continue;
      if (line.trim().isEmpty ||
          RegExp(r'^\s{0,3}(?:[-*_]\s*){3,}$').hasMatch(line)) {
        flush();
        continue;
      }
      final heading = RegExp(
        r'^\s{0,3}#{1,6}\s+(.+?)(?:\s+#+)?$',
      ).firstMatch(line);
      final item = RegExp(r'^\s*(?:[-+*]|\d+[.)])\s+(.+)$').firstMatch(line);
      if (heading != null || item != null) {
        flush();
        result.add(
          DocumentBlock(
            (heading ?? item)!.group(1)!,
            type: heading != null ? 'heading' : 'list',
          ),
        );
      } else if (RegExp(
        r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$',
      ).hasMatch(line)) {
        flush();
      } else if (line.contains('|')) {
        flush();
        result.addAll(
          line
              .replaceAll(RegExp(r'^\s*\||\|\s*$'), '')
              .split('|')
              .map((cell) => cell.trim())
              .where((cell) => cell.isNotEmpty)
              .map((cell) => DocumentBlock(cell, type: 'table-cell')),
        );
      } else {
        pending.add(line.replaceFirst(RegExp(r'^\s*>\s?'), ''));
      }
      if (result.length > maxBlocks) _checkBlocks(result);
    }
    flush();
    return result;
  }

  /// Only reads word/document.xml. Checking central-directory metadata before
  /// bounded inflate prevents an unrelated archive entry from being expanded.
  String _readDocumentXml(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    void require(bool condition) {
      if (!condition) throw const FormatException('DOCX 文件损坏或目录不完整。');
    }

    require(bytes.length >= 22);
    var end = -1;
    final earliest = bytes.length - 65557 < 0 ? 0 : bytes.length - 65557;
    for (var index = bytes.length - 22; index >= earliest; index--) {
      if (view.getUint32(index, Endian.little) == 0x06054b50 &&
          index + 22 + view.getUint16(index + 20, Endian.little) ==
              bytes.length) {
        end = index;
        break;
      }
    }
    require(end >= 0);
    final count = view.getUint16(end + 10, Endian.little);
    final centralSize = view.getUint32(end + 12, Endian.little);
    final centralOffset = view.getUint32(end + 16, Endian.little);
    require(
      view.getUint16(end + 4, Endian.little) == 0 &&
          view.getUint16(end + 6, Endian.little) == 0 &&
          view.getUint16(end + 8, Endian.little) == count,
    );
    if (count == 0xffff ||
        centralSize == 0xffffffff ||
        centralOffset == 0xffffffff) {
      throw const FormatException('暂不支持 ZIP64 文档，请另存为标准 DOCX。');
    }
    require(count <= 4096 && centralOffset + centralSize <= end);
    var cursor = centralOffset;
    Uint8List? document;
    for (var index = 0; index < count; index++) {
      require(
        cursor + 46 <= centralOffset + centralSize &&
            view.getUint32(cursor, Endian.little) == 0x02014b50,
      );
      final flags = view.getUint16(cursor + 8, Endian.little);
      final method = view.getUint16(cursor + 10, Endian.little);
      final compressed = view.getUint32(cursor + 20, Endian.little);
      final plain = view.getUint32(cursor + 24, Endian.little);
      final nameLength = view.getUint16(cursor + 28, Endian.little);
      final extraLength = view.getUint16(cursor + 30, Endian.little);
      final commentLength = view.getUint16(cursor + 32, Endian.little);
      final local = view.getUint32(cursor + 42, Endian.little);
      require(
        cursor + 46 + nameLength + extraLength + commentLength <=
            centralOffset + centralSize,
      );
      if (flags & 1 != 0) throw const FormatException('暂不支持加密 DOCX，请先移除密码。');
      final name = utf8.decode(
        bytes.sublist(cursor + 46, cursor + 46 + nameLength),
        allowMalformed: true,
      );
      if (name == 'word/document.xml') {
        require(document == null);
        if (plain > maxDocumentBytes) {
          throw const FormatException('DOCX 正文解压后不能超过 20 MB。');
        }
        require(
          plain != 0xffffffff &&
              compressed != 0xffffffff &&
              local + 30 <= centralOffset &&
              view.getUint32(local, Endian.little) == 0x04034b50,
        );
        final localFlags = view.getUint16(local + 6, Endian.little);
        final localMethod = view.getUint16(local + 8, Endian.little);
        final localNameLength = view.getUint16(local + 26, Endian.little);
        final localExtraLength = view.getUint16(local + 28, Endian.little);
        final start = local + 30 + localNameLength + localExtraLength;
        require(
          localFlags == flags &&
              localMethod == method &&
              start + compressed <= centralOffset &&
              utf8.decode(
                    bytes.sublist(local + 30, local + 30 + localNameLength),
                    allowMalformed: true,
                  ) ==
                  name,
        );
        if (method == 0) {
          require(compressed == plain);
          document = bytes.sublist(start, start + compressed);
        } else if (method == 8) {
          try {
            document = const ZLibDecoder().decodeBytes(
              bytes.sublist(start, start + compressed),
              raw: true,
              maxOutputSize: plain,
            );
          } catch (_) {
            throw const FormatException('DOCX 正文解压失败，文件损坏或超过声明大小。');
          }
        } else {
          throw const FormatException('DOCX 压缩格式不受支持，请另存为标准 DOCX。');
        }
        require(
          document.length == plain &&
              getCrc32(document) == view.getUint32(cursor + 16, Endian.little),
        );
      }
      cursor += 46 + nameLength + extraLength + commentLength;
    }
    require(cursor == centralOffset + centralSize);
    if (document == null) throw const FormatException('DOCX 中没有找到 Word 正文。');
    return utf8.decode(document);
  }

  List<DocumentBlock> _docx(String xml) {
    // OOXML does not require external entities or DTDs.
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(xml)) {
      throw const FormatException('DOCX 包含不支持的文档声明。');
    }
    final document = XmlDocument.parse(xml);
    final bodies = document.descendants.whereType<XmlElement>().where(
      (node) =>
          node.name.local == 'body' && node.name.namespaceUri == _wordNamespace,
    );
    if (bodies.isEmpty) throw const FormatException('DOCX 中没有可读取的正文。');
    final result = <DocumentBlock>[];
    bool isWord(XmlElement node, String name) =>
        node.name.local == name && node.name.namespaceUri == _wordNamespace;
    String paragraphText(XmlElement paragraph) {
      if (paragraph.ancestors.whereType<XmlElement>().any(
        (ancestor) => isWord(ancestor, 'del'),
      )) {
        return '';
      }
      final buffer = StringBuffer();
      void read(XmlNode node) {
        if (node is XmlElement && node.name.namespaceUri == _wordNamespace) {
          if (node.name.local == 'del') return;
          if (node.name.local == 't') {
            buffer.write(node.innerText);
            return;
          }
          if (node.name.local == 'tab') buffer.write('\t');
          if (node.name.local == 'br' || node.name.local == 'cr') {
            buffer.write('\n');
          }
        }
        for (final child in node.children) {
          read(child);
        }
      }

      read(paragraph);
      return buffer.toString().trim();
    }

    void walk(XmlNode node) {
      if (node is! XmlElement) return;
      if (isWord(node, 'del')) return;
      if (isWord(node, 'p')) {
        final text = paragraphText(node);
        final styles = node.descendants.whereType<XmlElement>().where(
          (child) => isWord(child, 'pStyle'),
        );
        final style = styles.isEmpty
            ? ''
            : styles.first.getAttribute('val', namespace: _wordNamespace) ?? '';
        final type =
            RegExp('heading|title|标题', caseSensitive: false).hasMatch(style)
            ? 'heading'
            : node.descendants.whereType<XmlElement>().any(
                (child) => isWord(child, 'numPr'),
              )
            ? 'list'
            : 'paragraph';
        if (text.isNotEmpty) result.add(DocumentBlock(text, type: type));
      } else if (isWord(node, 'tc')) {
        final text = node.descendants
            .whereType<XmlElement>()
            .where((child) => isWord(child, 'p'))
            .map(paragraphText)
            .where((text) => text.isNotEmpty)
            .join('\n');
        if (text.isNotEmpty) {
          result.add(DocumentBlock(text, type: 'table-cell'));
        }
      } else {
        for (final child in node.children) {
          walk(child);
        }
      }
      if (result.length > maxBlocks) _checkBlocks(result);
    }

    walk(bodies.first);
    return result;
  }

  static const _semanticKeys = <String, String>{
    '登录': 'login',
    '注册': 'register',
    '注册账号': 'register_account',
    '退出登录': 'log_out',
    '退出': 'exit',
    '忘记密码': 'forgot_password',
    '密码': 'password',
    '请输入密码': 'enter_password',
    '请输入用户名': 'enter_username',
    '用户名': 'username',
    '欢迎回来': 'welcome_back',
    '欢迎回来，{name}': 'welcome_back_user',
    '欢迎，{name}': 'welcome_user',
    '保存': 'save',
    '保存更改': 'save_changes',
    '开启通知': 'enable_notifications',
    '取消': 'cancel',
    '确定': 'confirm',
    '删除': 'delete',
    '下一步': 'next_step',
    '返回': 'go_back',
    '开始使用': 'get_started',
    '立即开始': 'start_now',
    '密码重置成功': 'password_reset_success',
    '登录成功': 'login_success',
    '邮箱地址': 'email_address',
    '请先阅读并同意用户协议': 'accept_user_agreement',
    '让每一段中文，抵达更多语言': 'reach_more_languages',
    '欢迎使用译包': 'welcome_to_langpack',
    '一次输入，即可生成多种语言的翻译结果': 'translate_into_multiple_languages',
    '为每一段中文生成稳定的语义 key': 'generate_stable_semantic_keys',
    '按语言导出 JSON，让本地化更简单': 'export_json_by_language',
    '项目名称': 'project_name',
    '新建项目': 'create_project',
    '设置': 'settings',
    '加载中': 'loading',
    '网络连接失败，请稍后重试': 'network_error_retry',
  };

  String _hash(String value) {
    var hash = 2166136261;
    for (final rune in value.runes) {
      hash = (hash ^ rune) & 0xffffffff;
      final low = (hash & 0xffff) * 16777619;
      final high = ((hash >> 16) * 16777619) & 0xffff;
      hash = (low + (high << 16)) & 0xffffffff;
    }
    return hash.toRadixString(36).padLeft(7, '0');
  }

  String uniqueKey(String source, Iterable<String> used, {String prefix = ''}) {
    final normalized = source
        .trim()
        .replaceAll(RegExp(r'[。.!！?？]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final keys = used.toSet();
    var base = _semanticKeys[normalized];
    if (base == null &&
        RegExp(r'^[\x20-\x7E]+$').hasMatch(normalized) &&
        RegExp('[a-zA-Z]').hasMatch(normalized)) {
      base = normalized
          .toLowerCase()
          .replaceAll(RegExp(r'\{[^}]*\}|%\d*\$?[sdif]'), '')
          .replaceAll(RegExp('[^a-z0-9]+'), '_')
          .replaceAll(RegExp('^_+|_+\$'), '');
      if (base.length > 48) {
        base = base.substring(0, 48).replaceFirst(RegExp('_+\$'), '');
      }
      if (base.isEmpty) base = 'text';
      if (!RegExp('^[a-z]').hasMatch(base)) base = 'text_$base';
    }
    base ??= 'text_${_hash(normalized)}';
    final context = prefix
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '');
    if (context.isNotEmpty) {
      base = '${context}_$base';
      if (!RegExp('^[a-z]').hasMatch(base)) base = 'text_$base';
      if (base.length > 64) {
        base = base.substring(0, 64).replaceFirst(RegExp('_+\$'), '');
      }
    }
    if (!keys.contains(base)) return base;
    final stem = base.length > 53 ? base.substring(0, 53) : base;
    final candidate = '${stem}_${_hash('$normalized\u0000$prefix')}';
    if (!keys.contains(candidate)) return candidate;
    var index = 2;
    while (keys.contains('${candidate}_$index')) {
      index++;
    }
    return '${candidate}_$index';
  }
}
