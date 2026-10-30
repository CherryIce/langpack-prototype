import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langpack/services/translation_service.dart';

http.Response primary(String text) => http.Response(
  jsonEncode({
    'responseStatus': 200,
    'responseData': {'translatedText': text},
  }),
  200,
);
http.Response proxy(String provider, String text) => http.Response(
  jsonEncode({'provider': provider, 'text': text, 'model': 'fixture-model'}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response errorResponse(
  String provider,
  String code,
  int status, {
  bool quota = false,
  bool unsupported = false,
  bool fatal = false,
}) => http.Response(
  jsonEncode({
    'provider': provider,
    'code': code,
    'quota': quota,
    'unsupported': unsupported,
    'fatal': fatal,
    'retryable': false,
    'message': 'secret_should_never_be_displayed',
  }),
  status,
);

void configure(
  TranslationService service,
  List<String> order, {
  bool fallback = true,
  int revision = 1,
  Map<String, Map<String, String>> credentials = const {},
}) => service.setProviderConfiguration(
  order: order,
  fallback: fallback,
  credentials: credentials,
  revision: revision,
);

void main() {
  for (final statuses in [(401, 200), (403, 200), (200, 401)]) {
    test(
      'MyMemory auth $statuses overrides a contradictory quota signal',
      () async {
        final methods = <String>[];
        final service = TranslationService(
          client: MockClient((request) async {
            methods.add(request.method);
            return http.Response(
              jsonEncode({
                'responseStatus': statuses.$2,
                'quotaFinished': true,
                'responseDetails': 'YOU USED ALL AVAILABLE FREE TRANSLATIONS',
                'responseData': {
                  'translatedText': 'MYMEMORY WARNING: OUT OF QUOTA',
                },
              }),
              statuses.$1,
            );
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        configure(
          service,
          ['MyMemory', 'DeepL'],
          credentials: {
            'DeepL': {'apiKey': 'fixture', 'plan': 'free'},
          },
        );
        await expectLater(
          service.translate('你好', 'en', token: CancelToken()),
          throwsA(
            isA<TranslationFailure>()
                .having((e) => e.code, 'code', 'PROVIDER_AUTH')
                .having((e) => e.fatal, 'fatal', true)
                .having((e) => e.quota, 'quota', false),
          ),
        );
        expect(methods, ['GET']);
      },
    );
  }

  for (final genuineQuota in [true, false]) {
    test(
      'HTTP 200 MyMemory business 403 preserves genuine quota only: $genuineQuota',
      () async {
        final methods = <String>[];
        final service = TranslationService(
          client: MockClient((request) async {
            methods.add(request.method);
            if (request.method == 'POST') return proxy('DeepL', 'Hello');
            return http.Response(
              jsonEncode({
                'responseStatus': 403,
                'quotaFinished': genuineQuota,
                'responseDetails': genuineQuota
                    ? 'YOU USED ALL AVAILABLE FREE TRANSLATIONS'
                    : 'Access denied',
                'responseData': {'translatedText': ''},
              }),
              200,
            );
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        configure(
          service,
          ['MyMemory', 'DeepL'],
          credentials: {
            'DeepL': {'apiKey': 'fixture', 'plan': 'free'},
          },
        );
        if (genuineQuota) {
          expect(
            (await service.translate(
              '你好',
              'en',
              token: CancelToken(),
            )).provider,
            'DeepL',
          );
          expect(methods, ['GET', 'POST']);
        } else {
          await expectLater(
            service.translate('你好', 'en', token: CancelToken()),
            throwsA(
              isA<TranslationFailure>().having(
                (e) => e.code,
                'code',
                'PROVIDER_AUTH',
              ),
            ),
          );
          expect(methods, ['GET']);
        }
      },
    );
  }

  for (final separated in [false, true]) {
    test(
      'cloud joins preserve the existing boundary, separated=$separated',
      () async {
        var calls = 0;
        final service = TranslationService(
          client: MockClient((request) async {
            calls++;
            return proxy('Google', calls == 1 ? 'North' : 'bound');
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        configure(
          service,
          ['Google'],
          credentials: {
            'Google': {'apiKey': 'fixture'},
          },
        );
        final source = separated ? '${'中' * 3999} 文' : '${'中' * 4000}文';
        final result = await service.translate(
          source,
          'en',
          token: CancelToken(),
        );
        expect(result.text, separated ? 'North bound' : 'Northbound');
        expect(calls, 2);
      },
    );
  }

  test(
    'MyMemory private key uses the fixed proxy with 480-byte chunks and no secret URL',
    () async {
      final requests = <Map>[];
      final service = TranslationService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/translation/provider');
          expect(request.url.query, isEmpty);
          final body = jsonDecode(request.body) as Map;
          requests.add(body);
          expect(body['provider'], 'MyMemory');
          expect(body['credentials'], {
            'apiKey': 'private-fixture',
            'email': 'author@example.com',
          });
          expect(
            utf8.encode(body['content'] as String).length,
            lessThanOrEqualTo(480),
          );
          return proxy('MyMemory', body['content'] as String);
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['MyMemory'],
        credentials: {
          'MyMemory': {'apiKey': 'private-fixture'},
        },
      );
      final source = '${'中' * 159}{name}\r\n${'😀中文' * 80}';
      final result = await service.translate(
        source,
        'zh-Hant',
        token: CancelToken(),
        email: 'author@example.com',
      );
      expect(result.text, source);
      expect(requests.length, greaterThan(1));
    },
  );

  test(
    'each account has an independent quota cooldown and unchanged identities retain theirs',
    () async {
      var now = DateTime.utc(2026, 10, 30);
      final seen = <String>[], counts = <String, int>{};
      final service = TranslationService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final provider = body['provider'] as String;
          seen.add(provider);
          counts[provider] = (counts[provider] ?? 0) + 1;
          if (counts[provider] == 1 && provider != 'Google') {
            return http.Response(
              jsonEncode({
                'provider': provider,
                'code': 'PROVIDER_QUOTA',
                'quota': true,
                'retryAfterMs': provider == 'DeepL' ? 1000 : 3000,
              }),
              402,
            );
          }
          return proxy(provider, 'Translated');
        }),
        now: () => now,
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      const credentials = {
        'DeepL': {'apiKey': 'd', 'plan': 'free'},
        'Azure': {'apiKey': 'a'},
        'Google': {'apiKey': 'g'},
      };
      configure(service, [
        'DeepL',
        'Azure',
        'Google',
      ], credentials: credentials);
      await service.translate('一', 'en', token: CancelToken());
      now = now.add(const Duration(milliseconds: 1500));
      expect(
        (await service.translate('二', 'en', token: CancelToken())).provider,
        'DeepL',
      );
      configure(service, ['Azure', 'Google'], credentials: credentials);
      expect(
        (await service.translate('三', 'en', token: CancelToken())).provider,
        'Google',
      );
      now = now.add(const Duration(seconds: 2));
      expect(
        (await service.translate('四', 'en', token: CancelToken())).provider,
        'Azure',
      );
      expect(seen, ['DeepL', 'Azure', 'Google', 'DeepL', 'Google', 'Azure']);
    },
  );

  test(
    'email identity change restores MyMemory without resetting another provider cooldown',
    () async {
      final providers = <String>[];
      var primaryCalls = 0;
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            providers.add('MyMemory');
            primaryCalls++;
            return primaryCalls == 1
                ? http.Response('{"quotaFinished":true}', 200)
                : primary('Recovered');
          }
          providers.add('Azure');
          return proxy('Azure', 'Fallback');
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['MyMemory', 'Azure'],
        credentials: {
          'Azure': {'apiKey': 'fixture'},
        },
      );
      await service.translate('一', 'en', token: CancelToken());
      await service.translate('二', 'en', token: CancelToken());
      expect(providers, ['MyMemory', 'Azure', 'Azure']);
      final recovered = await service.translate(
        '三',
        'en',
        token: CancelToken(),
        email: 'author@example.com',
      );
      expect(recovered.provider, 'MyMemory');
      expect(providers.last, 'MyMemory');
    },
  );

  test(
    'authorization overrides contradictory quota and unsupported metadata',
    () async {
      final seen = <String>[];
      final service = TranslationService(
        client: MockClient((request) async {
          final provider =
              (jsonDecode(request.body) as Map)['provider'] as String;
          seen.add(provider);
          return errorResponse(
            provider,
            'PROVIDER_QUOTA',
            401,
            quota: true,
            unsupported: true,
          );
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['DeepL', 'Azure'],
        credentials: {
          'DeepL': {'apiKey': 'd', 'plan': 'free'},
          'Azure': {'apiKey': 'a'},
        },
      );
      await expectLater(
        service.translate('你好', 'en', token: CancelToken()),
        throwsA(
          isA<TranslationFailure>()
              .having((e) => e.code, 'code', 'PROVIDER_AUTH')
              .having((e) => e.fatal, 'fatal', true)
              .having((e) => e.quota, 'quota', false),
        ),
      );
      expect(seen, ['DeepL']);
    },
  );

  test(
    'cloud newline at a chunk boundary retains exact CRLF without added spaces',
    () async {
      var calls = 0;
      final service = TranslationService(
        client: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map;
          expect(body['content'], isNot(contains('ZXQNL')));
          return proxy('Google', calls == 1 ? 'Word' : 'Next');
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['Google'],
        credentials: {
          'Google': {'apiKey': 'fixture'},
        },
      );
      final result = await service.translate(
        '  ${'中' * 4000}\r\n中文  ',
        'en',
        token: CancelToken(),
      );
      expect(result.text, '  Word\r\nNext  ');
      expect(calls, 2);
    },
  );

  test('configured default cannot use anonymous ZTAI fallback', () async {
    final methods = <String>[];
    final service = TranslationService(
      client: MockClient((request) async {
        methods.add(request.method);
        return http.Response(
          jsonEncode({
            'quotaFinished': true,
            'responseStatus': 403,
            'responseData': {'translatedText': ''},
          }),
          200,
        );
      }),
      minInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    configure(service, ['MyMemory']);
    await expectLater(
      service.translate('登录', 'en', token: CancelToken()),
      throwsA(isA<TranslationFailure>().having((e) => e.quota, 'quota', true)),
    );
    expect(methods, ['GET']);
    await expectLater(
      service.translate('登录', 'pt-BR', token: CancelToken()),
      throwsA(
        isA<TranslationFailure>().having(
          (e) => e.code,
          'code',
          'PROVIDER_UNSUPPORTED',
        ),
      ),
    );
    expect(methods, ['GET']);
  });

  test(
    'quota falls back to configured DeepL and each expired provider recovers',
    () async {
      var now = DateTime.utc(2026, 10, 30);
      final providers = <String>[];
      var primaryCalls = 0, deepLCalls = 0;
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            providers.add('MyMemory');
            primaryCalls++;
            return primaryCalls == 1
                ? http.Response(jsonEncode({'quotaFinished': true}), 200)
                : primary('Recovered');
          }
          final body = jsonDecode(request.body) as Map;
          final provider = body['provider'] as String;
          providers.add(provider);
          expect(request.url.path, '/api/translation/provider');
          expect(request.url.query, isEmpty);
          if (provider == 'DeepL') {
            expect(body['credentials'], {
              'apiKey': 'deepl-fixture',
              'plan': 'free',
            });
            deepLCalls++;
            if (deepLCalls == 1) {
              return errorResponse(
                provider,
                'PROVIDER_QUOTA',
                402,
                quota: true,
              );
            }
          }
          return proxy(provider, 'Translated');
        }),
        minInterval: Duration.zero,
        now: () => now,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['MyMemory', 'DeepL', 'Azure'],
        credentials: {
          'DeepL': {'apiKey': 'deepl-fixture', 'plan': 'free'},
          'Azure': {'apiKey': 'azure-fixture', 'region': 'eastasia'},
        },
      );
      final first = await service.translate('登录', 'en', token: CancelToken());
      expect(first.provider, 'Azure');
      await service.translate('注册', 'en', token: CancelToken());
      expect(providers, ['MyMemory', 'DeepL', 'Azure', 'Azure']);
      now = now.add(const Duration(hours: 1, seconds: 1));
      final recovered = await service.translate(
        '设置',
        'en',
        token: CancelToken(),
      );
      expect(recovered.provider, 'MyMemory');
      expect(providers.last, 'MyMemory');
    },
  );

  test(
    'unsupported locale skips to configured Azure without substituting language',
    () async {
      final seen = <Map>[];
      final service = TranslationService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          seen.add(body);
          return proxy(body['provider'] as String, 'Translated');
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['MyMemory', 'DeepL', 'Google', 'Azure'],
        credentials: {
          'Google': {'apiKey': 'google-fixture'},
          'Azure': {'apiKey': 'azure-fixture'},
        },
      );
      expect(
        (await service.translate('你好', 'fil', token: CancelToken())).provider,
        'Google',
      );
      configure(
        service,
        ['Google', 'Azure'],
        credentials: {
          'Google': {'apiKey': 'google-fixture'},
          'Azure': {'apiKey': 'azure-fixture'},
        },
      );
      expect(
        (await service.translate('你好', 'nb', token: CancelToken())).provider,
        'Azure',
      );
      expect(seen.map((body) => body['locale']), ['fil', 'nb']);
    },
  );

  for (final entry in [
    ('PROVIDER_AUTH', 401),
    ('PROVIDER_CONFIG', 400),
    ('PROVIDER_RATE_LIMIT', 429),
    ('PROVIDER_REQUEST', 400),
  ]) {
    test(
      '${entry.$1} never switches to another account or reveals provider text',
      () async {
        final requested = <String>[];
        final service = TranslationService(
          client: MockClient((request) async {
            final provider =
                (jsonDecode(request.body) as Map)['provider'] as String;
            requested.add(provider);
            return errorResponse(
              provider,
              entry.$1,
              entry.$2,
              fatal: ['PROVIDER_AUTH', 'PROVIDER_CONFIG'].contains(entry.$1),
            );
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        configure(
          service,
          ['DeepL', 'Azure'],
          credentials: {
            'DeepL': {
              'apiKey': 'secret_should_never_be_displayed',
              'plan': 'free',
            },
            'Azure': {'apiKey': 'azure-fixture'},
          },
        );
        await expectLater(
          service.translate('你好', 'en', token: CancelToken()),
          throwsA(
            isA<TranslationFailure>()
                .having((e) => e.provider, 'provider', 'DeepL')
                .having(
                  (e) => e.message,
                  'redacted',
                  isNot(contains('secret_should_never_be_displayed')),
                ),
          ),
        );
        expect(requested, ['DeepL']);
      },
    );
  }

  test(
    'disabled fallback stops at unsupported primary and missing credentials stop locally',
    () async {
      var calls = 0;
      final service = TranslationService(
        client: MockClient((request) async {
          calls++;
          return proxy('Azure', 'Translated');
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['MyMemory', 'Azure'],
        fallback: false,
        credentials: {
          'Azure': {'apiKey': 'fixture'},
        },
      );
      await expectLater(
        service.translate('你好', 'pt-BR', token: CancelToken()),
        throwsA(isA<TranslationFailure>()),
      );
      configure(
        service,
        ['ZTAITrans', 'Azure'],
        credentials: {
          'Azure': {'apiKey': 'fixture'},
        },
      );
      await expectLater(
        service.translate('你好', 'en', token: CancelToken()),
        throwsA(
          isA<TranslationFailure>().having(
            (e) => e.code,
            'code',
            'PROVIDER_CONFIG',
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test(
    'credential revision isolates cached results and developer status is a GET with header only',
    () async {
      final bodies = <Map>[];
      final service = TranslationService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            expect(request.url.path, '/api/translation/status');
            expect(request.url.query, isEmpty);
            expect(
              request.headers['X-LangPack-Developer-Token'],
              'developer-fixture',
            );
            return http.Response(
              '{"backupConfigured":true,"developerConfigured":true}',
              200,
            );
          }
          final body = jsonDecode(request.body) as Map;
          bodies.add(body);
          expect(body['credentials'], {
            'developerToken': bodies.length == 1
                ? 'old-fixture'
                : 'new-fixture',
          });
          return proxy('ZTAITrans', 'Translated ${bodies.length}');
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['ZTAITrans'],
        credentials: {
          'ZTAITrans': {'developerToken': 'old-fixture'},
        },
      );
      final first = await service.translate('登录', 'en', token: CancelToken());
      final cached = await service.translate('登录', 'en', token: CancelToken());
      expect(first.text, cached.text);
      expect(cached.cached, isTrue);
      configure(
        service,
        ['ZTAITrans'],
        revision: 2,
        credentials: {
          'ZTAITrans': {'developerToken': 'new-fixture'},
        },
      );
      final updated = await service.translate('登录', 'en', token: CancelToken());
      expect(updated.text, 'Translated 2');
      expect(updated.model, 'fixture-model');
      expect(
        await service.checkBackup('', developerToken: 'developer-fixture'),
        isTrue,
      );
      expect(bodies.length, 2);
    },
  );

  test(
    'cloud chunks retain markers, newlines, Unicode and do not exceed 4000 characters',
    () async {
      final contents = <String>[];
      final service = TranslationService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final text = body['content'] as String;
          contents.add(text);
          expect(text.runes.length, lessThanOrEqualTo(4000));
          expect(
            RegExp(r'ZXQ(?:PH|NL)\d+QXZ').allMatches(text).length,
            RegExp(r'ZXQ').allMatches(text).length,
          );
          return proxy('Google', text);
        }),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      configure(
        service,
        ['Google'],
        credentials: {
          'Google': {'apiKey': 'google-fixture'},
        },
      );
      final source = '  ${'😀中文' * 1600}{name}\n${'中文。' * 200}  ';
      final result = await service.translate(
        source,
        'zh-Hant',
        token: CancelToken(),
      );
      expect(result.text, source);
      expect(contents.length, greaterThan(1));
    },
  );
}
