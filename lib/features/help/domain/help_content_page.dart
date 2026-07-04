enum HelpPageVisibility { draft, public, private }

extension HelpPageVisibilityX on HelpPageVisibility {
  String get apiValue => switch (this) {
    HelpPageVisibility.draft => 'DRAFT',
    HelpPageVisibility.public => 'PUBLIC',
    HelpPageVisibility.private => 'PRIVATE',
  };

  String get label => switch (this) {
    HelpPageVisibility.draft => 'Nháp',
    HelpPageVisibility.public => 'Public',
    HelpPageVisibility.private => 'Private',
  };

  String get description => switch (this) {
    HelpPageVisibility.draft => 'Chưa hiển thị ra ngoài sau khi lưu.',
    HelpPageVisibility.public =>
      'Ai có link cũng xem được, không cần đăng nhập.',
    HelpPageVisibility.private => 'Chỉ xem được sau khi đăng nhập.',
  };

  bool get isPublished => this != HelpPageVisibility.draft;
  bool get isAuthenticatedOnly => this == HelpPageVisibility.private;

  static HelpPageVisibility fromJson(
    Object? value, {
    required bool isPublished,
    required bool isAuthenticatedOnly,
  }) {
    final normalized = value?.toString().trim().toUpperCase();
    return switch (normalized) {
      'DRAFT' => HelpPageVisibility.draft,
      'PUBLIC' => HelpPageVisibility.public,
      'PRIVATE' => HelpPageVisibility.private,
      _ =>
        !isPublished
            ? HelpPageVisibility.draft
            : isAuthenticatedOnly
            ? HelpPageVisibility.private
            : HelpPageVisibility.public,
    };
  }
}

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
    this.isAuthenticatedOnly = false,
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
  final bool isAuthenticatedOnly;
  final DateTime? seededFromDocsAt;
  final DateTime? updatedAt;
  final String? updatedByUserId;
  final String? updatedByEmail;

  HelpPageVisibility get visibility => HelpPageVisibilityX.fromJson(
    null,
    isPublished: isPublished,
    isAuthenticatedOnly: isAuthenticatedOnly,
  );

  factory HelpContentPage.fromJson(Map<String, dynamic> json) {
    final isPublished = json['isPublished'] == true;
    final isAuthenticatedOnly = json['isAuthenticatedOnly'] == true;
    final visibility = HelpPageVisibilityX.fromJson(
      json['visibility'],
      isPublished: isPublished,
      isAuthenticatedOnly: isAuthenticatedOnly,
    );
    return HelpContentPage(
      id: _textOf(json['id']),
      key: _textOf(json['key']),
      title: _textOf(json['title']),
      fileName: _textOf(json['fileName']),
      parentKey: _nullableTextOf(json['parentKey']),
      sortOrder: _intOf(json['sortOrder']),
      markdown: json['markdown']?.toString() ?? '',
      isPublished: visibility.isPublished,
      isAuthenticatedOnly: visibility.isAuthenticatedOnly,
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

typedef HelpContentPublicSnapshot = HelpContentAdminSnapshot;

class HelpContentAssetUploadResult {
  const HelpContentAssetUploadResult({
    required this.pageKey,
    required this.imageUrl,
    required this.markdown,
    required this.fileName,
  });

  final String? pageKey;
  final String imageUrl;
  final String markdown;
  final String? fileName;

  factory HelpContentAssetUploadResult.fromJson(Map<String, dynamic> json) {
    return HelpContentAssetUploadResult(
      pageKey: HelpContentPage._nullableTextOf(json['pageKey']),
      imageUrl: HelpContentPage._textOf(json['imageUrl']),
      markdown: HelpContentPage._textOf(json['markdown']),
      fileName: HelpContentPage._nullableTextOf(json['fileName']),
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
