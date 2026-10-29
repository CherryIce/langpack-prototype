import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';

http.Response success(String text) => http.Response(
  jsonEncode({
    'responseStatus': 200,
    'responseData': {'translatedText': text},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response quota() => http.Response(
  jsonEncode({
    'responseStatus': 403,
    'quotaFinished': true,
    'responseData': {
      'translatedText':
          'MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS',
    },
  }),
  200,
);
http.Response backup(String text) => http.Response(
  jsonEncode({'text': text, 'provider': 'ZTAITrans'}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Matcher failure(String code, {bool? fatal, bool? isQuota}) =>
    isA<TranslationFailure>()
        .having((value) => value.code, 'code', code)
        .having(
          (value) => fatal == null || value.fatal == fatal,
          'fatal matches',
          true,
        )
        .having(
          (value) => isQuota == null || value.quota == isQuota,
          'quota matches',
          true,
        );

void main() {
  group('UTF-8 chunks', () {
    test('preserves every Unicode scalar and marker within 480 bytes', () {
      final source = '${'这是一段带有表情的中文😀。' * 90}ZXQPH123456QXZ${'尾部' * 80}';
      final chunks = splitTranslationText(source);
      expect(chunks.join(), source);
      expect(chunks.every((piece) => utf8.encode(piece).length <= 480), true);
      expect(
        chunks.where((piece) => piece.contains('ZXQPH123456QXZ')).length,
        1,
      );
      expect(chunks.every((piece) => !piece.runes.contains(0xfffd)), true);
    });
    test('prefers sentence boundary and enforces valid maximum', () {
      expect(splitTranslationText('第一句。第二句话很长', maxBytes: 24).first, '第一句。');
      expect(
        () => splitTranslationText('text', maxBytes: 501),
        throwsRangeError,
      );
    });
  });

  test('uses real endpoint parameters and locale mapping', () async {
    late Uri observed;
    final service = TranslationService(
      client: MockClient((request) async {
        observed = request.url;
        return success('登入');
      }),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    final result = await service.translate(
      '登录',
      'zh-Hant',
      token: CancelToken(),
      email: 'person@example.com',
    );
    expect(observed.host, 'api.mymemory.translated.net');
    expect(observed.queryParameters, {
      'q': '登录',
      'langpair': 'zh-CN|zh-TW',
      'mt': '1',
      'de': 'person@example.com',
    });
    expect(result.text, '登入');
    expect(result.provider, 'MyMemory');
    expect(result.requestCount, 1);
  });

  test(
    'preserves repeated placeholders, literal marker, newlines and outer whitespace',
    () async {
      final service = TranslationService(
        client: MockClient(
          (request) async => success(
            request.url.queryParameters['q']!
                .replaceAll('你好', 'Hello')
                .replaceAll('欢迎', 'Welcome')
                .replaceAll('余额', 'Balance'),
          ),
        ),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      const source =
          '  你好 {{ name }}、{name}、{name}。\r\n欢迎 ZXQPH0QXZ\n余额 %1\$s %%  ';
      final result = await service.translate(
        source,
        'en',
        token: CancelToken(),
      );
      expect(
        result.text,
        '  Hello {{ name }}、{name}、{name}。\r\nWelcome ZXQPH0QXZ\nBalance %1\$s %%  ',
      );
    },
  );

  test(
    'rejects missing protected placeholder rather than storing corrupt text',
    () async {
      final service = TranslationService(
        client: MockClient((_) async => success('Hello')),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      await expectLater(
        service.translate('你好 {name}', 'en', token: CancelToken()),
        throwsA(failure('PLACEHOLDER')),
      );
    },
  );

  test('decodes API entities once and caches successful segments', () async {
    var calls = 0;
    final service = TranslationService(
      client: MockClient((_) async {
        calls++;
        return success('Tom &amp; Jerry &#x1F600;');
      }),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    final first = await service.translate('汤姆和杰瑞', 'en', token: CancelToken());
    final second = await service.translate('汤姆和杰瑞', 'en', token: CancelToken());
    expect(first.text, 'Tom & Jerry 😀');
    expect(second.cached, true);
    expect(second.requestCount, 0);
    expect(calls, 1);
  });

  test(
    'temporary failures retry twice; ordinary errors never call backup',
    () async {
      var calls = 0;
      final waits = <Duration>[];
      final service = TranslationService(
        client: MockClient((request) async {
          expect(request.url.host, 'api.mymemory.translated.net');
          calls++;
          return calls < 3
              ? http.Response('Unavailable', 503)
              : success('Sign in');
        }),
        minInterval: Duration.zero,
        sleep: (value) async {
          waits.add(value);
        },
      );
      addTearDown(service.dispose);
      final result = await service.translate(
        '登录',
        'en',
        token: CancelToken(),
        apiBaseUrl: 'https://backup.example',
      );
      expect(result.text, 'Sign in');
      expect(calls, 3);
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    },
  );

  test('explicit retranslation bypasses the cache', () async {
    var calls = 0;
    final service = TranslationService(
      client: MockClient((_) async {
        calls++;
        return success('Result $calls');
      }),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    await service.translate('登录', 'en', token: CancelToken());
    final result = await service.translate(
      '登录',
      'en',
      token: CancelToken(),
      bypassCache: true,
    );
    expect(result.text, 'Result 2');
    expect(result.cached, false);
  });

  test('failed long paragraphs reuse completed chunks on retry', () async {
    final seen = <String>[];
    final service = TranslationService(
      client: MockClient((request) async {
        seen.add(request.url.queryParameters['q']!);
        return seen.length == 2
            ? http.Response('{}', 503)
            : success('Translated segment.');
      }),
      minInterval: Duration.zero,
      maxRetries: 0,
    );
    addTearDown(service.dispose);
    final source = '${'甲' * 150}。${'乙' * 150}。${'丙' * 150}。';
    await expectLater(
      service.translate(source, 'en', token: CancelToken()),
      throwsA(failure('REQUEST')),
    );
    final result = await service.translate(source, 'en', token: CancelToken());
    expect(
      result.text,
      'Translated segment. Translated segment. Translated segment.',
    );
    expect(seen.where((chunk) => chunk.contains('甲')).length, 1);
    expect(seen.every((chunk) => utf8.encode(chunk).length <= 480), true);
  });

  test('concurrent paragraphs share the serial rate limiter', () async {
    final waits = <Duration>[];
    var active = 0, maximum = 0;
    final service = TranslationService(
      client: MockClient((_) async {
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.delayed(Duration.zero);
        active--;
        return success('Translated');
      }),
      now: () => DateTime.utc(2026),
      sleep: (value) async {
        waits.add(value);
      },
    );
    addTearDown(service.dispose);
    await Future.wait([
      service.translate('登录', 'en', token: CancelToken()),
      service.translate('注册', 'en', token: CancelToken()),
    ]);
    expect(maximum, 1);
    expect(waits, [const Duration(milliseconds: 1100)]);
  });

  test('HTTP 400 is not retried or treated as quota', () async {
    var calls = 0;
    final service = TranslationService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 400);
      }),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.translate(
        '登录',
        'en',
        token: CancelToken(),
        apiBaseUrl: 'https://backup.example',
      ),
      throwsA(failure('REQUEST', isQuota: false)),
    );
    expect(calls, 1);
  });

  test('long Retry-After is returned without shortening or retry', () async {
    var calls = 0;
    final service = TranslationService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 429, headers: {'retry-after': '120'});
      }),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.translate('登录', 'en', token: CancelToken()),
      throwsA(
        isA<TranslationFailure>().having(
          (e) => e.retryAfter,
          'server wait',
          const Duration(seconds: 120),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('HTTP date Retry-After is honored', () async {
    final service = TranslationService(
      client: MockClient(
        (_) async => http.Response(
          '{}',
          429,
          headers: {'retry-after': 'Thu, 29 Oct 2026 10:05:00 GMT'},
        ),
      ),
      now: () => DateTime.utc(2026, 10, 29, 10),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.translate('登录', 'en', token: CancelToken()),
      throwsA(
        isA<TranslationFailure>().having(
          (e) => e.retryAfter,
          'server date',
          const Duration(minutes: 5),
        ),
      ),
    );
  });

  test(
    'quota switches original complete paragraph to backup and cools down primary',
    () async {
      var primaryCalls = 0;
      final received = <String>[];
      final source = '  ${'这是中文内容。' * 60}\n欢迎 {name}  ';
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.url.host == 'api.mymemory.translated.net') {
            primaryCalls++;
            return primaryCalls == 1
                ? success('Partial primary result.')
                : quota();
          }
          expect(request.url.path, '/api/translation/backup');
          expect(
            request.headers.keys.any(
              (key) => key.toLowerCase().contains('key'),
            ),
            false,
          );
          final content =
              (jsonDecode(request.body) as Map)['content'] as String;
          received.add(content);
          return backup(
            content
                .replaceAll('这是中文内容。', 'Translated.')
                .replaceAll('欢迎', 'Welcome'),
          );
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      final result = await service.translate(
        source,
        'en',
        token: CancelToken(),
        apiBaseUrl: 'https://backup.example',
      );
      expect(result.provider, 'ZTAITrans');
      expect(result.text, '  ${'Translated.' * 60}\nWelcome {name}  ');
      expect(result.text.contains('Partial primary result'), false);
      expect(received.single.contains('这是中文内容。' * 60), true);
      final second = await service.translate(
        '第二段',
        'ja',
        token: CancelToken(),
        apiBaseUrl: 'https://backup.example',
      );
      expect(second.provider, 'ZTAITrans');
      expect(primaryCalls, 2);
    },
  );

  test(
    'native default and legacy empty settings use public proxy without a key',
    () async {
      final settings = AppSettings.fromJson({'apiBaseUrl': ''});
      var primaryCalls = 0;
      final requests = <http.Request>[];
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.url.host == 'api.mymemory.translated.net') {
            primaryCalls++;
            return quota();
          }
          requests.add(request);
          expect(request.url.origin, defaultBackupServiceOrigin);
          expect(
            request.headers.keys.any(
              (key) => RegExp(
                r'authorization|api.?key|cookie',
                caseSensitive: false,
              ).hasMatch(key),
            ),
            isFalse,
          );
          if (request.method == 'GET') {
            expect(request.url.path, '/api/translation/status');
            return http.Response('{"backupConfigured":true}', 200);
          }
          expect(request.url.path, '/api/translation/backup');
          expect(jsonDecode(request.body), {'content': '登录', 'locale': 'en'});
          return backup('Log in');
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      expect(await service.checkBackup(settings.apiBaseUrl), isTrue);
      final result = await service.translate(
        '登录',
        'en',
        token: CancelToken(),
        apiBaseUrl: settings.apiBaseUrl,
      );
      expect(result.text, 'Log in');
      expect(result.provider, 'ZTAITrans');
      expect(primaryCalls, 1);
      expect(requests.length, 2);
    },
  );

  test(
    'explicit custom proxy is retained instead of the built-in default',
    () async {
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.url.host == 'api.mymemory.translated.net') return quota();
          expect(request.url.origin, 'https://custom.example');
          return backup('Custom login');
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      final settings = AppSettings.fromJson({
        'apiBaseUrl': 'https://custom.example',
      });
      final result = await service.translate(
        '登录',
        'en',
        token: CancelToken(),
        apiBaseUrl: settings.apiBaseUrl,
      );
      expect(result.text, 'Custom login');
    },
  );

  for (final item in [
    (401, 'BACKUP_AUTH', true, false),
    (402, 'BACKUP_BUDGET', false, true),
  ]) {
    test('backup ${item.$2} is terminal without retry', () async {
      var backups = 0;
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.url.host == 'api.mymemory.translated.net') return quota();
          backups++;
          return http.Response(
            jsonEncode({'code': item.$2, 'retryable': false}),
            item.$1,
          );
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      await expectLater(
        service.translate(
          '登录',
          'en',
          token: CancelToken(),
          apiBaseUrl: 'https://backup.example',
        ),
        throwsA(failure(item.$2, fatal: item.$3, isQuota: item.$4)),
      );
      expect(backups, 1);
    });
  }

  test(
    'backup strips no original whitespace and protects source-like markers',
    () async {
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.url.host == 'api.mymemory.translated.net') return quota();
          final content =
              (jsonDecode(request.body) as Map)['content'] as String;
          return backup(content.replaceAll('你好', 'Hello'));
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      const source = ' \t你好 ZXQNL0QXZ {{ x }}\r\n你好 %s\n  ';
      final result = await service.translate(
        source,
        'en',
        token: CancelToken(),
        apiBaseUrl: 'https://backup.example',
      );
      expect(result.text, ' \tHello ZXQNL0QXZ {{ x }}\r\nHello %s\n  ');
    },
  );

  test('cancel prevents active response and later queued requests', () async {
    final response = Completer<http.Response>();
    var calls = 0;
    final service = TranslationService(
      client: MockClient((_) {
        calls++;
        return response.future;
      }),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    final token = CancelToken();
    final first = service.translate('第一段', 'en', token: token);
    final second = service.translate('第二段', 'en', token: token);
    final checks = [
      expectLater(first, throwsA(failure('ABORTED'))),
      expectLater(second, throwsA(failure('ABORTED'))),
    ];
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    response.complete(success('Late result'));
    await Future.wait(checks);
    expect(calls, 1);
  });

  test('timeout does not hang on a nonresponsive HTTP client', () async {
    final service = TranslationService(
      client: MockClient((_) => Completer<http.Response>().future),
      minInterval: Duration.zero,
      primaryTimeout: const Duration(milliseconds: 10),
      maxRetries: 0,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.translate('登录', 'en', token: CancelToken()),
      throwsA(failure('TIMEOUT')),
    );
  });

  test('rejects invalid email before making HTTP request', () async {
    final service = TranslationService(
      client: MockClient((_) async => throw StateError('Must not request')),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.translate('登录', 'en', token: CancelToken(), email: 'invalid'),
      throwsA(failure('EMAIL', fatal: true)),
    );
  });

  test('status distinguishes unconfigured server and login HTML', () async {
    var calls = 0;
    final service = TranslationService(
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('{"backupConfigured":false}', 200)
            : http.Response('<html>login</html>', 200);
      }),
    );
    addTearDown(service.dispose);
    expect(await service.checkBackup('https://backup.example'), false);
    await expectLater(
      service.checkBackup('https://backup.example'),
      throwsA(failure('BACKUP_STATUS', fatal: true)),
    );
  });

  test('rejects insecure remote proxy URL before sending source', () async {
    final service = TranslationService(
      client: MockClient((request) async {
        expect(request.url.host, 'api.mymemory.translated.net');
        return quota();
      }),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.translate(
        '登录',
        'en',
        token: CancelToken(),
        apiBaseUrl: 'http://remote.example',
      ),
      throwsA(failure('BACKUP_HTTPS', fatal: true)),
    );
  });
}
