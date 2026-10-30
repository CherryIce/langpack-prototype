import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const domesticCredentials = <String, Map<String, String>>{
  'Baidu': {
    'appId': 'baidu_app_fixture_123',
    'secretKey': 'baidu_secret_fixture_456',
  },
  'Tencent': {
    'secretId': 'tencent_id_fixture_123',
    'secretKey': 'tencent_secret_fixture_456',
  },
  'Alibaba': {
    'accessKeyId': 'alibaba_id_fixture_123',
    'accessKeySecret': 'alibaba_secret_fixture_456',
  },
};
const tencentLocales = [
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
];

http.Response translated(
  String provider,
  String text, {
  String model = 'domestic-model',
}) => http.Response(
  jsonEncode({'provider': provider, 'text': text, 'model': model}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all domestic providers are canonical and require both credential fields',
    () {
      expect(translationProviders.length, 8);
      for (final entry in domesticCredentials.entries) {
        expect(normalizeProviderOrder([entry.key, entry.key, 'unknown']), [
          entry.key,
        ]);
        expect(providerCredentialsReady(entry.key, entry.value), isTrue);
        for (final field in entry.value.keys) {
          final incomplete = {...entry.value}..remove(field);
          expect(providerCredentialsReady(entry.key, incomplete), isFalse);
        }
      }
    },
  );

  for (final provider in domesticCredentials.keys) {
    test(
      '$provider sends complete BYOK only to the same-origin proxy with safe chunks',
      () async {
        final requests = <Map>[];
        final service = TranslationService(
          client: MockClient((request) async {
            expect(request.url.origin, defaultBackupServiceOrigin);
            expect(request.method, 'POST');
            expect(request.url.path, '/api/translation/provider');
            expect(request.url.query, isEmpty);
            expect(request.url.toString(), isNot(contains('fixture')));
            final body = jsonDecode(request.body) as Map;
            requests.add(body);
            expect(body['provider'], provider);
            final expectedCredentials = {
              ...domesticCredentials[provider]!,
              if (provider == 'Tencent') 'region': 'ap-guangzhou',
            };
            expect(body['credentials'], expectedCredentials);
            final content = body['content'] as String;
            expect(content.runes.length, lessThanOrEqualTo(1000));
            if (provider == 'Baidu') {
              expect(utf8.encode(content).length, lessThanOrEqualTo(6000));
            }
            expect(
              RegExp(r'ZXQ(?:PH|NL)\d+QXZ').allMatches(content).length,
              RegExp('ZXQ').allMatches(content).length,
            );
            return translated(provider, content);
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        service.setProviderConfiguration(
          order: [provider],
          fallback: true,
          credentials: {provider: domesticCredentials[provider]!},
          revision: 1,
        );
        final source = '  ${'中' * 997}{name}\r\n${'😀中文' * 800}\t ';
        final result = await service.translate(
          source,
          'en',
          token: CancelToken(),
        );
        expect(result.text, source);
        expect(result.provider, provider);
        expect(requests.length, greaterThan(1));
      },
    );

    test(
      '$provider capability fallback keeps exact resource locale without aliases',
      () async {
        final seen = <Map>[];
        final service = TranslationService(
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map;
            seen.add(body);
            return translated(body['provider'] as String, 'Translated');
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        service.setProviderConfiguration(
          order: [provider, 'Azure'],
          fallback: true,
          credentials: {
            provider: domesticCredentials[provider]!,
            'Azure': {'apiKey': 'azure_matrix_fixture_123'},
          },
          revision: 1,
        );
        for (final language in supportedLanguages) {
          final supported = switch (provider) {
            'Baidu' => !['pt-BR', 'pt-PT'].contains(language.code),
            'Tencent' => tencentLocales.contains(language.code),
            _ => !['pt-BR', 'pt-PT', 'nb', 'hr', 'uk'].contains(language.code),
          };
          final result = await service.translate(
            '文案',
            language.code,
            token: CancelToken(),
          );
          expect(result.provider, supported ? provider : 'Azure');
          expect(seen.last['locale'], language.code);
        }
        expect(seen.length, 34);
      },
    );

    test(
      '$provider rejects incomplete credentials before making an HTTP request',
      () async {
        var requests = 0;
        final service = TranslationService(
          client: MockClient((request) async {
            requests++;
            return translated(provider, 'Unexpected');
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        for (final missing in domesticCredentials[provider]!.keys) {
          final partial = {...domesticCredentials[provider]!}..remove(missing);
          service.setProviderConfiguration(
            order: [provider, 'Azure'],
            fallback: true,
            credentials: {
              provider: partial,
              'Azure': {'apiKey': 'azure_fixture_key'},
            },
            revision: requests,
          );
          await expectLater(
            service.translate('登录', 'en', token: CancelToken()),
            throwsA(
              isA<TranslationFailure>().having(
                (e) => e.code,
                'code',
                'PROVIDER_CONFIG',
              ),
            ),
          );
        }
        expect(requests, 0);
      },
    );

    for (final field in domesticCredentials[provider]!.keys) {
      test(
        '$provider rejects reflected $field instead of persisting credentials as translation',
        () async {
          var requests = 0;
          final secret = domesticCredentials[provider]![field]!;
          final service = TranslationService(
            client: MockClient((request) async {
              requests++;
              return translated(
                provider,
                requests == 1 ? 'Echo: $secret' : 'Translated',
              );
            }),
            minInterval: Duration.zero,
          );
          addTearDown(service.dispose);
          service.setProviderConfiguration(
            order: [provider, 'Azure'],
            fallback: true,
            credentials: {
              provider: domesticCredentials[provider]!,
              'Azure': {'apiKey': 'azure_fixture_key'},
            },
            revision: 1,
          );
          await expectLater(
            service.translate('文案', 'en', token: CancelToken()),
            throwsA(
              isA<TranslationFailure>()
                  .having((e) => e.code, 'code', 'PROVIDER_RESPONSE')
                  .having(
                    (e) => e.message,
                    'safe message',
                    isNot(contains(secret)),
                  ),
            ),
          );
          final retry = await service.translate(
            '文案',
            'en',
            token: CancelToken(),
          );
          expect(retry.provider, provider);
          expect(requests, 2);
        },
      );
    }

    test(
      '$provider authorization failure cannot fall back to another account',
      () async {
        final seen = <String>[];
        final service = TranslationService(
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map;
            seen.add(body['provider'] as String);
            return http.Response(
              jsonEncode({
                'provider': provider,
                'code': 'PROVIDER_AUTH',
                'quota': true,
                'unsupported': true,
                'message': domesticCredentials[provider]!.values.join(),
              }),
              401,
            );
          }),
          minInterval: Duration.zero,
        );
        addTearDown(service.dispose);
        service.setProviderConfiguration(
          order: [provider, 'Azure'],
          fallback: true,
          credentials: {
            provider: domesticCredentials[provider]!,
            'Azure': {'apiKey': 'azure_fixture_key'},
          },
          revision: 1,
        );
        await expectLater(
          service.translate('文案', 'en', token: CancelToken()),
          throwsA(
            isA<TranslationFailure>()
                .having((e) => e.code, 'code', 'PROVIDER_AUTH')
                .having((e) => e.fatal, 'fatal', true)
                .having(
                  (e) => e.message,
                  'no secret echo',
                  isNot(contains('fixture')),
                ),
          ),
        );
        expect(seen, [provider]);
      },
    );

    test(
      '$provider persistence is explicit and machine results remain reusable',
      () async {
        SharedPreferences.setMockInitialValues({});
        var requests = 0;
        final controller = AppController(
          translator: TranslationService(
            client: MockClient((request) async {
              if (request.url.path == '/api/translation/validate') {
                return http.Response(
                  jsonEncode({
                    'provider': provider,
                    'status': 'valid',
                    'method': 'translation',
                    'billableCharacters': 1,
                  }),
                  200,
                );
              }
              requests++;
              return translated(provider, 'Login');
            }),
            minInterval: Duration.zero,
          ),
        );
        await controller.initialize();
        final project = controller.createProject('多字段凭据');
        controller.setLocales(['en']);
        controller.addBlocks([DocumentBlock('登录')]);
        await controller.saveProviderCredentials(
          provider,
          domesticCredentials[provider]!,
        );
        await controller.saveProviderOrder([provider]);
        await controller.startTranslation();
        controller.addBlocks([DocumentBlock('登录')]);
        await controller.startTranslation();
        expect(requests, 1);
        expect(controller.reused, 1);
        expect(project.entries.last.value('en').provider, provider);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(AppController.credentialStorageKey), isNull);
        for (final value in domesticCredentials[provider]!.values) {
          expect(jsonEncode(project.toJson()), isNot(contains(value)));
          expect(
            jsonEncode(controller.previewPackages()),
            isNot(contains(value)),
          );
          expect(
            prefs.getString(AppController.storageKey),
            isNot(contains(value)),
          );
        }
        await controller.saveProviderCredentials(
          provider,
          domesticCredentials[provider]!,
          remember: true,
        );
        final restored = AppController();
        await restored.initialize();
        expect(
          providerCredentialsReady(provider, restored.credentialsFor(provider)),
          isTrue,
        );
        expect(restored.credentialsSaved(provider), isTrue);
        if (provider == 'Tencent') {
          expect(restored.credentialsFor(provider)['region'], 'ap-guangzhou');
        }
        await restored.clearProviderCredentials(provider);
        expect(prefs.getString(AppController.credentialStorageKey), isNull);
        restored.dispose();
        await controller.flush();
        controller.dispose();
      },
    );
  }

  test(
    'model metadata cannot reflect any sensitive credential field',
    () async {
      final service = TranslationService(
        client: MockClient(
          (request) async => translated(
            'Alibaba',
            'Normal',
            model: domesticCredentials['Alibaba']!['accessKeySecret']!,
          ),
        ),
        minInterval: Duration.zero,
      );
      addTearDown(service.dispose);
      service.setProviderConfiguration(
        order: ['Alibaba'],
        fallback: false,
        credentials: {'Alibaba': domesticCredentials['Alibaba']!},
        revision: 1,
      );
      await expectLater(
        service.translate('文案', 'en', token: CancelToken()),
        throwsA(
          isA<TranslationFailure>().having(
            (e) => e.code,
            'code',
            'PROVIDER_RESPONSE',
          ),
        ),
      );
    },
  );
}
