class HelpContentPage {
  const HelpContentPage({
    required this.id,
    required this.key,
    required this.title,
    required this.fileName,
    required this.parentKey,
    required this.sortOrder,
    required this.markdown,
    required this.isPublished,
    required this.seededFromDocsAt,
    required this.updatedAt,
    required this.updatedByUserId,
    required this.updatedByEmail,
  });

  final String id;
  final String key;
  final String title;
  final String fileName;
  final String? parentKey;
  final int sortOrder;
  final String markdown;
  final bool isPublished;
  final DateTime? seededFromDocsAt;
  final DateTime? updatedAt;
  final String? updatedByUserId;
  final String? updatedByEmail;

  factory HelpContentPage.fromJson(Map<String, dynamic> json) {
    return HelpContentPage(
      id: _textOf(json['id']),
      key: _textOf(json['key']),
      title: _textOf(json['title']),
      fileName: _textOf(json['fileName']),
      parentKey: _nullableTextOf(json['parentKey']),
      sortOrder: _intOf(json['sortOrder']),
      markdown: json['markdown']?.toString() ?? '',
      isPublished: json['isPublished'] == true,
      seededFromDocsAt: _dateOf(json['seededFromDocsAt']),
      updatedAt: _dateOf(json['updatedAt']),
      updatedByUserId: _nullableTextOf(json['updatedByUserId']),
      updatedByEmail: _nullableTextOf(json['updatedByEmail']),
    );
  }

  static String _textOf(Object? value) => value?.toString().trim() ?? '';

  static String? _nullableTextOf(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _dateOf(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

class HelpContentAdminSnapshot {
  const HelpContentAdminSnapshot({
    required this.pages,
    required this.updatedAt,
  });

  final List<HelpContentPage> pages;
  final DateTime? updatedAt;

  factory HelpContentAdminSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'];
    final pages = rawPages is List
        ? rawPages
              .whereType<Map<String, dynamic>>()
              .map(HelpContentPage.fromJson)
              .toList(growable: false)
        : const <HelpContentPage>[];
    return HelpContentAdminSnapshot(
      pages: pages,
      updatedAt: HelpContentPage._dateOf(json['updatedAt']),
    );
  }
}

class HelpContentSeedResult {
  const HelpContentSeedResult({
    required this.seeded,
    required this.overwriteExisting,
    required this.pageCount,
    required this.sourcePath,
    required this.seededAt,
  });

  final bool seeded;
  final bool overwriteExisting;
  final int pageCount;
  final String sourcePath;
  final DateTime? seededAt;

  factory HelpContentSeedResult.fromJson(Map<String, dynamic> json) {
    return HelpContentSeedResult(
      seeded: json['seeded'] == true,
      overwriteExisting: json['overwriteExisting'] == true,
      pageCount: HelpContentPage._intOf(json['pageCount']),
      sourcePath: HelpContentPage._textOf(json['sourcePath']),
      seededAt: HelpContentPage._dateOf(json['seededAt']),
    );
  }
}
