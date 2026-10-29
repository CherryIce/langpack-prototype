import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/export_service.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:langpack/ui/app.dart';

class _FixtureTranslation extends TranslationService {
  @override
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
    return TranslationResult(
      text: source == '登录' ? 'Sign in' : 'Hello, {name}',
      provider: 'MyMemory',
    );
  }
}

class _CapturingExport extends ExportService {
  final saved = <String, Uint8List>{};
  @override
  Future<bool> saveFile(String name, Uint8List bytes) async {
    saved[name] = bytes;
    return true;
  }
}

class _DelayedImportController extends AppController {
  final pending = Completer<List<DocumentBlock>>();
  @override
  Future<List<DocumentBlock>> pickDocument() => pending.future;
}

class _DelayedBackupController extends AppController {
  final pending = Completer<bool>();
  @override
  Future<bool> checkBackup() => pending.future;
}

Future<AppController> _controller({_CapturingExport? exporter}) async {
  SharedPreferences.setMockInitialValues({});
  final controller = AppController(
    translator: _FixtureTranslation(),
    exporter: exporter,
  );
  await controller.initialize();
  return controller;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'restoring the built-in proxy ignores a late custom server status',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final controller = _DelayedBackupController();
      await controller.initialize();
      await controller.saveSettings(
        email: '',
        apiBaseUrl: 'https://custom.example',
        includeSource: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('偏好设置'));
      await _tap(tester, find.text('检测服务'));
      await _tap(tester, find.text('恢复内置在线服务'));
      controller.pending.complete(false);
      await tester.pumpAndSettle();
      expect(controller.settings.apiBaseUrl, isEmpty);
      expect(find.text('已选用内置在线服务，无需配置密钥'), findsOneWidget);
      expect(find.text('当前服务器尚未启用备用翻译'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native settings show built-in proxy and can restore it from a custom server',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('偏好设置'));
      expect(find.text('已选用内置在线服务，无需配置密钥'), findsOneWidget);
      expect(find.text(defaultBackupServiceOrigin), findsOneWidget);
      expect(find.text('自定义服务器（可选）'), findsOneWidget);
      expect(find.text('恢复内置在线服务'), findsNothing);
      await controller.saveSettings(
        email: '',
        apiBaseUrl: 'https://custom.example',
        includeSource: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('https://custom.example'), findsOneWidget);
      await _tap(tester, find.text('恢复内置在线服务'));
      expect(controller.settings.apiBaseUrl, isEmpty);
      expect(find.text(defaultBackupServiceOrigin), findsOneWidget);
      final stored = (await SharedPreferences.getInstance()).getString(
        AppController.storageKey,
      )!;
      expect(stored, contains('"apiBaseUrl":""'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mobile starts with an empty workspace and can create a project',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('你的第一个多语言项目'), findsOneWidget);
      expect(controller.projects, isEmpty);
      await _tap(tester, find.text('新建项目'));
      await tester.enterText(find.byType(TextFormField).first, '移动端文案');
      await _tap(tester, find.widgetWithText(FilledButton, '创建项目'));
      expect(controller.currentProject?.name, '移动端文案');
      expect(controller.currentProject?.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('desktop text to translation, proofreading and JSON ZIP export', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final exporter = _CapturingExport();
    final controller = await _controller(exporter: exporter);
    controller.createProject('产品文案');
    addTearDown(controller.dispose);
    await tester.pumpWidget(LangPackApp(controller: controller));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('输入文案'));
    await tester.enterText(find.byType(TextField).first, '登录\n你好，{name}');
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 段'), findsOneWidget);
    await _tap(tester, find.text('下一步：选择语言'));
    expect(controller.currentProject!.entries.length, 2);
    expect(find.text('为你的内容，选择目的地'), findsOneWidget);
    await _tap(tester, find.text('开始翻译'));
    expect(controller.running, isFalse);
    expect(controller.currentProject!.translatedCount, 4);
    await _tap(tester, find.text('进入翻译校对'));
    expect(find.text('好译文，值得再看一眼'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    final translation = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '英语译文',
    );
    await tester.enterText(translation, 'Log in');
    await tester.pumpAndSettle();
    await tester.enterText(translation, 'Log in now');
    await tester.pumpAndSettle();
    expect(
      controller.currentProject!.entries.first.value('en').text,
      'Log in now',
    );
    expect(tester.testTextInput.isVisible, isTrue);
    await _tap(tester, find.text('已人工校对确认'));
    expect(
      controller.currentProject!.entries.first.value('en').reviewed,
      isTrue,
    );
    await _tap(tester, find.text('下一步：导出语言包'));
    expect(find.text('zh-Hans.json'), findsWidgets);
    await _tap(tester, find.text('保存全部语言包 .zip'));
    expect(exporter.saved.keys.any((name) => name.endsWith('.zip')), isTrue);
    await _tap(tester, find.text('保存当前 JSON'));
    expect(exporter.saved.keys.any((name) => name.endsWith('.json')), isTrue);
    expect(controller.currentProject!.exports.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'mobile document preview, language selection and draft export have no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      controller.createProject('小屏幕回归');
      controller.addBlocks([
        DocumentBlock('登录'),
        DocumentBlock('欢迎使用我们的多语言翻译产品，{name}。'),
      ]);
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('导入文档'));
      expect(find.text('选择需要翻译的文档'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byTooltip('返回'));
      await _tap(tester, find.text('翻译未完成项'));
      expect(find.text('目标语言'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('返回项目'));
      await _tap(tester, find.text('导出语言包'));
      expect(find.text('把语言，带到你的产品中'), findsOneWidget);
      expect(find.textContaining('请先修复'), findsOneWidget);
      await _tap(tester, find.text('导出草稿'));
      expect(find.text('en.json'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'invalid text clears the old preview and disables the next step',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      controller.createProject('输入边界');
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('输入文案'));
      final field = find.byType(TextField).first;
      await tester.enterText(field, '登录');
      await tester.pumpAndSettle();
      expect(find.text('1 / 1 段'), findsOneWidget);
      await tester.enterText(field, List.filled(1001, '登录').join('\n'));
      await tester.pumpAndSettle();
      expect(find.text('0 / 0 段'), findsOneWidget);
      final next = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('下一步：选择语言'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(next.onPressed, isNull);
      expect(controller.currentProject!.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a late document result cannot enter another project input session',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final controller = _DelayedImportController();
      await controller.initialize();
      final first = controller.createProject('第一个项目');
      final second = controller.createProject('第二个项目');
      controller.openProject(first.id);
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('导入文档'));
      await tester.ensureVisible(find.text('选择文件'));
      await tester.tap(find.text('选择文件'));
      await tester.pump();
      await _tap(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('我的项目'),
        ),
      );
      await _tap(tester, find.text('第二个项目'));
      await _tap(tester, find.text('导入文档'));
      controller.pending.complete([DocumentBlock('旧项目文档内容')]);
      await tester.pumpAndSettle();
      expect(controller.currentProject!.id, second.id);
      expect(find.text('旧项目文档内容'), findsNothing);
      expect(find.text('0 / 0 段'), findsOneWidget);
      expect(second.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'mobile project and source editing dialogs remain usable above a 320px keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(LangPackApp(controller: controller));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('新建项目'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.view.viewInsets.bottom, 320);
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(AlertDialog)),
        ).bottom,
        320,
      );
      await tester.enterText(find.byType(TextFormField).first, '键盘项目');
      final description = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .last;
      await tester.ensureVisible(description);
      await tester.enterText(description, '用小屏幕完成项目创建，说明输入框和创建按钮都应可用。');
      await _tap(tester, find.widgetWithText(FilledButton, '创建项目'));
      expect(controller.currentProject!.name, '键盘项目');
      controller.addBlocks([DocumentBlock('需要校对的中文原文。')]);
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('文案操作'));
      await _tap(tester, find.text('编辑原文'));
      expect(find.text('编辑中文原文'), findsOneWidget);
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(AlertDialog)),
        ).bottom,
        320,
      );
      final sourceField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(sourceField);
      await tester.enterText(sourceField, '已经在键盘上方完成编辑的新原文。');
      await _tap(tester, find.widgetWithText(FilledButton, '保存'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        controller.currentProject!.entries.single.source,
        '已经在键盘上方完成编辑的新原文。',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
