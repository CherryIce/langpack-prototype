import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The preference platform fake exercises native storage failure without device I/O.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _ThrowingRemoveStore extends InMemorySharedPreferencesStore {
  _ThrowingRemoveStore(super.data) : super.withData();
  @override
  Future<bool> remove(String key) async {
    if (key.endsWith(AppController.credentialStorageKey)) {
      throw StateError('native failure with fixture_private_value');
    }
    return super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controller = AppController();
    await controller.initialize();
  });
  tearDown(() async {
    await controller.flush();
    controller.dispose();
  });

  test(
    'failed credential removal reports that an older local copy may remain',
    () async {
      await controller.saveProviderCredentials('Azure', {
        'apiKey': 'old_saved_fixture',
      }, remember: true);
      final store = _ThrowingRemoveStore(
        await SharedPreferencesStorePlatform.instance.getAll(),
      );
      SharedPreferencesStorePlatform.instance = store;
      await expectLater(
        controller.saveProviderCredentials('Azure', {
          'apiKey': 'new_session_fixture',
        }, remember: false),
        throwsA(isA<FormatException>()),
      );
      expect(controller.error, contains('旧的本机副本可能仍保留'));
      expect(controller.error, isNot(contains('fixture_private_value')));
      expect(
        (await store.getAll()).values.any(
          (value) => value.toString().contains('old_saved_fixture'),
        ),
        isTrue,
      );
    },
  );

  test(
    'MyMemory optional private key can be cleared back to anonymous mode',
    () async {
      await controller.saveProviderCredentials('MyMemory', {
        'apiKey': 'private-fixture',
      }, remember: true);
      expect(controller.credentialsSaved('MyMemory'), isTrue);
      await controller.saveProviderCredentials('MyMemory', {'apiKey': ''});
      expect(controller.credentialsFor('MyMemory'), isEmpty);
      expect(controller.credentialsSaved('MyMemory'), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppController.credentialStorageKey,
        ),
        isNull,
      );
    },
  );

  test(
    'platform selection persists while session credentials never enter project storage',
    () async {
      controller.createProject('BYOK');
      controller.addBlocks([DocumentBlock('登录')]);
      await controller.saveProviderCredentials('DeepL', {
        'apiKey': 'session_fixture_secret',
        'plan': 'free',
      });
      await controller.saveProviderOrder(['DeepL', 'MyMemory']);
      await controller.saveProviderOrder(
        controller.settings.providerOrder,
        fallback: false,
      );
      expect(controller.settings.providerOrder, ['DeepL', 'MyMemory']);
      await controller.saveSettings(
        email: '',
        apiBaseUrl: '',
        includeSource: true,
      );
      await controller.flush();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppController.storageKey),
        isNot(contains('session_fixture_secret')),
      );
      expect(prefs.getString(AppController.credentialStorageKey), isNull);
      final restored = AppController();
      await restored.initialize();
      expect(restored.settings.providerOrder, ['DeepL', 'MyMemory']);
      expect(restored.settings.providerFallback, isFalse);
      expect(restored.credentialsFor('DeepL'), isEmpty);
      restored.dispose();
    },
  );

  test(
    'explicit local save restores only opted-in providers and clear removes it',
    () async {
      await controller.saveProviderCredentials('Azure', {
        'apiKey': 'persist_fixture_secret',
        'region': 'eastasia',
      }, remember: true);
      await controller.saveProviderCredentials('Google', {
        'apiKey': 'temporary_google_fixture',
      });
      await controller.flush();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(AppController.credentialStorageKey)!;
      expect(saved, contains('persist_fixture_secret'));
      expect(saved, isNot(contains('temporary_google_fixture')));
      expect(
        prefs.getString(AppController.storageKey),
        isNot(contains('persist_fixture_secret')),
      );
      final restored = AppController();
      await restored.initialize();
      expect(restored.credentialsFor('Azure')['region'], 'eastasia');
      expect(restored.credentialsSaved('Azure'), isTrue);
      expect(restored.credentialsFor('Google'), isEmpty);
      await restored.clearProviderCredentials('Azure');
      expect(prefs.getString(AppController.credentialStorageKey), isNull);
      expect(restored.credentialsFor('Azure'), isEmpty);
      restored.dispose();
    },
  );

  test('disabling remember removes an older local credential copy', () async {
    await controller.saveProviderCredentials('DeepL', {
      'apiKey': 'old_fixture_secret',
    }, remember: true);
    await controller.saveProviderCredentials('DeepL', {
      'apiKey': 'new_session_fixture',
    }, remember: false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppController.credentialStorageKey), isNull);
    expect(controller.credentialsFor('DeepL')['apiKey'], 'new_session_fixture');
  });

  test(
    'ZTAI supports exactly one authorization mode and filters unrelated credential fields',
    () async {
      await expectLater(
        controller.saveProviderCredentials('ZTAITrans', {
          'apiKey': 'key-fixture',
          'developerToken': 'token-fixture',
        }),
        throwsFormatException,
      );
      await controller.saveProviderCredentials('ZTAITrans', {
        'developerToken': 'developer-fixture',
        'tenantId': 'not-used',
        'unrelated': 'discarded',
      });
      expect(controller.credentialsFor('ZTAITrans'), {
        'developerToken': 'developer-fixture',
      });
      expect(
        () =>
            controller.credentialsFor('ZTAITrans')['apiKey'] = 'cannot mutate',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'application defaults use MyMemory alone with no anonymous proxy translation',
    () async {
      controller.dispose();
      final methods = <String>[];
      controller = AppController(
        translator: TranslationService(
          client: MockClient((request) async {
            methods.add(request.method);
            return http.Response('{"quotaFinished":true}', 200);
          }),
          minInterval: Duration.zero,
        ),
      );
      await controller.initialize();
      controller.createProject('默认路径');
      controller.setLocales(['en']);
      controller.addBlocks([DocumentBlock('登录')]);
      await controller.startTranslation();
      expect(methods, ['GET']);
      expect(controller.failed, 1);
    },
  );

  test(
    'new platform success and model are reused without retaining credentials in snapshots',
    () async {
      controller.dispose();
      var calls = 0;
      controller = AppController(
        translator: TranslationService(
          client: MockClient((request) async {
            calls++;
            final body = jsonDecode(request.body) as Map;
            expect(body['credentials'], {
              'apiKey': 'fixture_key',
              'plan': 'free',
            });
            return http.Response(
              '{"provider":"DeepL","text":"Login","model":"fixture-model"}',
              200,
            );
          }),
          minInterval: Duration.zero,
        ),
      );
      await controller.initialize();
      final project = controller.createProject('复用');
      controller.setLocales(['en']);
      controller.addBlocks([DocumentBlock('登录')]);
      await controller.saveProviderCredentials('DeepL', {
        'apiKey': 'fixture_key',
      });
      await controller.saveProviderOrder(['DeepL']);
      await controller.startTranslation();
      controller.addBlocks([DocumentBlock('登录')]);
      await controller.startTranslation();
      expect(calls, 1);
      expect(controller.reused, 1);
      expect(project.entries.last.value('en').provider, 'DeepL');
      expect(project.entries.last.value('en').model, 'fixture-model');
      final serialized = jsonEncode(project.toJson());
      expect(serialized, isNot(contains('fixture_key')));
      expect(
        jsonEncode(controller.previewPackages()),
        isNot(contains('fixture_key')),
      );
    },
  );
}
