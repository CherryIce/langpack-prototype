import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:langpack/ui/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WidgetValidator extends TranslationService {
  final requests = <Completer<CredentialValidation>>[];
  @override
  Future<CredentialValidation> validateCredentials(
    String provider,
    Map<String, String> credentials, {
    String apiBaseUrl = '',
    CancelToken? token,
  }) {
    final pending = Completer<CredentialValidation>();
    requests.add(pending);
    return pending.future;
  }

  void finish(int index, String status) => requests[index].complete(
    CredentialValidation(
      provider: 'Azure',
      status: status,
      method: 'translation',
      billableCharacters: 1,
      message: status == 'invalid' ? '这些凭据未通过验证。' : '网络暂不可用，凭据仍已保存。',
    ),
  );
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'saving warns about the probe and reports verification separately without duplicate submits',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final validator = _WidgetValidator();
      final controller = AppController(translator: validator);
      await controller.initialize();
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('设置'));
      await tapVisible(tester, find.text('配置 Azure'));
      expect(find.textContaining('保存后自动验证'), findsOneWidget);
      expect(find.textContaining('可能产生 1 字符'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('credential-Azure-apiKey')),
        'widget_validation_fixture',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存配置'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        controller.credentialsFor('Azure')['apiKey'],
        'widget_validation_fixture',
      );
      expect(controller.credentialValidationFor('Azure').status, 'checking');
      expect(validator.requests.length, 1);
      final retry = find.byKey(const ValueKey('revalidate-Azure'));
      expect(tester.widget<TextButton>(retry).onPressed, isNull);
      validator.finish(0, 'invalid');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('validation-status-Azure')))
            .data,
        '上次验证：凭据或配置无效',
      );
      expect(controller.credentialsFor('Azure'), isNotEmpty);
      expect(find.text('widget_validation_fixture'), findsNothing);
      await tapVisible(tester, retry);
      expect(validator.requests.length, 2);
      expect(tester.widget<TextButton>(retry).onPressed, isNull);
      validator.finish(1, 'unavailable');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('validation-status-Azure')))
            .data,
        '上次验证：暂未验证成功',
      );
      expect(find.text('本次验证最多可能产生 1 字符用量'), findsOneWidget);
      expect(controller.credentialsFor('Azure'), isNotEmpty);
      expect(controller.error, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
