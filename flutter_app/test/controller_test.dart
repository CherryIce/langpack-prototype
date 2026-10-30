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
  final bypasses = <bool>[];
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
    bypasses.add(bypassCache);
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
    'single retranslation cannot narrow a paused batch continuation',
    () async {
      controller.setLocales(['en', 'ja']);
      final pausedTask = controller.startTranslation();
      controller.pauseTranslation();
      final single = controller.startTranslation(
        entryId: project.entries.single.id,
        locale: 'en',
        overwrite: true,
      );
      translator.complete(1, 'Login');
      await single;
      translator.complete(0, 'Stale');
      await pausedTask;
      final resumed = controller.startTranslation(resume: true);
      expect(translator.locales, ['en', 'en', 'ja']);
      translator.complete(2, 'ログイン');
      await resumed;
      expect(project.jobs.first.locales, ['en', 'ja']);
      expect(controller.settings.recentLocales, ['en', 'ja']);
    },
  );

  test(
    'single retranslation ignores invalid unrelated entries without changing recent targets',
    () async {
      controller.settings.recentLocales.add('fr');
      controller.addBlocks([DocumentBlock('注册')]);
      final other = project.entries.last;
      other.key = 'INVALID';
      controller.updateEntrySource(other, '');
      final task = controller.startTranslation(
        entryId: project.entries.first.id,
        locale: 'en',
        overwrite: true,
      );
      expect(translator.sources, ['登录']);
      translator.complete(0, 'Sign in');
      await task;
      expect(controller.settings.recentLocales, ['fr']);
      expect(project.entries.first.value('en').text, 'Sign in');
      expect(other.translations, isEmpty);
    },
  );

  test('recent language preference records only valid batch starts', () async {
    expect(controller.settings.recentLocales, isEmpty);
    controller.setLocales(['pt-BR', 'fil', 'pt-BR', 'zh-Hans', 'unknown']);
    expect(project.locales, ['pt-BR', 'fil']);
    expect(controller.settings.recentLocales, isEmpty);
    final task = controller.startTranslation();
    expect(controller.settings.recentLocales, ['pt-BR', 'fil']);
    translator.complete(0, 'Entrar');
    await Future<void>.delayed(Duration.zero);
    translator.complete(1, 'Mag-log in');
    await task;
    await controller.saveSettings(
      email: '',
      apiBaseUrl: '',
      includeSource: false,
    );
    expect(controller.settings.recentLocales, ['pt-BR', 'fil']);
    controller.setLocales([]);
    await controller.startTranslation();
    expect(controller.settings.recentLocales, ['pt-BR', 'fil']);
    controller.setLocales(['si']);
    controller.selectEntry(project.entries.single, false);
    await controller.startTranslation();
    expect(controller.settings.recentLocales, ['pt-BR', 'fil']);
    controller.selectEntry(project.entries.single, true);
    controller.updateEntrySource(project.entries.single, '  ');
    await controller.startTranslation();
    expect(controller.settings.recentLocales, ['pt-BR', 'fil']);
  });

  test(
    'draft language changes preserve history and started batches only translate the draft',
    () async {
      controller.setLocales(['en', 'ja']);
      controller.settings.recentLocales.add('fr');
      controller.applyRecentLocales();
      expect(controller.batchLocales, ['fr']);
      expect(project.locales, ['en', 'ja']);
      controller.openProject(project.id);
      expect(project.locales, ['en', 'ja']);
      controller.applyRecentLocales();
      final task = controller.startTranslation();
      expect(translator.locales, ['fr']);
      expect(project.locales, ['en', 'ja', 'fr']);
      translator.complete(0, 'Connexion');
      await task;
      expect(project.jobs.first.locales, ['fr']);
      expect(controller.settings.recentLocales, ['fr']);
    },
  );

  test('paused task scope survives new drafts and persisted resume', () async {
    controller.setLocales(['en', 'ja']);
    controller.settings.recentLocales.add('fr');
    controller.applyRecentLocales();
    final first = controller.startTranslation();
    controller.pauseTranslation();
    controller.settings.recentLocales
      ..clear()
      ..add('si');
    controller.applyRecentLocales();
    expect(controller.batchLocales, ['si']);
    final resumed = controller.startTranslation(resume: true);
    expect(translator.locales, ['fr', 'fr']);
    translator.complete(0, 'Stale');
    await first;
    translator.complete(1, 'Connexion');
    await resumed;
    expect(controller.settings.recentLocales, ['si']);
    await controller.flush();
    final restored = AppController(translator: ControlledTranslator());
    await restored.initialize();
    restored.openProject(project.id);
    expect(restored.projects.single.jobs.first.locales, ['fr']);
    await restored.startTranslation(resume: true);
    expect(restored.settings.recentLocales, ['si']);
    restored.dispose();
  });

  test(
    'invalid or duplicate keys do not start a batch or record preferences',
    () async {
      controller.settings.recentLocales.add('fr');
      final entry = project.entries.single;
      entry.key = 'INVALID';
      await controller.startTranslation();
      expect(translator.requests, isEmpty);
      expect(controller.settings.recentLocales, ['fr']);
      entry.key = 'login';
      controller.addBlocks([DocumentBlock('注册')]);
      project.entries.last.key = 'login';
      await controller.startTranslation();
      expect(translator.requests, isEmpty);
      expect(controller.settings.recentLocales, ['fr']);
    },
  );

  test(
    '34 targets export alongside source as 35 distinct resource files',
    () async {
      controller.setLocales(
        supportedLanguages.map((language) => language.code).toList(),
      );
      for (final code in project.locales) {
        controller.editTranslation(
          project.entries.single,
          code,
          'Translated $code',
        );
      }
      await controller.startTranslation();
      final packages = controller.previewPackages();
      expect(packages.length, 35);
      expect(
        packages.keys,
        containsAll([
          'zh-Hans.json',
          'pt-BR.json',
          'pt-PT.json',
          'fil.json',
          'nb.json',
          'si.json',
        ]),
      );
      expect(controller.settings.recentLocales.length, 34);
      expect(translator.requests, isEmpty);
    },
  );

  test(
    'all retained zero-request batches save recent choice and survive restart',
    () async {
      controller.setLocales(['nb', 'si']);
      for (final code in project.locales) {
        controller.editTranslation(project.entries.single, code, 'Manual');
      }
      await controller.startTranslation();
      expect(translator.requests, isEmpty);
      expect(controller.settings.recentLocales, ['nb', 'si']);
      await controller.flush();
      final restored = AppController();
      await restored.initialize();
      expect(restored.settings.recentLocales, ['nb', 'si']);
      final next = restored.createProject('最近选择');
      expect(next.locales, ['nb', 'si']);
      restored.openProject(project.id);
      expect(restored.currentProject!.locales, ['nb', 'si']);
      restored.dispose();
    },
  );

  test(
    'single retranslation retries and resumes preserve full recent choice',
    () async {
      controller.settings.recentLocales.addAll(['es', 'fr', 'pt-PT']);
      final single = controller.startTranslation(
        entryId: project.entries.single.id,
        locale: 'en',
        overwrite: true,
      );
      translator.complete(0, 'Login');
      await single;
      expect(controller.settings.recentLocales, ['es', 'fr', 'pt-PT']);
      project.entries.single.value('en')
        ..text = ''
        ..status = TranslationStatus.failed;
      final retry = controller.startTranslation(retryFailedOnly: true);
      translator.complete(1, 'Login');
      await retry;
      expect(controller.settings.recentLocales, ['es', 'fr', 'pt-PT']);
      project.entries.single.value('en')
        ..text = ''
        ..status = TranslationStatus.pending;
      final resume = controller.startTranslation(resume: true);
      translator.complete(2, 'Login');
      await resume;
      expect(controller.settings.recentLocales, ['es', 'fr', 'pt-PT']);
    },
  );

  test(
    'recent defaults apply explicitly while opening projects keeps history',
    () {
      controller.settings.recentLocales.addAll(['fil', 'nb']);
      controller.openProject(project.id);
      expect(project.locales, ['en']);
      controller.applyRecentLocales();
      expect(project.locales, ['en']);
      expect(controller.batchLocales, ['fil', 'nb']);
      controller.setLocales(['ja']);
      final next = controller.createProject('New');
      expect(next.locales, ['fil', 'nb']);
      controller.openProject(project.id);
      expect(project.locales, ['ja']);
      expect(controller.settings.recentLocales, ['fil', 'nb']);
    },
  );

  test(
    'stored preferences filter source unknown duplicate and non-string values',
    () {
      expect(supportedLanguages.length, 34);
      expect(
        supportedLanguages.map((language) => language.code).toSet().length,
        34,
      );
      expect(
        supportedLanguages.any((language) => language.code == 'zh-Hans'),
        isFalse,
      );
      final settings = AppSettings.fromJson({
        'recentLocales': [
          'zh-Hans',
          'fil',
          'fil',
          'nb',
          'xx',
          1,
          ' SI ',
          'pt-br',
        ],
      });
      expect(settings.recentLocales, ['fil', 'nb', 'si', 'pt-BR']);
      expect(
        AppSettings.fromJson({'recentLocales': 'invalid'}).recentLocales,
        isEmpty,
      );
      final legacy = Project.fromJson({
        'name': 'Legacy',
        'locales': ['en', 'ja'],
      });
      expect(legacy.locales, ['en', 'ja']);
    },
  );

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

  test(
    'same-batch duplicates use one request and keep independent values',
    () async {
      controller.addBlocks([DocumentBlock('登录'), DocumentBlock('登录')]);
      final plan = controller.incrementalPlan();
      expect(plan.pending, 3);
      expect(plan.uniquePending, 1);
      final task = controller.startTranslation();
      translator.complete(0, 'Login');
      await task;
      expect(translator.sources, ['登录']);
      expect(controller.reused, 2);
      expect(project.jobs.single.reused, 2);
      expect(
        project.entries.map((e) => e.value('en').text),
        everyElement('Login'),
      );
      controller.editTranslation(project.entries[1], 'en', 'Sign in');
      expect(project.entries.first.value('en').text, 'Login');
      expect(project.entries.last.value('en').text, 'Login');
    },
  );

  test(
    'repeat import and key edits reuse only the existing language',
    () async {
      final first = controller.startTranslation();
      translator.complete(0, 'Login');
      await first;
      controller.addBlocks([DocumentBlock('登录')]);
      controller.updateEntryKey(project.entries.last, 'other_context_key');
      expect(controller.incrementalPlan().reusable, 1);
      await controller.startTranslation();
      expect(translator.sources, ['登录']);
      controller.setLocales(['en', 'ja']);
      final next = controller.startTranslation();
      expect(translator.locales, ['en', 'ja']);
      translator.complete(1, 'ログイン');
      await next;
      expect(translator.sources, ['登录', '登录']);
      expect(project.entries.last.value('ja').text, 'ログイン');
      controller.updateEntrySource(project.entries.last, '退出登录');
      controller.setLocales(['en']);
      final changed = controller.startTranslation();
      expect(translator.sources.last, '退出登录');
      translator.complete(2, 'Log out');
      await changed;
      expect(project.entries.first.value('en').text, 'Login');
    },
  );

  test(
    'project translation reuse survives restart without service cache',
    () async {
      final first = controller.startTranslation();
      translator.complete(0, 'Login');
      await first;
      await controller.flush();
      final freshTranslator = ControlledTranslator();
      final restored = AppController(translator: freshTranslator);
      await restored.initialize();
      restored.openProject(project.id);
      restored.addBlocks([DocumentBlock('登录')]);
      await restored.startTranslation();
      expect(freshTranslator.requests, isEmpty);
      expect(restored.currentProject!.entries.last.value('en').text, 'Login');
      expect(restored.currentProject!.jobs.first.reused, 1);
      restored.dispose();
    },
  );

  test('project reuse excludes edited results and other projects', () async {
    controller.editTranslation(project.entries.single, 'en', 'Sign in');
    controller.reviewTranslation(project.entries.single, 'en', true);
    controller.addBlocks([DocumentBlock('登录')]);
    final task = controller.startTranslation();
    expect(translator.sources, ['登录']);
    translator.complete(0, 'Login');
    await task;
    expect(project.entries.first.value('en').text, 'Sign in');
    expect(project.entries.first.value('en').reviewed, isTrue);
    controller.createProject('Other');
    controller.setLocales(['en']);
    controller.addBlocks([DocumentBlock('登录')]);
    final other = controller.startTranslation();
    expect(translator.requests.length, 2);
    translator.complete(1, 'Log in');
    await other;
  });

  test(
    'explicit retranslation bypasses project reuse and service cache',
    () async {
      final first = controller.startTranslation();
      translator.complete(0, 'Login');
      await first;
      controller.addBlocks([DocumentBlock('登录')]);
      final forced = controller.startTranslation(
        entryId: project.entries.last.id,
        locale: 'en',
        overwrite: true,
      );
      expect(translator.sources, ['登录', '登录']);
      expect(translator.bypasses.last, isTrue);
      translator.complete(1, 'Sign in');
      await forced;
      expect(controller.reused, 0);
      expect(project.entries.last.value('en').text, 'Sign in');
    },
  );

  test(
    'a donor edited after completion is excluded from same-batch reuse',
    () async {
      controller.addBlocks([DocumentBlock('登录')]);
      var edited = false;
      void editCompleted() {
        if (!edited &&
            project.entries.first.value('en').status ==
                TranslationStatus.done) {
          edited = true;
          controller.editTranslation(project.entries.first, 'en', 'Sign in');
        }
      }

      controller.addListener(editCompleted);
      final task = controller.startTranslation();
      translator.complete(0, 'Login');
      await Future<void>.delayed(Duration.zero);
      expect(translator.sources, ['登录', '登录']);
      translator.complete(1, 'Log in');
      await task;
      controller.removeListener(editCompleted);
      expect(project.entries.first.value('en').text, 'Sign in');
      expect(project.entries.last.value('en').text, 'Log in');
      expect(controller.reused, 0);
    },
  );

  test(
    'reviewed machine results copy unreviewed and exact source matching is required',
    () async {
      final first = controller.startTranslation();
      translator.complete(0, 'Login');
      await first;
      controller.reviewTranslation(project.entries.first, 'en', true);
      controller.addBlocks([DocumentBlock('登录')]);
      await controller.startTranslation();
      expect(project.entries.last.value('en').text, 'Login');
      expect(project.entries.last.value('en').reviewed, isFalse);
      expect(project.entries.first.value('en').reviewed, isTrue);
      controller.updateEntrySource(project.entries.last, '登录 ');
      expect(controller.incrementalPlan().reusable, 0);
      expect(controller.incrementalPlan().uniquePending, 1);
    },
  );

  test(
    'conflicting machine translations request once for new batch duplicates',
    () async {
      controller.addBlocks([
        DocumentBlock('登录'),
        DocumentBlock('登录'),
        DocumentBlock('登录'),
      ]);
      for (var i = 0; i < 2; i++) {
        final entry = project.entries[i];
        entry.value('en')
          ..text = i == 0 ? 'Login' : 'Sign in'
          ..provider = 'MyMemory'
          ..status = TranslationStatus.done
          ..sourceText = entry.source
          ..sourceRevision = entry.sourceRevision;
      }
      expect(controller.incrementalPlan().reusable, 0);
      final task = controller.startTranslation();
      expect(translator.sources, ['登录']);
      translator.complete(0, 'Log in');
      await task;
      expect(translator.sources, ['登录']);
      expect(project.entries.last.value('en').text, 'Log in');
      expect(controller.reused, 1);
      controller.addBlocks([DocumentBlock('登录')]);
      expect(controller.incrementalPlan().reusable, 0);
    },
  );

  test(
    'stale source provenance and invalid placeholders never enter memory',
    () async {
      controller.updateEntrySource(project.entries.single, '欢迎 {name}');
      final original = project.entries.single;
      original.value('en')
        ..text = 'Welcome'
        ..provider = 'MyMemory'
        ..status = TranslationStatus.done
        ..sourceText = original.source
        ..sourceRevision = original.sourceRevision;
      controller.addBlocks([DocumentBlock(original.source)]);
      expect(controller.incrementalPlan().reusable, 0);
      original.value('en')
        ..text = 'Welcome {name}'
        ..sourceRevision = -1;
      expect(controller.incrementalPlan().reusable, 0);
      original.value('en')
        ..sourceRevision = original.sourceRevision
        ..sourceText = '其他原文';
      expect(controller.incrementalPlan().reusable, 0);
      original.value('en')
        ..sourceText = original.source
        ..sourceRevision = null;
      expect(controller.incrementalPlan().reusable, 0);
    },
  );

  test(
    'legacy persisted machine values migrate only when both bindings absent',
    () async {
      final entry = Entry.fromJson({
        'source': '登录',
        'key': 'login',
        'translations': {
          'en': {'text': 'Login', 'provider': 'MyMemory', 'status': 'done'},
        },
      });
      project.entries[0] = entry;
      controller.addBlocks([DocumentBlock('登录')]);
      await controller.startTranslation();
      expect(translator.requests, isEmpty);
      expect(project.entries.last.value('en').text, 'Login');
      final partial = entry.toJson();
      final values = partial['translations'] as Map<String, dynamic>;
      (values['en'] as Map<String, dynamic>)['sourceRevision'] = null;
      project.entries
        ..clear()
        ..add(Entry.fromJson(partial));
      controller.addBlocks([DocumentBlock('登录')]);
      expect(controller.incrementalPlan().reusable, 0);
    },
  );

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
