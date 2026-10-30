import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const validationCredentials = <String, Map<String, String>>{
  'MyMemory': {},
  'ZTAITrans': {'developerToken': 'developer_validation_fixture'},
  'DeepL': {'apiKey': 'deepl_validation_fixture', 'plan': 'free'},
  'Azure': {'apiKey': 'azure_validation_fixture', 'region': 'eastasia'},
  'Google': {'apiKey': 'google_validation_fixture'},
  'Baidu': {
    'appId': 'baidu_validation_id',
    'secretKey': 'baidu_validation_secret',
  },
  'Tencent': {
    'secretId': 'tencent_validation_id',
    'secretKey': 'tencent_validation_secret',
    'region': 'ap-guangzhou',
  },
  'Alibaba': {
    'accessKeyId': 'alibaba_validation_id',
    'accessKeySecret': 'alibaba_validation_secret',
  },
};

class ValidationRequest {
  ValidationRequest(this.provider, this.credentials, this.base, this.token);
  final String provider, base;
  final Map<String, String> credentials;
  final CancelToken? token;
  final completion = Completer<CredentialValidation>();
  void finish(String status, {String method = 'translation'}) =>
      completion.complete(
        CredentialValidation(
          provider: provider,
          status: status,
          method: method,
          billableCharacters: method == 'translation' ? 1 : 0,
          message: 'Fixture verification result.',
        ),
      );
}

class ControlledCredentialValidator extends TranslationService {
  final requests = <ValidationRequest>[];
  @override
  Future<CredentialValidation> validateCredentials(
    String provider,
    Map<String, String> credentials, {
    String apiBaseUrl = '',
    CancelToken? token,
  }) {
    final request = ValidationRequest(
      provider,
      {...credentials},
      apiBaseUrl,
      token,
    );
    requests.add(request);
    // Deliberately ignore cancellation to verify that late server replies cannot overwrite UI state.
    return request.completion.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in validationCredentials.entries) {
    test(
      '${entry.key} validation makes one proxy request without content, fallback or retry',
      () async {
        var calls = 0;
        final method = entry.key == 'MyMemory'
            ? 'anonymous'
            : ['DeepL', 'Google'].contains(entry.key)
            ? 'metadata'
            : 'translation';
        final service = TranslationService(
          client: MockClient((request) async {
            calls++;
            expect(request.url.path, '/api/translation/validate');
            expect(request.url.query, isEmpty);
            expect(request.method, 'POST');
            final body = jsonDecode(request.body) as Map;
            expect(body.keys.toSet(), {'provider', 'credentials'});
            expect(body['provider'], entry.key);
            expect(body['credentials'], entry.value);
            return http.Response(
              jsonEncode({
                'provider': entry.key,
                'status': 'valid',
                'method': method,
                'billableCharacters': method == 'translation' ? 1 : 0,
                'message':
                    'must_ignore_sensitive_echo_${entry.value.values.join()}',
              }),
              200,
            );
          }),
        );
        addTearDown(service.dispose);
        service.setProviderConfiguration(
          order: ['MyMemory', 'DeepL', 'Azure'],
          fallback: true,
          credentials: validationCredentials,
          revision: 1,
        );
        final result = await service.validateCredentials(
          entry.key,
          entry.value,
        );
        expect(calls, 1);
        expect(result.status, 'valid');
        expect(result.method, method);
        expect(result.billableCharacters, method == 'translation' ? 1 : 0);
        expect(result.message, isNot(contains('must_ignore_sensitive_echo')));
        if (method == 'metadata') expect(result.message, contains('未验证所有目标'));
        if (method == 'anonymous') expect(result.message, contains('未检查翻译服务'));
      },
    );
  }

  for (final status in ['invalid', 'limited', 'unavailable']) {
    test(
      '$status validation remains distinct and does not trigger another platform',
      () async {
        var calls = 0;
        final service = TranslationService(
          client: MockClient((request) async {
            calls++;
            return http.Response(
              jsonEncode({
                'provider': 'DeepL',
                'status': status,
                'method': 'metadata',
                'billableCharacters': 0,
                'message': 'key=secret_fixture',
              }),
              200,
            );
          }),
        );
        addTearDown(service.dispose);
        final result = await service.validateCredentials('DeepL', {
          'apiKey': 'secret_fixture',
          'plan': 'free',
        });
        expect(result.status, status);
        expect(result.message, isNot(contains('secret_fixture')));
        expect(calls, 1);
      },
    );
  }

  test(
    'private MyMemory trial success does not imply private-memory authorization',
    () async {
      final service = TranslationService(
        client: MockClient(
          (request) async => http.Response(
            '{"provider":"MyMemory","status":"valid","method":"translation","billableCharacters":1}',
            200,
          ),
        ),
      );
      addTearDown(service.dispose);
      final result = await service.validateCredentials('MyMemory', {
        'apiKey': 'private_validation_fixture',
      });
      expect(result.message, contains('不能据此确认私有词库权限'));
      expect(result.label, '单字试译通过');
    },
  );

  for (final patch in <Map<String, dynamic>>[
    {'provider': 'Google'},
    {'status': 'success'},
    {'method': 'developer'},
    {'billableCharacters': 2},
    {'method': 'metadata', 'billableCharacters': 1},
    {'method': 'anonymous', 'billableCharacters': 0},
    {'method': 'translation', 'billableCharacters': 1},
  ]) {
    test(
      'malformed verification metadata cannot become valid: $patch',
      () async {
        final service = TranslationService(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'provider': 'DeepL',
                'status': 'valid',
                'method': 'metadata',
                'billableCharacters': 0,
                ...patch,
              }),
              200,
            ),
          ),
        );
        addTearDown(service.dispose);
        final result = await service.validateCredentials('DeepL', {
          'apiKey': 'test_validation_fixture',
        });
        expect(result.status, 'unavailable');
        expect(result.billableCharacters, isNull);
      },
    );
  }

  test(
    'network errors are unavailable rather than invalid and are never retried',
    () async {
      var calls = 0;
      final service = TranslationService(
        client: MockClient((request) async {
          calls++;
          throw StateError('do_not_expose_validation_key');
        }),
      );
      addTearDown(service.dispose);
      final result = await service.validateCredentials('Google', {
        'apiKey': 'do_not_expose_validation_key',
      });
      expect(calls, 1);
      expect(result.status, 'unavailable');
      expect(result.message, isNot(contains('do_not_expose_validation_key')));
    },
  );

  group('saved credential validation', () {
    late ControlledCredentialValidator validator;
    late AppController controller;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      validator = ControlledCredentialValidator();
      controller = AppController(translator: validator);
      await controller.initialize();
    });
    tearDown(() async {
      await controller.flush();
      controller.dispose();
    });

    test(
      'saving completes before verification and invalid credentials remain explicitly saved',
      () async {
        await controller.saveProviderCredentials(
          'Baidu',
          validationCredentials['Baidu']!,
          remember: true,
        );
        expect(controller.credentialsSaved('Baidu'), isTrue);
        expect(controller.credentialValidationFor('Baidu').status, 'checking');
        expect(validator.requests, hasLength(1));
        final pending = controller.validateProviderCredentials('Baidu');
        validator.requests.single.finish('invalid');
        await pending;
        expect(controller.credentialValidationFor('Baidu').status, 'invalid');
        expect(
          controller.credentialsFor('Baidu'),
          validationCredentials['Baidu'],
        );
        expect(controller.error, isNull);
        expect(
          (await SharedPreferences.getInstance()).getString(
            AppController.credentialStorageKey,
          ),
          isNotNull,
        );
      },
    );

    test(
      'remember-only changes reuse one pending request and the current-session result',
      () async {
        await controller.saveProviderCredentials(
          'Tencent',
          validationCredentials['Tencent']!,
        );
        await controller.saveProviderCredentials(
          'Tencent',
          validationCredentials['Tencent']!,
          remember: true,
        );
        expect(validator.requests, hasLength(1));
        final first = controller.validateProviderCredentials(
          'Tencent',
          force: true,
        );
        validator.requests.single.finish('valid');
        await first;
        await controller.saveProviderCredentials(
          'Tencent',
          validationCredentials['Tencent']!,
          remember: false,
        );
        expect(validator.requests, hasLength(1));
        final repeated = controller.validateProviderCredentials(
          'Tencent',
          force: true,
        );
        expect(validator.requests, hasLength(2));
        validator.requests.last.finish('limited');
        await repeated;
        expect(controller.credentialValidationFor('Tencent').status, 'limited');
      },
    );

    test(
      'changed credentials and deletion reject delayed replies even if the server ignores abort',
      () async {
        await controller.saveProviderCredentials('Azure', {
          'apiKey': 'first_validation_key',
        });
        final old = controller.validateProviderCredentials('Azure');
        await controller.saveProviderCredentials('Azure', {
          'apiKey': 'second_validation_key',
        });
        expect(validator.requests.first.token!.cancelled, isTrue);
        validator.requests.first.finish('valid');
        await old;
        expect(controller.credentialValidationFor('Azure').status, 'checking');
        final current = controller.validateProviderCredentials('Azure');
        await controller.clearProviderCredentials('Azure');
        validator.requests.last.finish('valid');
        await current;
        expect(controller.credentialsFor('Azure'), isEmpty);
        expect(
          controller.credentialValidationFor('Azure').status,
          'unverified',
        );
      },
    );

    test(
      'validations are independent per platform and metadata is never persisted',
      () async {
        await controller.saveProviderCredentials(
          'DeepL',
          validationCredentials['DeepL']!,
          remember: true,
        );
        final deepL = controller.validateProviderCredentials('DeepL');
        await controller.saveProviderCredentials(
          'Google',
          validationCredentials['Google']!,
        );
        final google = controller.validateProviderCredentials('Google');
        validator.requests.first.finish('valid', method: 'metadata');
        await deepL;
        expect(controller.credentialValidationFor('DeepL').status, 'valid');
        expect(controller.credentialValidationFor('Google').status, 'checking');
        validator.requests.last.finish('unavailable', method: 'metadata');
        await google;
        expect(controller.error, isNull);
        expect(controller.credentialsFor('Google'), isNotEmpty);
        await controller.flush();
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(AppController.storageKey),
          isNot(contains('Fixture verification result')),
        );
        expect(
          prefs.getString(AppController.credentialStorageKey),
          isNot(contains('Fixture verification result')),
        );
        final restoredValidator = ControlledCredentialValidator();
        final restored = AppController(translator: restoredValidator);
        await restored.initialize();
        expect(restored.credentialValidationFor('DeepL').status, 'unverified');
        expect(restoredValidator.requests, isEmpty);
        restored.dispose();
      },
    );

    test(
      'changing email or proxy invalidates old account verification',
      () async {
        await controller.saveProviderCredentials('MyMemory', {
          'apiKey': 'private_validation_key',
        });
        final first = controller.validateProviderCredentials('MyMemory');
        await controller.saveSettings(
          email: 'owner@example.com',
          apiBaseUrl: '',
          includeSource: true,
        );
        expect(validator.requests.first.token!.cancelled, isTrue);
        validator.requests.first.finish('valid');
        await first;
        expect(
          controller.credentialValidationFor('MyMemory').status,
          'unverified',
        );
        final fresh = controller.validateProviderCredentials('MyMemory');
        expect(
          validator.requests.last.credentials['email'],
          'owner@example.com',
        );
        await controller.saveSettings(
          email: 'owner@example.com',
          apiBaseUrl: 'https://other.example',
          includeSource: true,
        );
        validator.requests.last.finish('valid');
        await fresh;
        expect(
          controller.credentialValidationFor('MyMemory').status,
          'unverified',
        );
      },
    );
  });
}
