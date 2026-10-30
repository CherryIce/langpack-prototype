import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

/// Fixed LangPack proxy origin. User credentials are supplied only at runtime.
const defaultBackupServiceOrigin =
    'https://langpack-standalone.406859116.workers.dev';

/// Cancels queued work, active HTTP requests, retry waits and late responses.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();
  bool get cancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!cancelled) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (cancelled) {
      throw const TranslationFailure('ABORTED', '翻译已暂停，已完成的译文会保留。');
    }
  }

  Future<T> race<T>(Future<T> work) {
    throwIfCancelled();
    return Future.any([
      work,
      whenCancelled.then<T>((_) {
        throwIfCancelled();
        throw StateError('Cancelled');
      }),
    ]);
  }
}

class TranslationFailure implements Exception {
  const TranslationFailure(
    this.code,
    this.message, {
    this.retryable = false,
    this.quota = false,
    this.fatal = false,
    this.retryAfter = Duration.zero,
    this.provider = 'MyMemory',
  });
  final String code;
  final String message;
  final bool retryable;
  final bool quota;
  final bool fatal;
  final Duration retryAfter;
  final String provider;
  @override
  String toString() => message;
}

class TranslationResult {
  const TranslationResult({
    required this.text,
    required this.provider,
    this.requestCount = 0,
    this.cached = false,
    this.model,
  });
  final String text;
  final String provider;
  final int requestCount;
  final bool cached;
  final String? model;
}

final _placeholder = RegExp(
  r'''\{\{\s*[\w.]+\s*\}\}|\{[\w.]+\}|%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdif@uoxXegGc]|%%''',
);
final _marker = RegExp(r'ZXQ(?:PH|NL)\d+QXZ');
final _looseMarker = RegExp(
  r'ZXQ\s*(PH|NL)\s*(\d+)\s*QXZ',
  caseSensitive: false,
);
final _quotaMessage = RegExp(
  r'used all available free translations|next available in|quota\s*(?:has been\s*)?(?:exceed|finish|exhaust)|(?:daily|free)\s+(?:translation\s+)?(?:limit|quota)\s*(?:reached|exceed|exhaust)|out of quota',
  caseSensitive: false,
);
const _languageMap = {
  'en': 'en',
  'ja': 'ja',
  'ko': 'ko',
  'fr': 'fr',
  'de': 'de',
  'es': 'es',
  'zh-Hant': 'zh-TW',
  'pt-PT': 'pt-PT',
  'ms': 'ms',
  'th': 'th',
  'ar': 'ar',
  'vi': 'vi',
  'ru': 'ru',
  'tr': 'tr',
  'id': 'id',
  'hi': 'hi',
  'hu': 'hu',
  'it': 'it',
  'ro': 'ro',
  'sv': 'sv',
  'bg': 'bg',
  'pl': 'pl',
  'da': 'da',
  'fi': 'fi',
  'nl': 'nl',
  'cs': 'cs',
  'sk': 'sk',
  'uk': 'uk',
  'el': 'el',
  'hr': 'hr',
  'si': 'si-LK',
};

List<String> _matches(RegExp pattern, String text) =>
    pattern
        .allMatches(text)
        .map((m) => m[0]!.replaceAll(RegExp(r'\s+'), ''))
        .toList()
      ..sort();
String _normalizeMarkers(String text) => text.replaceAllMapped(
  _looseMarker,
  (m) => 'ZXQ${m[1]!.toUpperCase()}${m[2]}QXZ',
);
void _assertSame(RegExp pattern, String expected, String result) {
  if (!listEquals(_matches(pattern, expected), _matches(pattern, result))) {
    throw const TranslationFailure(
      'PLACEHOLDER',
      '译文改变了占位符或换行标记，结果未保存，请重试或人工校对。',
    );
  }
}

class _Protected {
  _Protected(String source, {bool newlines = false}) {
    var index = 0;
    final pattern = RegExp(
      '${_placeholder.pattern}|ZXQ(?:PH|NL)\\s*\\d+\\s*QXZ${newlines ? '|\\r\\n|\\r|\\n' : ''}',
      caseSensitive: false,
    );
    text = source.replaceAllMapped(pattern, (m) {
      String token;
      do {
        token =
            'ZXQ${RegExp(r'^[\r\n]+$').hasMatch(m[0]!) ? 'NL' : 'PH'}${index++}QXZ';
      } while (source.toUpperCase().contains(token));
      originals[token] = m[0]!;
      return token;
    });
  }
  late final String text;
  final Map<String, String> originals = {};
  String restore(String result) {
    var output = _normalizeMarkers(result);
    _assertSame(_marker, text, output);
    for (final item in originals.entries) {
      output = output.replaceFirst(item.key, item.value);
    }
    return output;
  }
}

/// Lossless UTF-8 splitting; generated markers and Unicode scalar values are atomic.
List<String> splitTranslationText(String text, {int maxBytes = 480}) {
  if (maxBytes < 4 || maxBytes > 500) throw RangeError.range(maxBytes, 4, 500);
  final pieces = <String>[];
  var start = 0;
  while (start < text.length) {
    var cursor = start, bytes = 0, sentence = -1, word = -1, soft = -1;
    while (cursor < text.length) {
      final marker = _marker.matchAsPrefix(text, cursor);
      final high = text.codeUnitAt(cursor);
      final count = high >= 0xd800 && high <= 0xdbff && cursor + 1 < text.length
          ? 2
          : 1;
      final unit = marker?[0] ?? text.substring(cursor, cursor + count);
      final size = utf8.encode(unit).length;
      if (bytes + size > maxBytes) break;
      bytes += size;
      cursor += unit.length;
      if (RegExp(r'[。！？.!?；;\r\n]$').hasMatch(unit)) {
        sentence = cursor;
      } else if (RegExp(r'[，,：:]$').hasMatch(unit)) {
        soft = cursor;
      }
      if (RegExp(r'\s$').hasMatch(unit)) word = cursor;
    }
    if (cursor == start) {
      throw const TranslationFailure('CHUNK_SIZE', '受保护标记过长，无法安全拆分。');
    }
    var end = cursor;
    if (cursor < text.length) {
      end = sentence > start
          ? sentence
          : word > start
          ? word
          : soft > start
          ? soft
          : cursor;
    }
    pieces.add(text.substring(start, end));
    start = end;
  }
  return pieces;
}

String _decodeEntities(String value) => value.replaceAllMapped(
  RegExp(r'&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);', caseSensitive: false),
  (m) {
    final entity = m[0]!.toLowerCase();
    const named = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&apos;': "'",
    };
    if (named.containsKey(entity)) return named[entity]!;
    final hex = entity.startsWith('&#x');
    final point = int.tryParse(
      entity.substring(hex ? 3 : 2, entity.length - 1),
      radix: hex ? 16 : 10,
    );
    return point != null &&
            point > 0 &&
            point <= 0x10ffff &&
            (point < 0xd800 || point > 0xdfff)
        ? String.fromCharCode(point)
        : m[0]!;
  },
);

class _Run {
  _Run(this.token, this.onStatus, this.bypassCache);
  final CancelToken token;
  final void Function(String)? onStatus;
  final bool bypassCache;
  int requests = 0;
  void status(String value) {
    try {
      onStatus?.call(value);
    } catch (_) {
      /* Observers do not affect requests. */
    }
  }
}

class TranslationService {
  TranslationService({
    http.Client? client,
    this.minInterval = const Duration(milliseconds: 1100),
    this.primaryTimeout = const Duration(seconds: 15),
    this.backupTimeout = const Duration(seconds: 620),
    this.maxRetries = 2,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _sleep = sleep ?? Future<void>.delayed,
       _now = now ?? DateTime.now;
  final http.Client _client;
  final Duration minInterval;
  final Duration primaryTimeout;
  final Duration backupTimeout;
  final int maxRetries;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;
  Future<void> _queue = Future<void>.value();
  DateTime? _lastStarted;
  DateTime? _circuitUntil;
  final LinkedHashMap<String, String> _cache = LinkedHashMap();
  bool _disposed = false;
  List<String>? _providerOrder;
  bool _providerFallback = true;
  Map<String, Map<String, String>> _credentials = {};
  int _credentialRevision = 0;
  final Map<String, DateTime> _providerCooldowns = {};
  final Map<String, String> _providerModels = {};
  String? _configuredEmail;

  void resetProviderState(String provider) {
    _providerCooldowns.remove(provider);
    if (provider == 'MyMemory') _circuitUntil = null;
    final keys = _cache.keys
        .where(
          (key) =>
              key.startsWith('provider\u0000$provider\u0000') ||
              provider == 'MyMemory' && key.startsWith('primary\u0000'),
        )
        .toList();
    for (final key in keys) {
      _cache.remove(key);
      _providerModels.remove(key);
    }
  }

  void setProviderConfiguration({
    required List<String> order,
    required bool fallback,
    required Map<String, Map<String, String>> credentials,
    required int revision,
  }) {
    final copied = {
      for (final pair in credentials.entries)
        pair.key: Map<String, String>.from(pair.value),
    };
    for (final provider in translationProviders) {
      if (jsonEncode(_credentials[provider]) != jsonEncode(copied[provider])) {
        _providerCooldowns.remove(provider);
      }
    }
    if (_credentialRevision != revision ||
        jsonEncode(_credentials) != jsonEncode(copied)) {
      clearCache();
    }
    _providerOrder = normalizeProviderOrder(order);
    _providerFallback = fallback;
    _credentials = copied;
    _credentialRevision = revision;
  }

  bool _supportsProvider(String provider, String locale) => switch (provider) {
    'MyMemory' => _languageMap.containsKey(locale),
    'DeepL' => !['fil', 'si'].contains(locale),
    'Google' => locale != 'nb',
    'Baidu' => !['pt-BR', 'pt-PT'].contains(locale),
    'Tencent' => const [
      'zh-Hant',
      'en',
      'ms',
      'th',
      'fr',
      'es',
      'ar',
      'vi',
      'ru',
      'tr',
      'id',
      'ja',
      'ko',
      'de',
      'it',
    ].contains(locale),
    'Alibaba' => !['pt-BR', 'pt-PT', 'nb', 'hr', 'uk'].contains(locale),
    _ => true,
  };

  Uri _endpoint(String base, String path) {
    final cleaned = base.trim();
    final uri = cleaned.isEmpty
        ? Uri.parse(kIsWeb ? Uri.base.origin : defaultBackupServiceOrigin)
        : Uri.tryParse(cleaned);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '' && uri.path != '/') {
      throw const TranslationFailure(
        'BACKUP_URL',
        '请填写有效的服务根地址，例如 https://translate.example.com。',
        fatal: true,
        provider: 'ZTAITrans',
      );
    }
    if (kIsWeb && uri.origin != Uri.base.origin) {
      throw const TranslationFailure(
        'BACKUP_ORIGIN',
        '网页版的备用翻译需与当前页面使用同一服务地址。',
        fatal: true,
        provider: 'ZTAITrans',
      );
    }
    if (uri.scheme == 'http' &&
        !['localhost', '127.0.0.1', '::1', '10.0.2.2'].contains(uri.host)) {
      throw const TranslationFailure(
        'BACKUP_HTTPS',
        '正式备用服务需使用 HTTPS；HTTP 仅用于本机开发。',
        fatal: true,
        provider: 'ZTAITrans',
      );
    }
    return uri.replace(path: path);
  }

  void _remember(String key, String text) {
    _cache.remove(key);
    _cache[key] = text;
    while (_cache.length > 500) {
      _cache.remove(_cache.keys.first);
    }
  }

  String? _cached(String key) {
    final value = _cache.remove(key);
    if (value != null) _cache[key] = value;
    return value;
  }

  Duration _retryAfter(http.Response response, Map<String, dynamic>? body) {
    final raw = response.headers['retry-after'] ?? '';
    final seconds = double.tryParse(raw);
    var delay = seconds != null && seconds.isFinite
        ? Duration(milliseconds: (seconds * 1000).round())
        : Duration.zero;
    var date = DateTime.tryParse(raw);
    final httpDate = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(raw);
    if (date == null && httpDate != null) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = months.indexOf(httpDate[2]!);
      if (month >= 0) {
        date = DateTime.utc(
          int.parse(httpDate[3]!),
          month + 1,
          int.parse(httpDate[1]!),
          int.parse(httpDate[4]!),
          int.parse(httpDate[5]!),
          int.parse(httpDate[6]!),
        );
      }
    }
    if (date != null) delay = date.difference(_now());
    if (raw.isNotEmpty &&
        (seconds == null || !seconds.isFinite) &&
        date == null) {
      delay = const Duration(minutes: 2);
    }
    final millis = body?['retryAfterMs'];
    if (millis is num) {
      delay = Duration(
        milliseconds: math.max(delay.inMilliseconds, millis.round()),
      );
    }
    return delay.isNegative ? Duration.zero : delay;
  }

  Future<http.Response> _send(
    Uri uri, {
    required CancelToken token,
    required Duration timeout,
    String? body,
    Map<String, String> headers = const {},
  }) async {
    token.throwIfCancelled();
    if (_disposed) {
      throw const TranslationFailure('DISPOSED', '翻译服务已关闭。', fatal: true);
    }
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    var timedOut = false;
    try {
      final request = http.AbortableRequest(
        body == null ? 'GET' : 'POST',
        uri,
        abortTrigger: Future.any([token.whenCancelled, abort.future]),
      );
      request.followRedirects = false;
      request.headers['Accept'] = 'application/json';
      request.headers.addAll(headers);
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = body;
      }
      final operation = () async {
        final streamed = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          token.throwIfCancelled();
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            throw const TranslationFailure('RESPONSE_SIZE', '翻译服务响应过大，未保存。');
          }
        }
        return http.Response.bytes(
          bytes,
          streamed.statusCode,
          headers: streamed.headers,
        );
      }();
      return await token.race(
        operation.timeout(
          timeout,
          onTimeout: () {
            timedOut = true;
            if (!abort.isCompleted) abort.complete();
            throw const TranslationFailure(
              'TIMEOUT',
              '翻译请求超时，已完成的结果会保留。',
              retryable: true,
            );
          },
        ),
      );
    } on TranslationFailure {
      rethrow;
    } catch (_) {
      token.throwIfCancelled();
      if (timedOut || abort.isCompleted) {
        throw const TranslationFailure(
          'TIMEOUT',
          '翻译请求超时，已完成的结果会保留。',
          retryable: true,
        );
      }
      throw const TranslationFailure(
        'NETWORK',
        '无法连接翻译服务，请检查网络后重试。',
        retryable: true,
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  Map<String, dynamic>? _body(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<T> _limited<T>(CancelToken token, Future<T> Function() action) {
    final work = _queue.then((_) async {
      token.throwIfCancelled();
      if (_lastStarted != null) {
        final wait = minInterval - _now().difference(_lastStarted!);
        if (wait > Duration.zero) await token.race(_sleep(wait));
      }
      token.throwIfCancelled();
      _lastStarted = _now();
      return action();
    });
    _queue = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return token.race(work);
  }

  Future<String> _primaryChunk(
    String source,
    String locale,
    String email,
    _Run run,
  ) async {
    final key = 'primary\u0000$locale\u0000$source';
    final cached = run.bypassCache ? null : _cached(key);
    if (cached != null) return cached;
    for (var attempt = 0; ; attempt++) {
      run.token.throwIfCancelled();
      try {
        final result = await _limited(run.token, () async {
          final query = {
            'q': source,
            'langpair': 'zh-CN|${_languageMap[locale]}',
            'mt': '1',
            if (email.isNotEmpty) 'de': email,
          };
          run.requests++;
          final response = await _send(
            Uri.https('api.mymemory.translated.net', '/get', query),
            token: run.token,
            timeout: primaryTimeout,
          );
          final body = _body(response);
          final data = body?['responseData'];
          final candidate = data is Map && data['translatedText'] is String
              ? data['translatedText'] as String
              : '';
          final details = body?['responseDetails'] is String
              ? body!['responseDetails'] as String
              : '';
          final delay = _retryAfter(response, body);
          // translatedText is user content; quota words alone are not a service signal.
          final candidateWarning = RegExp(
            r'^\s*MYMEMORY WARNING\s*:',
            caseSensitive: false,
          ).hasMatch(candidate);
          final serviceStatus = int.tryParse('${body?['responseStatus']}');
          final quotaSignal =
              [true, 'true', 1].contains(body?['quotaFinished']) ||
              _quotaMessage.hasMatch(details) ||
              candidateWarning && _quotaMessage.hasMatch(candidate);
          if ([401, 403].contains(response.statusCode) ||
              serviceStatus == 401 ||
              serviceStatus == 403 && !quotaSignal) {
            throw const TranslationFailure(
              'PROVIDER_AUTH',
              'MyMemory 鉴权或访问配置不可用，请检查设置。',
              fatal: true,
            );
          }
          if (quotaSignal) {
            throw TranslationFailure(
              'QUOTA',
              'MyMemory 今日免费额度已用尽，已保留成功译文。',
              quota: true,
              retryAfter: delay,
            );
          }
          final status = response.statusCode >= 400
              ? response.statusCode
              : serviceStatus;
          if (status != 200) {
            final retryable =
                status == null ||
                status == 408 ||
                status == 425 ||
                status == 429 ||
                status >= 500;
            throw TranslationFailure(
              status == 429 ? 'RATE_LIMIT' : 'REQUEST',
              status == 429 ? '翻译请求过于频繁，请稍后重试。' : 'MyMemory 暂时无法完成翻译，请稍后重试。',
              retryable: retryable,
              retryAfter: delay,
            );
          }
          if (RegExp(
            r'MYMEMORY WARNING:|NO QUERY SPECIFIED|INVALID LANGPAIR|IS AN INVALID (?:TARGET|SOURCE) LANGUAGE|PLEASE SELECT TWO DISTINCT LANGUAGES|^\s*<(?:!doctype|html)',
            caseSensitive: false,
          ).hasMatch(candidate)) {
            throw const TranslationFailure('RESPONSE', '服务商返回了错误提示，未将其保存为译文。');
          }
          final text = _normalizeMarkers(
            _decodeEntities(candidate),
          ).replaceAll(RegExp(r'\r\n|\r|\n'), ' ').trim();
          if (text.isEmpty) {
            throw const TranslationFailure(
              'EMPTY',
              '翻译服务返回空译文，请稍后重试。',
              retryable: true,
            );
          }
          _assertSame(_marker, source, text);
          _assertSame(_placeholder, source, text);
          return text;
        });
        run.token.throwIfCancelled();
        _remember(key, result);
        return result;
      } on TranslationFailure catch (error) {
        run.token.throwIfCancelled();
        if (!error.retryable ||
            error.quota ||
            attempt >= maxRetries.clamp(0, 5) ||
            error.retryAfter > const Duration(minutes: 1)) {
          rethrow;
        }
        final delay = Duration(
          milliseconds: math.max(
            error.retryAfter.inMilliseconds,
            1000 * (1 << attempt),
          ),
        );
        run.status('MyMemory 暂时失败，${attempt + 1}/$maxRetries 次自动重试…');
        await run.token.race(_sleep(delay));
      }
    }
  }

  Future<String> _primary(
    String source,
    String locale,
    String email,
    _Run run,
  ) async {
    final protected = _Protected(source);
    final output = StringBuffer();
    var previousTranslated = false;
    // Keep newline bytes and whitespace outside the translation API.
    final lines = RegExp(r'\r\n|\r|\n|[^\r\n]+').allMatches(protected.text);
    for (final lineMatch in lines) {
      final line = lineMatch[0]!;
      if (line.trim().isEmpty) {
        output.write(line);
        previousTranslated = false;
        continue;
      }
      for (final chunk in splitTranslationText(line)) {
        final match = RegExp(r'^(\s*)([\s\S]*?)(\s*)$').firstMatch(chunk)!;
        final core = match[2]!;
        if (core.isEmpty ||
            core
                .replaceAll(_marker, '')
                .replaceAll(RegExp(r'[\p{P}\p{S}\s\d]', unicode: true), '')
                .isEmpty) {
          output.write(chunk);
          previousTranslated = false;
          continue;
        }
        run.status('MyMemory · 翻译中');
        final text =
            '${match[1]}${await _primaryChunk(core, locale, email, run)}${match[3]}';
        final tail = output.toString();
        if (previousTranslated &&
            !['zh-Hant', 'ja', 'th'].contains(locale) &&
            RegExp(
              r'''[\p{L}\p{M}\p{N}.!?;:)"']$''',
              unicode: true,
            ).hasMatch(tail) &&
            RegExp(r'^[\p{L}\p{M}\p{N}]', unicode: true).hasMatch(text)) {
          output.write(' ');
        }
        output.write(text);
        previousTranslated = true;
      }
    }
    final text = protected.restore(output.toString());
    _assertSame(_placeholder, source, text);
    return text;
  }

  TranslationFailure _backupFailure(
    http.Response response,
    Map<String, dynamic>? body,
  ) {
    final status = response.statusCode;
    final code =
        body?['code'] as String? ??
        (status == 401 || status == 403
            ? 'BACKUP_AUTH'
            : status == 402
            ? 'BACKUP_BUDGET'
            : 'BACKUP_SERVICE');
    final fatal =
        status == 401 ||
        status == 403 ||
        body?['fatal'] == true ||
        [
          'UNAUTHORIZED',
          'BACKUP_AUTH',
          'BACKUP_NOT_CONFIGURED',
          'TRANSLATE_NOT_CONFIGURED',
          'BACKUP_DISABLED',
          'TRANSLATE_DISABLED',
        ].contains(code);
    final quota =
        status == 402 ||
        ['BACKUP_BUDGET', 'TRANSLATE_BUDGET_EXCEEDED'].contains(code);
    final retryable =
        !fatal &&
        !quota &&
        body?['retryable'] != false &&
        (status >= 500 || [408, 425, 429].contains(status));
    const messages = {
      'BACKUP_AUTH': '备用翻译鉴权失败，请检查服务端配置。',
      'UNAUTHORIZED': '备用翻译鉴权失败，请检查服务端配置。',
      'BACKUP_BUDGET': '备用翻译授权预算已用尽，已完成的译文会保留。',
      'TRANSLATE_BUDGET_EXCEEDED': '备用翻译授权预算已用尽，已完成的译文会保留。',
      'BACKUP_NOT_CONFIGURED': '备用翻译服务尚未配置，请检查服务端设置。',
      'BACKUP_DISABLED': '备用翻译服务已停用，请联系服务提供方。',
      'BACKUP_ORIGIN': '备用翻译只允许同源网页访问，请检查部署地址。',
      'BACKUP_RATE_LIMIT': '备用翻译请求过于频繁，请稍后重试。',
      'BACKUP_TIMEOUT': '备用翻译超时，已完成的译文会保留。',
    };
    return TranslationFailure(
      code,
      messages[code] ?? '备用翻译请求失败，请检查服务端状态后重试。',
      fatal: fatal,
      quota: quota,
      retryable: retryable,
      retryAfter: _retryAfter(response, body),
      provider: 'ZTAITrans',
    );
  }

  Future<String> _backup(
    String source,
    String locale,
    String base,
    _Run run,
  ) async {
    final endpoint = _endpoint(base, '/api/translation/backup');
    final key = 'backup\u0000${endpoint.origin}\u0000$locale\u0000$source';
    final cached = run.bypassCache ? null : _cached(key);
    if (cached != null) return cached;
    if (source.runes.length > 50000) {
      throw const TranslationFailure(
        'BACKUP_TOO_LARGE',
        '备用服务单段最多 50,000 字符，请拆分段落后重试。',
        provider: 'ZTAITrans',
      );
    }
    final whitespace = RegExp(r'^(\s*)([\s\S]*?)(\s*)$').firstMatch(source)!;
    final protected = _Protected(whitespace[2]!, newlines: true);
    final body = jsonEncode({'content': protected.text, 'locale': locale});
    if (utf8.encode(body).length > 256 * 1024) {
      throw const TranslationFailure(
        'BACKUP_TOO_LARGE',
        '备用请求过大，请拆分段落后重试。',
        provider: 'ZTAITrans',
      );
    }
    for (var attempt = 0; ; attempt++) {
      run.token.throwIfCancelled();
      try {
        run.status('ZTAITrans · 备用翻译中');
        run.requests++;
        final response = await _send(
          endpoint,
          token: run.token,
          timeout: backupTimeout,
          body: body,
        );
        final payload = _body(response);
        if (response.statusCode != 200 || payload?['code'] != null) {
          throw _backupFailure(response, payload);
        }
        final raw = payload?['text'];
        if (raw is! String ||
            (payload?['provider'] != null &&
                payload?['provider'] != 'ZTAITrans') ||
            raw.trim().isEmpty ||
            RegExp(
              r'^\s*(?:MYMEMORY WARNING:|<!doctype html|<html(?:\s|>)|Internal Server Error\s*$|UNAUTHORIZED\s*$|TRANSLATE_[A-Z_]+\s*$)',
              caseSensitive: false,
            ).hasMatch(raw) ||
            RegExp(r'^(?:\.{3}|…|<译文>)$').hasMatch(raw.trim())) {
          throw const TranslationFailure(
            'BACKUP_RESPONSE',
            '备用服务未返回有效译文，现有内容已保留。',
            provider: 'ZTAITrans',
          );
        }
        // The protected full paragraph is translated once; never mix primary fragments.
        final text =
            '${whitespace[1]}${protected.restore(raw.replaceAll(RegExp(r'\r\n|\r|\n'), ' ').trim())}${whitespace[3]}';
        _assertSame(_placeholder, source, text);
        run.token.throwIfCancelled();
        _remember(key, text);
        return text;
      } on TranslationFailure catch (error) {
        run.token.throwIfCancelled();
        if (!error.retryable ||
            error.quota ||
            error.fatal ||
            attempt >= 1 ||
            error.retryAfter > const Duration(minutes: 1)) {
          throw TranslationFailure(
            error.code,
            error.message,
            retryable: error.retryable,
            quota: error.quota,
            fatal: error.fatal,
            retryAfter: error.retryAfter,
            provider: 'ZTAITrans',
          );
        }
        run.status('备用服务暂时失败，自动重试…');
        await run.token.race(
          _sleep(
            Duration(
              milliseconds: math.max(1000, error.retryAfter.inMilliseconds),
            ),
          ),
        );
      }
    }
  }

  TranslationFailure _providerFailure(
    http.Response response,
    Map<String, dynamic>? body,
    String provider,
  ) {
    final code = body?['code'] is String
        ? body!['code'] as String
        : 'PROVIDER_REQUEST';
    final fatal =
        [401, 403].contains(response.statusCode) ||
        ['PROVIDER_AUTH', 'PROVIDER_CONFIG'].contains(code) ||
        body?['fatal'] == true;
    final quota =
        !fatal &&
        (response.statusCode == 402 ||
            code == 'PROVIDER_QUOTA' ||
            body?['quota'] == true);
    final unsupported =
        !fatal &&
        (code == 'PROVIDER_UNSUPPORTED' || body?['unsupported'] == true);
    final retryable =
        !quota &&
        !fatal &&
        !unsupported &&
        body?['retryable'] != false &&
        (body?['retryable'] == true ||
            [429, 502, 503, 504].contains(response.statusCode));
    return TranslationFailure(
      fatal
          ? ([401, 403].contains(response.statusCode)
                ? 'PROVIDER_AUTH'
                : 'PROVIDER_CONFIG')
          : quota
          ? 'PROVIDER_QUOTA'
          : unsupported
          ? 'PROVIDER_UNSUPPORTED'
          : code,
      quota
          ? '$provider 可用额度已用尽，已保存成功译文。'
          : unsupported
          ? '$provider 暂不支持这个目标语言。'
          : fatal
          ? '$provider 凭据或配置不可用，请在设置中检查。'
          : response.statusCode == 429
          ? '$provider 请求过于频繁，请稍后重试。'
          : '$provider 暂时无法完成翻译，请稍后重试。',
      quota: quota,
      fatal: fatal,
      retryable: retryable,
      retryAfter: _retryAfter(response, body),
      provider: provider,
    );
  }

  List<String> _proxyChunks(
    String text, {
    bool byteLimit = false,
    int maxCodepoints = 4000,
  }) {
    final result = <String>[];
    var current = StringBuffer(), length = 0;
    final pieces = RegExp(
      r'ZXQ(?:PH|NL)\d+QXZ|.',
      dotAll: true,
      unicode: true,
    ).allMatches(text);
    for (final piece in pieces) {
      final token = piece[0]!, count = token.runes.length;
      if (RegExp(r'^ZXQNL\d+QXZ$').hasMatch(token)) {
        if (length > 0) result.add(current.toString());
        result.add(token);
        current = StringBuffer();
        length = 0;
        continue;
      }
      final size = byteLimit ? utf8.encode(token).length : count;
      if (length + size > (byteLimit ? 480 : maxCodepoints) && length > 0) {
        result.add(current.toString());
        current = StringBuffer();
        length = 0;
      }
      current.write(token);
      length += size;
    }
    if (length > 0) result.add(current.toString());
    return result;
  }

  Future<TranslationResult> _proxyProvider(
    String provider,
    String source,
    String locale,
    String base,
    _Run run, {
    String email = '',
  }) async {
    final credentials = Map<String, String>.from(
      _credentials[provider] ?? const {},
    );
    if (provider == 'MyMemory' && email.isNotEmpty) {
      credentials['email'] = email;
    }
    if (provider == 'Tencent') {
      credentials.putIfAbsent('region', () => 'ap-guangzhou');
    }
    if (!providerCredentialsReady(provider, credentials)) {
      throw TranslationFailure(
        'PROVIDER_CONFIG',
        '$provider 尚未配置凭据，请先在设置中填写。',
        fatal: true,
        provider: provider,
      );
    }
    if (source.runes.length > 50000) {
      throw TranslationFailure(
        'PROVIDER_REQUEST',
        '单段最多 50,000 字符，请先拆分文案。',
        provider: provider,
      );
    }
    final endpoint = _endpoint(base, '/api/translation/provider');
    final whitespace = RegExp(r'^(\s*)([\s\S]*?)(\s*)$').firstMatch(source)!;
    final protected = _Protected(whitespace[2]!, newlines: true);
    final chunks = provider == 'ZTAITrans'
        ? [protected.text]
        : _proxyChunks(
            protected.text,
            byteLimit: provider == 'MyMemory',
            maxCodepoints: ['Baidu', 'Tencent', 'Alibaba'].contains(provider)
                ? 1000
                : 4000,
          );
    final output = StringBuffer();
    String? model;
    for (final chunk in chunks) {
      final spaces = RegExp(r'^(\s*)([\s\S]*?)(\s*)$').firstMatch(chunk)!;
      final core = spaces[2]!;
      if (core.isEmpty ||
          core
              .replaceAll(_marker, '')
              .replaceAll(RegExp(r'[\p{P}\p{S}\s\d]', unicode: true), '')
              .isEmpty) {
        output.write(chunk);
        continue;
      }
      final cacheKey =
          'provider\u0000$provider\u0000${endpoint.origin}\u0000$locale\u0000$core';
      var translated = run.bypassCache ? null : _cached(cacheKey);
      var chunkModel = _providerModels[cacheKey];
      if (translated == null) {
        final body = jsonEncode({
          'provider': provider,
          'content': core,
          'locale': locale,
          'credentials': credentials,
        });
        if (utf8.encode(body).length > 256 * 1024) {
          throw TranslationFailure(
            'PROVIDER_REQUEST',
            '请求内容过大，请先拆分段落。',
            provider: provider,
          );
        }
        for (var attempt = 0; ; attempt++) {
          try {
            run.status('$provider · 翻译中');
            run.requests++;
            final response = await _send(
              endpoint,
              token: run.token,
              timeout: provider == 'MyMemory' ? primaryTimeout : backupTimeout,
              body: body,
            );
            final payload = _body(response);
            if (response.statusCode != 200 || payload?['code'] != null) {
              throw _providerFailure(response, payload, provider);
            }
            final raw = payload?['text'];
            final reflectedSecret = credentials.entries
                .where(
                  (entry) =>
                      providerSecretFields.contains(entry.key) &&
                      entry.value.isNotEmpty,
                )
                .any(
                  (entry) =>
                      (raw is String && raw.contains(entry.value)) ||
                      (payload?['model'] is String &&
                          (payload!['model'] as String).contains(entry.value)),
                );
            if (raw is! String ||
                reflectedSecret ||
                raw.trim().isEmpty ||
                payload?['provider'] != provider ||
                RegExp(
                  r'^\s*(?:MYMEMORY WARNING:|<!doctype html|<html(?:\s|>)|UNAUTHORIZED\s*$|Internal Server Error\s*$)',
                  caseSensitive: false,
                ).hasMatch(raw)) {
              throw TranslationFailure(
                'PROVIDER_RESPONSE',
                '$provider 未返回有效译文，现有内容已保留。',
                provider: provider,
              );
            }
            translated = _normalizeMarkers(
              raw,
            ).replaceAll(RegExp(r'\r\n|\r|\n'), ' ').trim();
            _assertSame(_marker, core, translated);
            run.token.throwIfCancelled();
            chunkModel = payload?['model'] is String
                ? payload!['model'] as String
                : null;
            _remember(cacheKey, translated);
            if (chunkModel != null) _providerModels[cacheKey] = chunkModel;
            while (_providerModels.length > 500) {
              _providerModels.remove(_providerModels.keys.first);
            }
            break;
          } on TranslationFailure catch (error) {
            if (!error.retryable ||
                error.fatal ||
                error.quota ||
                attempt >= 1 ||
                error.retryAfter > const Duration(minutes: 1)) {
              rethrow;
            }
            await run.token.race(
              _sleep(
                error.retryAfter > const Duration(seconds: 1)
                    ? error.retryAfter
                    : const Duration(seconds: 1),
              ),
            );
          }
        }
      }
      final text = '${spaces[1]}$translated${spaces[3]}';
      // Retain the source boundary exactly; do not infer spaces between chunks.
      output.write(text);
      model ??= chunkModel;
    }
    final text =
        '${whitespace[1]}${protected.restore(output.toString())}${whitespace[3]}';
    _assertSame(_placeholder, source, text);
    return TranslationResult(text: text, provider: provider, model: model);
  }

  Future<TranslationResult> _configuredTranslation(
    String source,
    String locale,
    String email,
    String base,
    _Run run,
  ) async {
    if (_configuredEmail != email) {
      resetProviderState('MyMemory');
      _configuredEmail = email;
    }
    TranslationFailure? last;
    final order = _providerFallback ? _providerOrder! : _providerOrder!.take(1);
    for (final provider in order) {
      run.token.throwIfCancelled();
      if (!_supportsProvider(provider, locale)) {
        last = TranslationFailure(
          'PROVIDER_UNSUPPORTED',
          '$provider 暂不支持这个目标语言。',
          provider: provider,
        );
        if (_providerFallback) continue;
        throw last;
      }
      final until = _providerCooldowns[provider];
      if (until != null && until.isAfter(_now())) {
        last = TranslationFailure(
          'PROVIDER_QUOTA',
          '$provider 额度冷却中，稍后会自动恢复尝试。',
          quota: true,
          provider: provider,
          retryAfter: until.difference(_now()),
        );
        if (_providerFallback) continue;
        throw last;
      }
      try {
        final result =
            provider == 'MyMemory' &&
                (_credentials['MyMemory']?['apiKey'] ?? '').isEmpty
            ? TranslationResult(
                text: await _primary(source, locale, email, run),
                provider: provider,
              )
            : await _proxyProvider(
                provider,
                source,
                locale,
                base,
                run,
                email: email,
              );
        return TranslationResult(
          text: result.text,
          provider: result.provider,
          model: result.model,
          requestCount: run.requests,
          cached: run.requests == 0,
        );
      } on TranslationFailure catch (error) {
        last = TranslationFailure(
          error.code,
          error.message,
          retryable: error.retryable,
          quota: error.quota,
          fatal: error.fatal,
          retryAfter: error.retryAfter,
          provider: provider,
        );
        if (error.fatal) throw last;
        if (error.quota) {
          final cooldown = error.retryAfter > Duration.zero
              ? error.retryAfter
              : const Duration(hours: 1);
          _providerCooldowns[provider] = _now().add(
            Duration(
              milliseconds: cooldown.inMilliseconds.clamp(1000, 86400000),
            ),
          );
        }
        if (_providerFallback &&
            (error.quota || error.code == 'PROVIDER_UNSUPPORTED')) {
          continue;
        }
        throw last;
      }
    }
    throw last ??
        const TranslationFailure(
          'PROVIDER_CONFIG',
          '请配置至少一个翻译平台。',
          fatal: true,
        );
  }

  Future<TranslationResult> translate(
    String source,
    String locale, {
    required CancelToken token,
    String email = '',
    String apiBaseUrl = '',
    bool bypassCache = false,
    void Function(String)? onStatus,
  }) async {
    token.throwIfCancelled();
    if (!supportedLanguages.any((language) => language.code == locale)) {
      throw const TranslationFailure('LANGUAGE', '不支持这个目标语言。');
    }
    email = email.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const TranslationFailure(
        'EMAIL',
        '请填写有效的联系邮箱，或留空使用匿名额度。',
        fatal: true,
      );
    }
    if (source.trim().isEmpty) {
      return TranslationResult(
        text: source,
        provider: 'MyMemory',
        cached: true,
      );
    }
    final run = _Run(token, onStatus, bypassCache);
    if (_providerOrder != null) {
      return _configuredTranslation(source, locale, email, apiBaseUrl, run);
    }
    var provider = 'MyMemory';
    String text;
    if (!_languageMap.containsKey(locale) ||
        _circuitUntil != null && _circuitUntil!.isAfter(_now())) {
      provider = 'ZTAITrans';
      text = await _backup(source, locale, apiBaseUrl, run);
    } else {
      try {
        text = await _primary(source, locale, email, run);
      } on TranslationFailure catch (error) {
        token.throwIfCancelled();
        if (!error.quota) rethrow;
        final cooldown = error.retryAfter > Duration.zero
            ? error.retryAfter
            : const Duration(hours: 1);
        _circuitUntil = _now().add(
          Duration(milliseconds: cooldown.inMilliseconds.clamp(1000, 86400000)),
        );
        run.status('MyMemory 额度已用尽，整段切换至 ZTAITrans。');
        provider = 'ZTAITrans';
        text = await _backup(source, locale, apiBaseUrl, run);
      }
    }
    token.throwIfCancelled();
    return TranslationResult(
      text: text,
      provider: provider,
      requestCount: run.requests,
      cached: run.requests == 0,
    );
  }

  Future<bool> checkBackup(
    String apiBaseUrl, {
    String developerToken = '',
  }) async {
    final token = CancelToken();
    final response = await _send(
      _endpoint(apiBaseUrl, '/api/translation/status'),
      token: token,
      timeout: primaryTimeout,
      headers: {
        if (developerToken.isNotEmpty)
          'X-LangPack-Developer-Token': developerToken,
      },
    );
    final body = _body(response);
    if (response.statusCode != 200 || body?['backupConfigured'] is! bool) {
      throw TranslationFailure(
        'BACKUP_STATUS',
        response.statusCode == 401 || response.statusCode == 403
            ? '备用服务需要登录或授权，请检查服务地址。'
            : '无法读取备用服务状态，请检查部署地址。',
        fatal: true,
        provider: 'ZTAITrans',
      );
    }
    return body!['backupConfigured'] as bool;
  }

  void clearCache() {
    _cache.clear();
    _providerModels.clear();
  }

  void dispose() {
    _disposed = true;
    _credentials.clear();
    _client.close();
  }
}
