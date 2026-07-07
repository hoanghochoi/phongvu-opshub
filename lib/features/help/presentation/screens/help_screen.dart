import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/repositories/help_content_repository.dart';
import '../../domain/help_content_page.dart';
import '../../domain/help_content_tree.dart';

typedef HelpContentPublicLoader = Future<HelpContentPublicSnapshot> Function();

class HelpScreen extends StatefulWidget {
  const HelpScreen({
    super.key,
    this.repository,
    this.loader,
    this.onBack,
    this.embeddedInShell = false,
  });

  final HelpContentRepository? repository;
  final HelpContentPublicLoader? loader;
  final VoidCallback? onBack;
  final bool embeddedInShell;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  late final HelpContentRepository _repository;
  late final HelpContentPublicLoader _loader;

  List<HelpContentPage> _pages = const [];
  bool _loading = true;
  String? _errorMessage;
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? HelpContentRepository(ApiClient());
    _loader = widget.loader ?? _repository.fetchPublicSnapshot;
    unawaited(_load(reason: 'screen_open'));
  }

  Future<void> _load({required String reason}) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'HelpScreen',
      'Help screen load started',
      context: {'reason': reason, 'selectedKey': _selectedKey},
    );
    try {
      final snapshot = await _loader();
      if (!mounted) return;
      final pages = helpPagesInTreeOrder(
        snapshot.pages.where((page) => page.isPublished),
      );
      final treeStats = helpContentTreeStats(pages);
      final selectedKey = _resolveSelectedKey(pages);
      setState(() {
        _pages = pages;
        _loading = false;
        _errorMessage = null;
        _selectedKey = selectedKey;
      });
      await AppLogger.instance.info(
        'HelpScreen',
        'Help screen load succeeded',
        context: {
          'reason': reason,
          'pageCount': pages.length,
          'rootPageCount': treeStats.rootCount,
          'childPageCount': treeStats.childCount,
          'orphanPageCount': treeStats.orphanCount,
          'selectedKey': selectedKey,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } on ApiException catch (error) {
      await AppLogger.instance.warn(
        'HelpScreen',
        'Help screen load failed',
        context: {
          'reason': reason,
          'message': error.message,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'HelpScreen',
        'Help screen load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'reason': reason,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Không tải được hướng dẫn sử dụng.';
      });
    }
  }

  String? _resolveSelectedKey(List<HelpContentPage> pages) {
    if (_selectedKey != null && pages.any((page) => page.key == _selectedKey)) {
      return _selectedKey;
    }
    if (pages.any((page) => page.key == 'guide')) return 'guide';
    return pages.isEmpty ? null : pages.first.key;
  }

  Future<void> _selectPage(HelpContentPage page) async {
    setState(() => _selectedKey = page.key);
    await AppLogger.instance.info(
      'HelpScreen',
      'Help page selected',
      context: {'key': page.key, 'title': page.title},
    );
  }

  Future<void> _handleLink(String text) async {
    final href = text.trim();
    if (href.isEmpty) return;

    final byKey = _findPageByKey(href);
    if (byKey != null) {
      await _selectPage(byKey);
      return;
    }

    final byFileName = _findPageByFileName(href);
    if (byFileName != null) {
      await _selectPage(byFileName);
      return;
    }

    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (!uri.hasScheme) return;

    await AppLogger.instance.info(
      'HelpScreen',
      'Help external link opening',
      context: {'host': uri.host, 'path': uri.path},
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      AppToast.show(
        context,
        const SnackBar(content: Text('Chưa mở được liên kết hướng dẫn.')),
      );
    }
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    await AppLogger.instance.info(
      'HelpScreen',
      'Help back requested',
      context: {'hasCustomBack': widget.onBack != null},
    );
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageContent = AppResponsiveScrollView(
      onRefresh: () => _load(reason: 'pull_refresh'),
      refreshLogSource: 'HelpScreen',
      refreshLogContext: () => {
        'embeddedInShell': widget.embeddedInShell,
        'pageCount': _pages.length,
        'hasSelection': _selectedKey != null,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.embeddedInShell)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Tải lại hướng dẫn',
                onPressed: _loading
                    ? null
                    : () => _load(reason: 'manual_refresh'),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          _HelpScreenHeader(
            loading: _loading,
            pageCount: _pages.length,
            updatedAt: _pages
                .map((page) => page.updatedAt)
                .whereType<DateTime>()
                .fold<DateTime?>(null, (latest, value) {
                  if (latest == null || value.isAfter(latest)) return value;
                  return latest;
                }),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          _buildBody(),
        ],
      ),
    );
    if (widget.embeddedInShell) return pageContent;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null || Navigator.of(context).canPop()
            ? IconButton(
                tooltip: 'Quay lại',
                onPressed: _handleBack,
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: const Text('Hướng dẫn sử dụng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại hướng dẫn',
            onPressed: _loading ? null : () => _load(reason: 'manual_refresh'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: pageContent,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppSurfaceCard(
        child: AppStatePanel.loading(
          title: 'Đang tải hướng dẫn',
          message: 'Hệ thống đang lấy nội dung mới nhất từ runtime help.',
        ),
      );
    }

    if (_errorMessage != null) {
      return AppSurfaceCard(
        child: AppStatePanel.error(
          title: 'Chưa tải được hướng dẫn',
          message: _errorMessage,
          actionLabel: 'Thử lại',
          actionIcon: Icons.refresh_rounded,
          onAction: () => _load(reason: 'retry'),
        ),
      );
    }

    if (_selectedPage == null) {
      return const AppSurfaceCard(
        child: AppStatePanel.empty(
          title: 'Chưa có nội dung hướng dẫn',
          message:
              'Nội dung sẽ hiển thị khi runtime help có trang được xuất bản.',
          icon: Icons.menu_book_outlined,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 960;
        final navigationCard = _HelpNavigationCard(
          pages: _pages,
          selectedKey: _selectedKey,
          onSelectPage: _selectPage,
        );
        final contentCard = _HelpContentCard(
          page: _selectedPage!,
          parentTitle: helpPageParentTitle(_selectedPage!, _pages),
          markdown: _resolvedMarkdown(_selectedPage!),
          onLinkTap: _handleLink,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              navigationCard,
              const SizedBox(height: AppLayoutTokens.cardGap),
              contentCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 320, child: navigationCard),
            const SizedBox(width: AppLayoutTokens.cardGap),
            Expanded(child: contentCard),
          ],
        );
      },
    );
  }

  HelpContentPage? get _selectedPage {
    if (_selectedKey == null) return null;
    for (final page in _pages) {
      if (page.key == _selectedKey) return page;
    }
    return null;
  }

  HelpContentPage? _findPageByKey(String key) {
    for (final page in _pages) {
      if (page.key == key) return page;
    }
    return null;
  }

  HelpContentPage? _findPageByFileName(String fileName) {
    for (final page in _pages) {
      if (page.fileName == fileName) return page;
    }
    return null;
  }

  String _resolvedMarkdown(HelpContentPage page) {
    final assetBase = ApiConstants.publicBaseUri.replace(path: '/help/assets/');
    return page.markdown.replaceAllMapped(RegExp(r'\((assets/[^)]+)\)'), (
      match,
    ) {
      final relativePath = match.group(1)!.replaceFirst('assets/', '');
      final uri = assetBase.replace(path: '/help/assets/$relativePath');
      return '(${uri.toString()})';
    });
  }
}

class _HelpScreenHeader extends StatelessWidget {
  const _HelpScreenHeader({
    required this.loading,
    required this.pageCount,
    required this.updatedAt,
  });

  final bool loading;
  final int pageCount;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('help-screen-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kho nội dung hỗ trợ OpsHub', style: AppTextStyles.headingM),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppStatusChip(
                label: loading ? 'Đang đồng bộ' : '$pageCount trang',
                color: AppColors.primary,
              ),
              if (updatedAt != null)
                AppStatusChip(
                  label:
                      'Cập nhật ${DateFormat('HH:mm dd/MM').format(updatedAt!.toLocal())}',
                  color: AppColors.neutral700,
                ),
              const AppStatusChip(
                label: 'Nguồn runtime',
                color: AppColors.info,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpNavigationCard extends StatelessWidget {
  const _HelpNavigationCard({
    required this.pages,
    required this.selectedKey,
    required this.onSelectPage,
  });

  final List<HelpContentPage> pages;
  final String? selectedKey;
  final ValueChanged<HelpContentPage> onSelectPage;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mục lục', style: AppTextStyles.headingS),
          const SizedBox(height: 12),
          for (final page in pages) ...[
            _HelpNavigationItem(
              page: page,
              selected: page.key == selectedKey,
              depth: helpPageDepth(page, pages),
              onTap: () => onSelectPage(page),
            ),
            if (page != pages.last)
              const SizedBox(height: AppLayoutTokens.formInlineGap),
          ],
        ],
      ),
    );
  }
}

class _HelpNavigationItem extends StatelessWidget {
  const _HelpNavigationItem({
    required this.page,
    required this.selected,
    required this.depth,
    required this.onTap,
  });

  final HelpContentPage page;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('help-nav-item-${page.key}'),
      borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.24)
                : AppColors.borderOf(context),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: depth * 12),
              Icon(
                depth == 0
                    ? Icons.book_outlined
                    : Icons.subdirectory_arrow_right,
                color: selected ? AppColors.primary : AppColors.neutral700,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  page.title,
                  style: AppTextStyles.labelM.copyWith(
                    color: selected
                        ? AppColors.primaryOf(context)
                        : AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpContentCard extends StatelessWidget {
  const _HelpContentCard({
    required this.page,
    required this.parentTitle,
    required this.markdown,
    required this.onLinkTap,
  });

  final HelpContentPage page;
  final String? parentTitle;
  final String markdown;
  final Future<void> Function(String) onLinkTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(page.title, style: AppTextStyles.headingM),
          const SizedBox(height: 6),
          Text(
            parentTitle == null ? 'Trang gốc' : 'Thuộc mục $parentTitle',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          MarkdownBody(
            data: markdown,
            selectable: true,
            shrinkWrap: true,
            onTapLink: (text, href, title) {
              if (href == null) return;
              unawaited(onLinkTap(href));
            },
          ),
        ],
      ),
    );
  }
}
