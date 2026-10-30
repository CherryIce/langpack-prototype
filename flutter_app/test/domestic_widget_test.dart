import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:langpack/ui/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DomesticValidationFixture extends TranslationService {
  @override
  Future<CredentialValidation> validateCredentials(
    String provider,
    Map<String, String> credentials, {
    String apiBaseUrl = '',
    CancelToken? token,
  }) async => CredentialValidation(
    provider: provider,
    status: 'valid',
    method: 'translation',
    billableCharacters: 1,
    message: 'Mock single-character probe.',
  );
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in const <String, List<String>>{
    'Baidu': ['appId', 'secretKey'],
    'Tencent': ['secretId', 'secretKey'],
    'Alibaba': ['accessKeyId', 'accessKeySecret'],
  }.entries) {
    testWidgets(
      '${entry.key} configures masked multi-field session credentials at 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final controller = AppController(
          translator: _DomesticValidationFixture(),
        );
        await controller.initialize();
        addTearDown(controller.dispose);
        await tester.pumpWidget(LangPackApp(controller: controller));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('设置'));
        await tapVisible(tester, find.text('配置 ${entry.key}'));
        for (final field in entry.value) {
          final finder = find.byKey(ValueKey('credential-${entry.key}-$field'));
          expect(tester.widget<TextField>(finder).obscureText, isTrue);
          await tester.enterText(
            finder,
            '${entry.key}_${field}_widget_fixture',
          );
        }
        if (entry.key == 'Tencent') {
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('credential-Tencent-region')),
                )
                .controller!
                .text,
            'ap-guangzhou',
          );
        }
        if (entry.key == 'Alibaba') {
          expect(find.textContaining('固定为 cn-hangzhou'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('credential-Alibaba-region')),
            findsNothing,
          );
        }
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, '在本机保存凭据'),
              )
              .value,
          isFalse,
        );
        await tapVisible(tester, find.widgetWithText(FilledButton, '保存配置'));
        for (final field in entry.value) {
          expect(
            controller.credentialsFor(entry.key)[field],
            '${entry.key}_${field}_widget_fixture',
          );
          expect(
            find.text('${entry.key}_${field}_widget_fixture'),
            findsNothing,
          );
        }
        expect(
          (await SharedPreferences.getInstance()).getString(
            AppController.credentialStorageKey,
          ),
          isNull,
        );
        await tapVisible(
          tester,
          find.byKey(ValueKey('provider-enable-${entry.key}')),
        );
        expect(controller.settings.providerOrder, ['MyMemory', entry.key]);
        await controller.flush();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
