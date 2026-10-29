import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:langpack/controller.dart';
import 'package:langpack/models.dart';
import 'package:langpack/services/translation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControlledTranslator extends TranslationService {
  final requests = <Completer<TranslationResult>>[];
  final sources = <String>[];
  final locales = <String>[];
  @override
  Future<TranslationResult> translate(
    String source,
    String locale, {
    required CancelToken token,
    String email = '',
    String apiBaseUrl = '',
    bool bypassCache = false,
    void Function(String)? onStatus,
  }) {
    sources.add(source);
    locales.add(locale);
    final request = Completer<TranslationResult>();
    requests.add(request);
    return request.future;
  }

  void complete(int index, [String text = 'Translated']) => requests[index]
      .complete(TranslationResult(text: text, provider: 'MyMemory'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledTranslator translator;
  late AppController controller;
  late Project project;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    translator = ControlledTranslator();
    controller = AppController(translator: translator);
    await controller.initialize();
    project = controller.createProject('测试项目');
    controller.setLocales(['en']);
    controller.addBlocks([DocumentBlock('登录')]);
  });
  tearDown(() async {
    await controller.flush();
    controller.dispose();
  });

  test(
    'source edits invalidate translations and reject late network results',
    () async {
      final entry = project.entries.single;
      final task = controller.startTranslation();
      expect(controller.running, isTrue);
      controller.updateEntrySource(entry, '退出登录');
      translator.complete(0, 'Login');
      await task;
      expect(entry.source, '退出登录');
      expect(entry.translations['en']?.text ?? '', isEmpty);
      expect(controller.running, isFalse);
    },
  );

  test('in-flight result cannot overwrite a newer manual edit', () async {
    final entry = project.entries.single;
    final task = controller.startTranslation();
    controller.editTranslation(entry, 'en', 'Sign in');
    translator.complete(0, 'Login');
    await task;
    expect(entry.value('en').text, 'Sign in');
    expect(entry.value('en').edited, isTrue);
  });

  test(
    'pause followed by resume rejects previous generation results',
    () async {
      final first = controller.startTranslation();
      controller.pauseTranslation();
      expect(controller.paused, isTrue);
      final second = controller.startTranslation();
      expect(translator.requests.length, 2);
      translator.complete(0, 'Stale');
      await first;
      expect(controller.running, isTrue);
      expect(project.entries.single.value('en').text, isEmpty);
      translator.complete(1, 'Sign in');
      await second;
      expect(project.entries.single.value('en').text, 'Sign in');
      expect(project.jobs.map((job) => job.status), ['completed', 'paused']);
    },
  );

  test('batch protects manual and reviewed translations', () async {
    final entry = project.entries.single;
    controller.editTranslation(entry, 'en', 'Sign in');
    controller.reviewTranslation(entry, 'en', true);
    await controller.startTranslation();
    expect(translator.requests, isEmpty);
    expect(entry.value('en').reviewed, isTrue);
  });

  test('failed-only retry skips successful translation', () async {
    controller.addBlocks([DocumentBlock('注册')]);
    project.entries.first.value('en')
      ..text = 'Login'
      ..status = TranslationStatus.done;
    project.entries.last.value('en')
      ..status = TranslationStatus.failed
      ..error = 'Network';
    final task = controller.startTranslation(retryFailedOnly: true);
    expect(translator.sources, ['注册']);
    translator.complete(0, 'Register');
    await task;
    expect(project.entries.first.value('en').text, 'Login');
    expect(project.entries.last.value('en').text, 'Register');
  });

  test(
    'fatal backup failure stops queue and preserves prior successes',
    () async {
      controller.addBlocks([DocumentBlock('注册'), DocumentBlock('设置')]);
      final task = controller.startTranslation();
      translator.complete(0, 'Login');
      await Future<void>.delayed(Duration.zero);
      translator.requests[1].completeError(
        const TranslationFailure('BACKUP_AUTH', '授权失败', fatal: true),
      );
      await task;
      expect(translator.sources, ['登录', '注册']);
      expect(project.entries.first.value('en').text, 'Login');
      expect(controller.failed, 1);
      expect(project.jobs.first.status, 'stopped');
      expect(project.entries.last.translations['en']?.text ?? '', isEmpty);
    },
  );

  test('project deletion rejects active results', () async {
    final task = controller.startTranslation();
    controller.deleteProject(project.id);
    translator.complete(0, 'Login');
    await task;
    expect(controller.projects, isEmpty);
    expect(controller.currentProject, isNull);
    expect(controller.running, isFalse);
  });

  test('review rejects empty or mismatched placeholder translations', () {
    final entry = project.entries.single;
    controller.reviewTranslation(entry, 'en', true);
    expect(entry.value('en').reviewed, isFalse);
    controller.updateEntrySource(entry, '欢迎 {name}');
    controller.editTranslation(entry, 'en', 'Welcome');
    controller.reviewTranslation(entry, 'en', true);
    expect(entry.value('en').reviewed, isFalse);
    expect(
      controller.validate().any((issue) => issue.type == 'placeholders'),
      isTrue,
    );
  });

  test(
    'projects, translations, settings and export snapshots persist',
    () async {
      controller.editTranslation(project.entries.single, 'en', 'Login');
      project.exports.add(
        ExportRecord(name: 'en.json', files: {'en.json': '{"login":"Login"}'}),
      );
      await controller.saveSettings(
        email: 'author@example.com',
        apiBaseUrl: '',
        includeSource: false,
      );
      await controller.flush();
      final restored = AppController();
      await restored.initialize();
      expect(restored.projects.single.entries.single.value('en').text, 'Login');
      expect(
        restored.projects.single.exports.single.files['en.json'],
        contains('Login'),
      );
      expect(restored.settings.email, 'author@example.com');
      expect(restored.settings.includeSource, isFalse);
      restored.dispose();
    },
  );

  test(
    'interrupted persisted jobs reopen paused and in-flight values pending',
    () async {
      final task = controller.startTranslation();
      await controller.flush();
      final restored = AppController();
      await restored.initialize();
      expect(restored.projects.single.jobs.single.status, 'paused');
      expect(
        restored.projects.single.entries.single.value('en').status,
        TranslationStatus.pending,
      );
      restored.dispose();
      controller.pauseTranslation();
      translator.complete(0);
      await task;
    },
  );

  test('corrupt storage is preserved without silently replacing it', () async {
    await controller.flush();
    controller.dispose();
    SharedPreferences.setMockInitialValues({
      AppController.storageKey: 'invalid-json',
    });
    controller = AppController();
    await controller.initialize();
    controller.createProject('New');
    await controller.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppController.storageKey), 'invalid-json');
    expect(controller.error, isNotNull);
  });

  test('unsupported version is preserved', () async {
    await controller.flush();
    controller.dispose();
    final raw = jsonEncode({'version': 99, 'projects': []});
    SharedPreferences.setMockInitialValues({AppController.storageKey: raw});
    controller = AppController();
    await controller.initialize();
    await controller.flush();
    expect(
      (await SharedPreferences.getInstance()).getString(
        AppController.storageKey,
      ),
      raw,
    );
  });
}
