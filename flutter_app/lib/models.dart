import 'dart:math';

const supportedLanguages = <Language>[
  Language('en', '英语', 'English', 'EN'),
  Language('ja', '日语', '日本語', 'JA'),
  Language('ko', '韩语', '한국어', 'KO'),
  Language('fr', '法语', 'Français', 'FR'),
  Language('de', '德语', 'Deutsch', 'DE'),
  Language('es', '西班牙语', 'Español', 'ES'),
  Language('zh-Hant', '繁体中文', '繁體中文', '繁'),
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
  });
  String text;
  String provider;
  bool reviewed;
  bool edited;
  TranslationStatus status;
  String error;
  int revision;
  Map<String, dynamic> toJson() => {
    'text': text,
    'provider': provider,
    'reviewed': reviewed,
    'edited': edited,
    'status': status.name,
    'error': error,
    'revision': revision,
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
  factory Entry.fromJson(Map<String, dynamic> data) => Entry(
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
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now();
  final String id;
  final DateTime createdAt;
  String status;
  int completed;
  int total;
  int failed;
  String provider;
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'status': status,
    'completed': completed,
    'total': total,
    'failed': failed,
    'provider': provider,
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
  );
}

class AppSettings {
  AppSettings({
    this.email = '',
    this.apiBaseUrl = const String.fromEnvironment('API_BASE_URL'),
    this.includeSource = true,
  });
  String email;
  String apiBaseUrl;
  bool includeSource;
  Map<String, dynamic> toJson() => {
    'email': email,
    'apiBaseUrl': apiBaseUrl,
    'includeSource': includeSource,
  };
  factory AppSettings.fromJson(Map<String, dynamic> data) => AppSettings(
    email: data['email'] as String? ?? '',
    apiBaseUrl:
        data['apiBaseUrl'] as String? ??
        const String.fromEnvironment('API_BASE_URL'),
    includeSource: data['includeSource'] != false,
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
