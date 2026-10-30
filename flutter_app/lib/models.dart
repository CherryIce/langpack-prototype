import 'dart:math';

const translationProviders = [
  'MyMemory',
  'ZTAITrans',
  'DeepL',
  'Azure',
  'Google',
  'Baidu',
  'Tencent',
  'Alibaba',
];

const providerCredentialFields = <String, List<String>>{
  'MyMemory': ['apiKey'],
  'ZTAITrans': ['apiKey', 'tenantId', 'developerToken'],
  'DeepL': ['apiKey', 'plan'],
  'Azure': ['apiKey', 'region'],
  'Google': ['apiKey'],
  'Baidu': ['appId', 'secretKey'],
  'Tencent': ['secretId', 'secretKey', 'region'],
  'Alibaba': ['accessKeyId', 'accessKeySecret'],
};

const providerSecretFields = {
  'apiKey',
  'developerToken',
  'appId',
  'secretId',
  'secretKey',
  'accessKeyId',
  'accessKeySecret',
};

bool providerCredentialsReady(String provider, Map<String, String> values) {
  bool present(String field) => (values[field] ?? '').trim().isNotEmpty;
  return switch (provider) {
    'ZTAITrans' => present('apiKey') != present('developerToken'),
    'Baidu' => present('appId') && present('secretKey'),
    'Tencent' => present('secretId') && present('secretKey'),
    'Alibaba' => present('accessKeyId') && present('accessKeySecret'),
    _ => present('apiKey'),
  };
}

List<String> normalizeProviderOrder(Iterable<dynamic> values) {
  final result = values
      .whereType<String>()
      .where(translationProviders.contains)
      .toSet()
      .toList();
  return result.isEmpty ? ['MyMemory'] : result;
}

const supportedLanguages = <Language>[
  Language('zh-Hant', '繁体中文', '繁體中文', '繁'),
  Language('en', '英语', 'English', 'EN'),
  Language('pt-BR', '葡萄牙语（巴西）', 'Português (Brasil)', 'BR'),
  Language('pt-PT', '葡萄牙语（葡萄牙）', 'Português (Portugal)', 'PT'),
  Language('ms', '马来语', 'Bahasa Melayu', 'MS'),
  Language('th', '泰语', 'ไทย', 'TH'),
  Language('fr', '法语', 'Français', 'FR'),
  Language('es', '西班牙语', 'Español', 'ES'),
  Language('ar', '阿拉伯语', 'العربية', 'AR'),
  Language('fil', '菲律宾语', 'Filipino', 'FIL'),
  Language('vi', '越南语', 'Tiếng Việt', 'VI'),
  Language('ru', '俄语', 'Русский', 'RU'),
  Language('tr', '土耳其语', 'Türkçe', 'TR'),
  Language('id', '印度尼西亚语', 'Bahasa Indonesia', 'ID'),
  Language('ja', '日语', '日本語', 'JA'),
  Language('ko', '韩语', '한국어', 'KO'),
  Language('de', '德语', 'Deutsch', 'DE'),
  Language('hi', '印地语', 'हिन्दी', 'HI'),
  Language('hu', '匈牙利语', 'Magyar', 'HU'),
  Language('it', '意大利语', 'Italiano', 'IT'),
  Language('ro', '罗马尼亚语', 'Română', 'RO'),
  Language('sv', '瑞典语', 'Svenska', 'SV'),
  Language('bg', '保加利亚语', 'Български', 'BG'),
  Language('pl', '波兰语', 'Polski', 'PL'),
  Language('da', '丹麦语', 'Dansk', 'DA'),
  Language('fi', '芬兰语', 'Suomi', 'FI'),
  Language('nl', '荷兰语', 'Nederlands', 'NL'),
  Language('cs', '捷克语', 'Čeština', 'CS'),
  Language('sk', '斯洛伐克语', 'Slovenčina', 'SK'),
  Language('uk', '乌克兰语', 'Українська', 'UK'),
  Language('el', '希腊语', 'Ελληνικά', 'EL'),
  Language('nb', '书面挪威语', 'Norsk bokmål', 'NB'),
  Language('hr', '克罗地亚语', 'Hrvatski', 'HR'),
  Language('si', '僧伽罗语', 'සිංහල', 'SI'),
];

class Language {
  const Language(this.code, this.name, this.nativeName, this.badge);
  final String code;
  final String name;
  final String nativeName;
  final String badge;
}

String languageName(String code) => supportedLanguages
    .firstWhere(
      (language) => language.code == code,
      orElse: () => Language(code, code, code, code),
    )
    .name;

List<String> normalizeTargetLocales(Iterable<dynamic> codes) {
  final canonical = {
    for (final language in supportedLanguages)
      language.code.toLowerCase(): language.code,
  };
  return codes
      .whereType<String>()
      .map((code) => canonical[code.trim().toLowerCase()])
      .whereType<String>()
      .toSet()
      .toList();
}

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';

enum TranslationStatus { pending, translating, done, failed }

class TranslationValue {
  TranslationValue({
    this.text = '',
    this.provider = '',
    this.reviewed = false,
    this.edited = false,
    this.status = TranslationStatus.pending,
    this.error = '',
    this.revision = 0,
    this.sourceText,
    this.sourceRevision,
    this.model,
  });
  String text;
  String provider;
  bool reviewed;
  bool edited;
  TranslationStatus status;
  String error;
  int revision;
  String? sourceText;
  int? sourceRevision;
  String? model;
  Map<String, dynamic> toJson() => {
    'text': text,
    'provider': provider,
    'reviewed': reviewed,
    'edited': edited,
    'status': status.name,
    'error': error,
    'revision': revision,
    'sourceText': sourceText,
    'sourceRevision': sourceRevision,
    if (model != null) 'model': model,
  };
  factory TranslationValue.fromJson(Map<String, dynamic> data) {
    var status = TranslationStatus.values.firstWhere(
      (value) => value.name == data['status'],
      orElse: () => TranslationStatus.pending,
    );
    if (status == TranslationStatus.translating) {
      status = TranslationStatus.pending;
    }
    return TranslationValue(
      text: data['text'] as String? ?? '',
      provider: data['provider'] as String? ?? '',
      reviewed: data['reviewed'] == true,
      edited: data['edited'] == true,
      status: status,
      error: data['error'] as String? ?? '',
      revision: data['revision'] as int? ?? 0,
      sourceText: data['sourceText'] as String?,
      sourceRevision: data['sourceRevision'] as int?,
      model: data['model'] as String?,
    );
  }
}

class Entry {
  Entry({
    String? id,
    required this.key,
    required this.source,
    this.selected = true,
    this.sourceRevision = 0,
    Map<String, TranslationValue>? translations,
  }) : id = id ?? newId(),
       translations = translations ?? {};
  final String id;
  String key;
  String source;
  bool selected;
  int sourceRevision;
  final Map<String, TranslationValue> translations;
  TranslationValue value(String locale) =>
      translations.putIfAbsent(locale, () => TranslationValue());
  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'source': source,
    'selected': selected,
    'sourceRevision': sourceRevision,
    'translations': translations.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };
  factory Entry.fromJson(Map<String, dynamic> data) {
    final entry = Entry(
      id: data['id'] as String?,
      key: data['key'] as String? ?? '',
      source: data['source'] as String? ?? '',
      selected: data['selected'] != false,
      sourceRevision: data['sourceRevision'] as int? ?? 0,
      translations: (data['translations'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          TranslationValue.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
    // Older saves kept translations on the entry and cleared them on source edits.
    for (final value in entry.translations.values) {
      if (value.sourceText == null && value.sourceRevision == null) {
        value.sourceText = entry.source;
        value.sourceRevision = entry.sourceRevision;
      }
    }
    return entry;
  }
}

class DocumentBlock {
  DocumentBlock(this.text, {this.type = 'paragraph', this.selected = true});
  String text;
  final String type;
  bool selected;
}

class ExportRecord {
  ExportRecord({
    String? id,
    required this.name,
    required this.files,
    DateTime? createdAt,
    this.draft = false,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now();
  final String id;
  final String name;
  final Map<String, String> files;
  final DateTime createdAt;
  final bool draft;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'files': files,
    'createdAt': createdAt.toIso8601String(),
    'draft': draft,
  };
  factory ExportRecord.fromJson(Map<String, dynamic> data) => ExportRecord(
    id: data['id'] as String?,
    name: data['name'] as String? ?? '语言包',
    files: Map<String, String>.from(data['files'] as Map? ?? {}),
    createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
    draft: data['draft'] == true,
  );
}

class Project {
  Project({
    String? id,
    required this.name,
    this.description = '',
    List<Entry>? entries,
    List<String>? locales,
    List<ExportRecord>? exports,
    List<TaskRecord>? jobs,
    DateTime? updatedAt,
  }) : id = id ?? newId(),
       entries = entries ?? [],
       locales = locales ?? ['en', 'ja'],
       exports = exports ?? [],
       jobs = jobs ?? [],
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  String name;
  String description;
  final List<Entry> entries;
  final List<String> locales;
  final List<ExportRecord> exports;
  final List<TaskRecord> jobs;
  DateTime updatedAt;
  Iterable<Entry> get selectedEntries =>
      entries.where((entry) => entry.selected);
  int get translatedCount => selectedEntries.fold(
    0,
    (sum, entry) =>
        sum +
        locales
            .where(
              (locale) =>
                  entry.translations[locale]?.text.trim().isNotEmpty == true,
            )
            .length,
  );
  int get totalCount => selectedEntries.length * locales.length;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'locales': locales,
    'exports': exports.map((record) => record.toJson()).toList(),
    'jobs': jobs.map((record) => record.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory Project.fromJson(Map<String, dynamic> data) => Project(
    id: data['id'] as String?,
    name: data['name'] as String? ?? '未命名项目',
    description: data['description'] as String? ?? '',
    entries: (data['entries'] as List? ?? [])
        .map((entry) => Entry.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList(),
    locales: (data['locales'] as List? ?? ['en', 'ja'])
        .cast<String>()
        .where(
          (code) => supportedLanguages.any((language) => language.code == code),
        )
        .toSet()
        .toList(),
    exports: (data['exports'] as List? ?? [])
        .take(20)
        .map(
          (record) =>
              ExportRecord.fromJson(Map<String, dynamic>.from(record as Map)),
        )
        .toList(),
    jobs: (data['jobs'] as List? ?? [])
        .take(20)
        .map(
          (record) =>
              TaskRecord.fromJson(Map<String, dynamic>.from(record as Map)),
        )
        .toList(),
    updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? ''),
  );
}

class TaskRecord {
  TaskRecord({
    String? id,
    DateTime? createdAt,
    this.status = 'running',
    this.completed = 0,
    this.total = 0,
    this.failed = 0,
    this.provider = '',
    this.reused = 0,
    List<String>? locales,
    this.batch = true,
  }) : id = id ?? newId(),
       locales = normalizeTargetLocales(locales ?? const <String>[]),
       createdAt = createdAt ?? DateTime.now();
  final String id;
  final DateTime createdAt;
  String status;
  int completed;
  int total;
  int failed;
  String provider;
  int reused;
  final List<String> locales;
  final bool batch;
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'status': status,
    'completed': completed,
    'total': total,
    'failed': failed,
    'provider': provider,
    'reused': reused,
    'locales': locales,
    'batch': batch,
  };
  factory TaskRecord.fromJson(Map<String, dynamic> data) => TaskRecord(
    id: data['id'] as String?,
    createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
    status: data['status'] == 'running'
        ? 'paused'
        : data['status'] as String? ?? 'paused',
    completed: data['completed'] as int? ?? 0,
    total: data['total'] as int? ?? 0,
    failed: data['failed'] as int? ?? 0,
    provider: data['provider'] as String? ?? '',
    reused: data['reused'] as int? ?? 0,
    locales: normalizeTargetLocales(
      data['locales'] is List ? data['locales'] as List : const [],
    ),
    batch: data['batch'] != false,
  );
}

class IncrementalPlan {
  const IncrementalPlan({
    this.retained = 0,
    this.reusable = 0,
    this.pending = 0,
    this.uniquePending = 0,
  });
  final int retained, reusable, pending, uniquePending;
}

class AppSettings {
  AppSettings({
    this.email = '',
    this.apiBaseUrl = const String.fromEnvironment('API_BASE_URL'),
    this.includeSource = true,
    Iterable<dynamic> recentLocales = const [],
    Iterable<dynamic> providerOrder = const ['MyMemory'],
    this.providerFallback = true,
  }) : recentLocales = normalizeTargetLocales(recentLocales),
       providerOrder = normalizeProviderOrder(providerOrder);
  String email;
  String apiBaseUrl;
  bool includeSource;
  final List<String> recentLocales;
  final List<String> providerOrder;
  bool providerFallback;
  Map<String, dynamic> toJson() => {
    'email': email,
    'apiBaseUrl': apiBaseUrl,
    'includeSource': includeSource,
    'recentLocales': normalizeTargetLocales(recentLocales),
    'providerOrder': normalizeProviderOrder(providerOrder),
    'providerFallback': providerFallback,
  };
  factory AppSettings.fromJson(Map<String, dynamic> data) => AppSettings(
    email: data['email'] as String? ?? '',
    apiBaseUrl:
        data['apiBaseUrl'] as String? ??
        const String.fromEnvironment('API_BASE_URL'),
    includeSource: data['includeSource'] != false,
    recentLocales: data['recentLocales'] is List
        ? data['recentLocales'] as List
        : const [],
    providerOrder: data['providerOrder'] is List
        ? data['providerOrder'] as List
        : const ['MyMemory'],
    providerFallback: data['providerFallback'] != false,
  );
}

class ValidationIssue {
  const ValidationIssue(
    this.message, {
    this.entryId,
    this.locale,
    this.type = 'validation',
  });
  final String message;
  final String? entryId;
  final String? locale;
  final String type;
  Map<String, dynamic> toJson() => {
    'message': message,
    'entryId': entryId,
    'locale': locale,
    'type': type,
  };
}
