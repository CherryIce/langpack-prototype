import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:langpack/ui/app.dart';
import 'package:langpack/ui/ios_modals.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ModalTranslator extends TranslationService {
  int validationCalls = 0;
  int translationCalls = 0;

  @override
  Future<CredentialValidation> validateCredentials(
    String provider,
    Map<String, String> credentials, {
    String apiBaseUrl = '',
    CancelToken? token,
  }) async {
    validationCalls++;
    return CredentialValidation(
      provider: provider,
      status: 'valid',
      method: 'metadata',
      billableCharacters: 0,
      message: 'Fixture authorization check.',
    );
  }

  @override
  Future<TranslationResult> translate(
    String source,
    String locale, {
    required CancelToken token,
    String sourceLocale = 'zh-Hans',
    String email = '',
    String apiBaseUrl = '',
    bool bypassCache = false,
    void Function(String)? onStatus,
  }) async {
    token.throwIfCancelled();
    translationCalls++;
    return TranslationResult(text: 'Fresh translation', provider: 'MyMemory');
  }
}

Future<AppController> _controller(_ModalTranslator translator) async {
  SharedPreferences.setMockInitialValues({});
  final controller = AppController(translator: translator);
  await controller.initialize();
  return controller;
}

Future<void> _mount(
  WidgetTester tester,
  AppController controller, {
  double width = 390,
  double height = 844,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(controller.dispose);
  await tester.pumpWidget(LangPackApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Finder _formAction(String label) => find.descendant(
  of: find.byType(IosFormSheet),
  matching: find.widgetWithText(CupertinoButton, label),
);

Future<void> _finish(WidgetTester tester, AppController controller) async {
  await controller.flush();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'phone project and multiline source forms retain validation and keyboard access',
    (tester) async {
      final controller = await _controller(_ModalTranslator());
      await _mount(tester, controller, width: 320, height: 900);
      await _tap(tester, find.text('新建项目'));
      expect(find.byType(IosFormSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await _tap(tester, _formAction('创建项目'));
      expect(find.text('请填写项目名称'), findsOneWidget);
      expect(controller.projects, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, '取消的项目');
      await _tap(tester, _formAction('取消'));
      expect(controller.projects, isEmpty);

      await _tap(tester, find.text('新建项目'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '英文项目');
      final description = find
          .descendant(
            of: find.byType(IosFormSheet),
            matching: find.byType(TextField),
          )
          .last;
      await tester.ensureVisible(description);
      await tester.enterText(description, '第一行说明\n第二行说明');
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('new-project-source-locale')),
          matching: find.text('英文'),
        ),
      );
      final create = _formAction('创建项目');
      expect(tester.getSize(create).height, greaterThanOrEqualTo(44));
      expect(tester.getBottomLeft(create).dy, lessThanOrEqualTo(580));
      await _tap(tester, create);
      expect(controller.currentProject!.sourceLocale, 'en');
      expect(controller.settings.interfaceLocale, 'zh');
      expect(controller.currentProject!.description, '第一行说明\n第二行说明');

      controller.addBlocks([DocumentBlock('Good morning')]);
      final entry = controller.currentProject!.entries.single;
      controller.editTranslation(entry, 'zh-Hans', '早上好');
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('文案操作'));
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      await _tap(tester, find.text('编辑原文'));
      expect(find.byType(IosFormSheet), findsOneWidget);
      final source = find.descendant(
        of: find.byType(IosFormSheet),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(source);
      await tester.enterText(source, '   ');
      await _tap(tester, _formAction('保存'));
      expect(find.text('请输入内容'), findsOneWidget);
      expect(entry.source, 'Good morning');
      expect(entry.value('zh-Hans').text, '早上好');
      await tester.enterText(
        source,
        'Good morning\nWelcome back\nHello, {name}',
      );
      await _tap(tester, _formAction('保存'));
      expect(entry.source, 'Good morning\nWelcome back\nHello, {name}');
      expect(entry.translations, isEmpty);
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    },
  );

  testWidgets(
    'phone deletion is destructive and requires explicit confirmation',
    (tester) async {
      final controller = await _controller(_ModalTranslator());
      final project = controller.createProject('删除测试');
      await _mount(tester, controller);

      Future<void> openDelete() async {
        await _tap(tester, find.byTooltip('项目操作'));
        final menuDelete = find.widgetWithText(
          CupertinoActionSheetAction,
          '删除项目',
        );
        expect(
          tester
              .widget<CupertinoActionSheetAction>(menuDelete)
              .isDestructiveAction,
          isTrue,
        );
        await _tap(tester, menuDelete);
        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          tester
              .widget<CupertinoDialogAction>(
                find.widgetWithText(CupertinoDialogAction, '删除项目'),
              )
              .isDestructiveAction,
          isTrue,
        );
      }

      await openDelete();
      await _tap(tester, find.widgetWithText(CupertinoDialogAction, '取消'));
      expect(controller.projects.map((p) => p.id), contains(project.id));
      await openDelete();
      await _tap(tester, find.widgetWithText(CupertinoDialogAction, '删除项目'));
      expect(controller.projects, isEmpty);
      expect(controller.currentProject, isNull);
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    },
  );

  testWidgets(
    'phone credential form cancels without saving and retains failed input',
    (tester) async {
      final translator = _ModalTranslator();
      final controller = await _controller(translator);
      await _mount(tester, controller, width: 320, height: 900);
      await _tap(tester, find.text('设置'));
      await _tap(tester, find.byKey(const ValueKey('provider-details-Azure')));
      await _tap(tester, find.text('配置 Azure'));
      final field = find.byKey(const ValueKey('credential-Azure-apiKey'));
      expect(find.byType(IosFormSheet), findsOneWidget);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, 'cancelled_fixture_key');
      await _tap(tester, _formAction('取消'));
      expect(controller.credentialsFor('Azure'), isEmpty);
      expect(translator.validationCalls, 0);

      await _tap(tester, find.text('配置 Azure'));
      await tester.enterText(field, '   ');
      await _tap(tester, _formAction('保存'));
      expect(find.byType(IosFormSheet), findsOneWidget);
      expect(find.text('请完整填写该平台的所有必填凭据。'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '   ');
      expect(controller.credentialsFor('Azure'), isEmpty);
      expect(translator.validationCalls, 0);

      await tester.enterText(field, 'saved_fixture_key');
      await _tap(tester, _formAction('保存'));
      expect(find.byType(IosFormSheet), findsNothing);
      expect(controller.credentialsFor('Azure')['apiKey'], 'saved_fixture_key');
      expect(controller.credentialsSaved('Azure'), isFalse);
      expect(translator.validationCalls, 1);
      expect(find.text('saved_fixture_key'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppController.credentialStorageKey,
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    },
  );

  testWidgets('phone protected retranslation keeps content when cancelled', (
    tester,
  ) async {
    final translator = _ModalTranslator();
    final controller = await _controller(translator);
    controller.createProject('人工译文');
    controller.setLocales(['en']);
    controller.addBlocks([DocumentBlock('登录')]);
    final entry = controller.currentProject!.entries.single;
    controller.editTranslation(entry, 'en', 'Manual translation');
    controller.reviewTranslation(entry, 'en', true);
    await _mount(tester, controller);
    await _tap(tester, find.text('人工译文'));
    await _tap(tester, find.text('校对'));
    await _tap(tester, find.text('重新翻译'));
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await _tap(tester, find.widgetWithText(CupertinoDialogAction, '取消'));
    expect(translator.translationCalls, 0);
    expect(entry.value('en').text, 'Manual translation');
    await _tap(tester, find.text('重新翻译'));
    await _tap(tester, find.widgetWithText(CupertinoDialogAction, '重新翻译并替换'));
    expect(translator.translationCalls, 1);
    expect(entry.value('en').text, 'Fresh translation');
    expect(tester.takeException(), isNull);
    await _finish(tester, controller);
  });

  testWidgets('desktop keeps Material forms, menus and confirmation dialogs', (
    tester,
  ) async {
    final controller = await _controller(_ModalTranslator());
    controller.createProject('桌面项目');
    await _mount(tester, controller, width: 1200, height: 1000);
    await _tap(tester, find.text('新建项目'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(IosFormSheet), findsNothing);
    expect(find.widgetWithText(FilledButton, '创建项目'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(controller.projects.length, 1);

    await _tap(tester, find.byTooltip('项目操作'));
    expect(find.byType(CupertinoActionSheet), findsNothing);
    await _tap(tester, find.text('删除项目'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    await _tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(controller.projects.length, 1);

    await _tap(tester, find.text('偏好设置'));
    await _tap(tester, find.byKey(const ValueKey('provider-details-DeepL')));
    await _tap(tester, find.text('配置 DeepL'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(IosFormSheet), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(CheckboxListTile, '在本机保存凭据'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(controller.credentialsFor('DeepL'), isEmpty);
    expect(tester.takeException(), isNull);
    await _finish(tester, controller);
  });
}
