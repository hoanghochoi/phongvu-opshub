import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
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
      maxWidth: widget.embeddedInShell ? 1126 : 1120,
      padding: widget.embeddedInShell
          ? null
          : _publicContentPadding(MediaQuery.sizeOf(context).width),
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
            onReload: widget.embeddedInShell && !_loading
                ? () => _load(reason: 'manual_refresh')
                : null,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          _buildBody(),
        ],
      ),
    );
    if (widget.embeddedInShell) return pageContent;
    return Scaffold(
      body: Column(
        children: [
          _HelpPublicTopBar(
            loading: _loading,
            onBack: _handleBack,
            onRefresh: () => _load(reason: 'manual_refresh'),
          ),
          Expanded(child: pageContent),
        ],
      ),
    );
  }

  EdgeInsets _publicContentPadding(double width) {
    if (width >= AppLayoutTokens.desktopBreakpoint) {
      return const EdgeInsets.fromLTRB(32, 32, 32, 24);
    }
    return const EdgeInsets.all(16);
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
          actionIcon: PhosphorIconsRegular.arrowCounterClockwise,
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
          icon: PhosphorIconsRegular.bookOpen,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final shellTablet =
            widget.embeddedInShell &&
            viewportWidth >= AppLayoutTokens.compactBreakpoint &&
            viewportWidth < AppLayoutTokens.tabletBreakpoint;
        final sideBySide =
            shellTablet || viewportWidth >= AppLayoutTokens.desktopBreakpoint;
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
          minHeight: widget.embeddedInShell
              ? (viewportWidth < AppLayoutTokens.compactBreakpoint
                    ? 455
                    : viewportWidth < AppLayoutTokens.tabletBreakpoint
                    ? 312
                    : 329)
              : viewportWidth < AppLayoutTokens.compactBreakpoint
              ? 409
              : 329,
        );

        if (!sideBySide) {
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
            SizedBox(width: shellTablet ? 210 : 300, child: navigationCard),
            const SizedBox(width: 16),
            if (shellTablet)
              SizedBox(width: 480, child: contentCard)
            else
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

class _HelpPublicTopBar extends StatelessWidget {
  const _HelpPublicTopBar({
    required this.loading,
    required this.onBack,
    required this.onRefresh,
  });

  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          border: Border(
            bottom: BorderSide(color: AppColors.borderOf(context)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              AppIconAction(
                tooltip: 'Quay lại',
                icon: PhosphorIconsRegular.arrowLeft,
                onPressed: onBack,
                backgroundColor: AppColors.secondarySurfaceOf(context),
                foregroundColor: AppColors.secondaryOf(context),
              ),
              const SizedBox(width: 12),
              Text('Hướng dẫn sử dụng', style: AppTextStyles.labelL),
              const Spacer(),
              AppIconAction(
                tooltip: 'Tải lại hướng dẫn',
                icon: PhosphorIconsRegular.arrowCounterClockwise,
                onPressed: loading ? null : onRefresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpScreenHeader extends StatelessWidget {
  const _HelpScreenHeader({
    required this.loading,
    required this.pageCount,
    required this.updatedAt,
    required this.onReload,
  });

  final bool loading;
  final int pageCount;
  final DateTime? updatedAt;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('help-screen-header'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Kho nội dung hỗ trợ OpsHub',
                    style: AppTextStyles.pageTitle,
                  ),
                ),
                if (onReload != null)
                  AppIconAction(
                    tooltip: 'Tải lại hướng dẫn',
                    icon: PhosphorIconsRegular.arrowCounterClockwise,
                    onPressed: onReload,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: loading ? 93 : 67,
                child: AppStatusChip(
                  label: loading ? 'Đang đồng bộ' : '$pageCount trang',
                  color: AppColors.primaryOf(context),
                  backgroundColor: AppColors.primarySurfaceOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                ),
              ),
              if (updatedAt != null)
                SizedBox(
                  width: 155,
                  child: AppStatusChip(
                    label:
                        'Cập nhật ${DateFormat('HH:mm dd/MM').format(updatedAt!.toLocal())}',
                    color: AppColors.textSecondaryOf(context),
                    backgroundColor: AppColors.statusSurfaceOf(
                      context,
                      'neutral',
                    ),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                  ),
                ),
              SizedBox(
                width: 109,
                child: AppStatusChip(
                  label: 'Nguồn runtime',
                  color: AppColors.infoOf(context),
                  backgroundColor: AppColors.infoSurfaceOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                ),
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
      key: const Key('help-navigation-card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mục lục', style: AppTextStyles.pageTitle),
          const SizedBox(height: 10),
          for (final page in pages) ...[
            _HelpNavigationItem(
              page: page,
              selected: page.key == selectedKey,
              depth: helpPageDepth(page, pages),
              onTap: () => onSelectPage(page),
            ),
            if (page != pages.last) const SizedBox(height: 10),
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
              ? AppColors.primarySurfaceOf(context)
              : AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          border: Border.all(
            color: selected
                ? AppColors.primaryOf(context).withValues(alpha: 0.24)
                : AppColors.borderOf(context),
          ),
        ),
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: depth * 12),
                Icon(
                  PhosphorIconsRegular.bookOpen,
                  size: 20,
                  color: selected
                      ? AppColors.primaryOf(context)
                      : AppColors.textSecondaryOf(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    page.title,
                    style: AppTextStyles.labelM.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
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
    required this.minHeight,
  });

  final HelpContentPage page;
  final String? parentTitle;
  final String markdown;
  final Future<void> Function(String) onLinkTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: AppSurfaceCard(
        key: const Key('help-content-card'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(page.title, style: AppTextStyles.pageTitle),
            const SizedBox(height: 12),
            Text(
              parentTitle == null ? 'Trang gốc' : 'Thuộc mục $parentTitle',
              style: AppTextStyles.bodyS.copyWith(
                height: 18 / 13,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 12),
            MarkdownBody(
              data: markdown,
              selectable: true,
              shrinkWrap: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    h1: AppTextStyles.pageTitle,
                    h2: AppTextStyles.pageTitle,
                    h3: AppTextStyles.pageTitle,
                    p: AppTextStyles.bodyM.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                    a: AppTextStyles.labelM.copyWith(
                      color: AppColors.primaryOf(context),
                    ),
                    listBullet: AppTextStyles.bodyM.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
              onTapLink: (text, href, title) {
                if (href == null) return;
                unawaited(onLinkTap(href));
              },
            ),
          ],
        ),
      ),
    );
  }
}
