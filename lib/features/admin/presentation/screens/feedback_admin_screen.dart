import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/private_media_headers.dart';
import '../../data/feedback_display_content.dart';

typedef FeedbackAdminLoader = Future<List<Map<String, dynamic>>> Function();

class FeedbackAdminScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final FeedbackAdminLoader? loader;

  const FeedbackAdminScreen({super.key, this.apiClient, this.loader});

  @override
  State<FeedbackAdminScreen> createState() => _FeedbackAdminScreenState();
}

class _FeedbackAdminScreenState extends State<FeedbackAdminScreen> {
  late final ApiClient _apiClient;
  late final FeedbackAdminLoader _loader;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    _loader = widget.loader ?? _loadFromApi;
    _load();
  }

  Future<List<Map<String, dynamic>>> _loadFromApi() async {
    final response = await _apiClient.get(ApiConstants.adminFeedbackEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'FeedbackAdmin',
      'Feedback admin list load started',
    );
    try {
      final items = await _loader();
      final displayContents = items
          .map(
            (item) => FeedbackDisplayContent.fromRaw(
              item['content']?.toString() ?? '',
            ),
          )
          .toList(growable: false);
      final imageUrlCount = displayContents.fold<int>(
        0,
        (count, content) => count + content.imageUrls.length,
      );
      final feedbackWithImagesCount = displayContents
          .where((content) => content.imageUrls.isNotEmpty)
          .length;
      if (!mounted) return;
      setState(() => _items = items);
      await AppLogger.instance.info(
        'FeedbackAdmin',
        'Feedback admin list load succeeded',
        context: {
          'count': items.length,
          'feedbackWithImagesCount': feedbackWithImagesCount,
          'imageUrlCount': imageUrlCount,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FeedbackAdmin',
        'Feedback admin list load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        setState(() => _errorMessage = 'Không tải được danh sách góp ý');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _FeedbackMetrics.fromItems(_items);
    return AppResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FeedbackAdminHeader(
            loading: _loading,
            feedbackCount: _items.length,
            feedbackWithImagesCount: metrics.feedbackWithImagesCount,
            imageUrlCount: metrics.imageUrlCount,
            onRefresh: _loading ? null : _load,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppListSkeleton(itemCount: 6, itemHeight: 108);
    }

    if (_errorMessage != null) {
      return AppStatePanel.error(
        title: _errorMessage!,
        message: 'Kiểm tra kết nối rồi thử tải lại danh sách góp ý.',
        actionLabel: 'Thử tải lại',
        actionIcon: Icons.refresh,
        onAction: _load,
      );
    }

    if (_items.isEmpty) {
      return AppStatePanel.empty(
        title: 'Chưa có góp ý',
        message: 'Góp ý mới từ nhân viên sẽ xuất hiện tại đây.',
        icon: Icons.lightbulb_outline_rounded,
        actionLabel: 'Tải lại',
        actionIcon: Icons.refresh,
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('feedback-admin-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppLayoutTokens.formInlineGap),
        itemBuilder: (context, index) => _FeedbackCard(item: _items[index]),
      ),
    );
  }
}

class _FeedbackAdminHeader extends StatelessWidget {
  final bool loading;
  final int feedbackCount;
  final int feedbackWithImagesCount;
  final int imageUrlCount;
  final VoidCallback? onRefresh;

  const _FeedbackAdminHeader({
    required this.loading,
    required this.feedbackCount,
    required this.feedbackWithImagesCount,
    required this.imageUrlCount,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('feedback-admin-header'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Danh sách góp ý',
                style: AppTextStyles.headingM.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Theo dõi góp ý, lỗi vận hành và ảnh minh họa từ nhân viên.',
                style: AppTextStyles.bodyM.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              Wrap(
                spacing: AppLayoutTokens.formInlineGap,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: loading ? 'Đang tải góp ý' : '$feedbackCount góp ý',
                    color: AppColors.primary,
                  ),
                  AppStatusChip(
                    label: '$feedbackWithImagesCount có ảnh',
                    color: AppColors.info,
                  ),
                  AppStatusChip(
                    label: '$imageUrlCount ảnh',
                    color: AppColors.neutral700,
                  ),
                  const AppStatusChip(
                    label: 'Chỉ Super Admin',
                    color: AppColors.neutral700,
                  ),
                ],
              ),
            ],
          );
          final refreshButton = AppIconAction(
            onPressed: onRefresh,
            icon: Icons.refresh,
            tooltip: 'Tải lại danh sách góp ý',
          );

          if (isCompact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: AppLayoutTokens.formInlineGap),
                refreshButton,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              refreshButton,
            ],
          );
        },
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _FeedbackCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final user = item['user'] is Map<String, dynamic>
        ? item['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final email = user['email']?.toString();
    final name = user['firstName']?.toString();
    final content = item['content']?.toString() ?? '';
    final displayContent = FeedbackDisplayContent.fromRaw(content);
    final rating = _ratingText(item['rating']);
    final createdAt = _formatCreatedAt(item['createdAt']);
    final module = _functionNameFromBody(displayContent.body);
    final sender = name?.isNotEmpty == true
        ? name!
        : email?.isNotEmpty == true
        ? email!
        : 'Không rõ người gửi';

    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FeedbackIcon(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayContent.body,
                  maxLines: displayContent.imageUrls.isEmpty ? 4 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyM.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (module != null)
                      AppStatusChip(
                        label: module,
                        color: AppColors.primary,
                        maxWidth: 180,
                      ),
                    if (rating != null)
                      AppStatusChip(label: rating, color: AppColors.warning),
                    if (displayContent.imageUrls.isNotEmpty)
                      AppStatusChip(
                        label: '${displayContent.imageUrls.length} ảnh',
                        color: AppColors.info,
                      ),
                    if (createdAt != null)
                      AppStatusChip(
                        label: createdAt,
                        color: AppColors.neutral700,
                        maxWidth: 160,
                      ),
                    if (email?.isNotEmpty == true)
                      AppStatusChip(
                        label: email!,
                        color: AppColors.neutral700,
                        maxWidth: 220,
                      ),
                  ],
                ),
                if (displayContent.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: AppLayoutTokens.formInlineGap),
                  _FeedbackImageStrip(imageUrls: displayContent.imageUrls),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackIcon extends StatelessWidget {
  const _FeedbackIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Icon(
        Icons.lightbulb_outline_rounded,
        color: AppColors.info,
        size: 22,
      ),
    );
  }
}

class _FeedbackMetrics {
  final int feedbackWithImagesCount;
  final int imageUrlCount;

  const _FeedbackMetrics({
    required this.feedbackWithImagesCount,
    required this.imageUrlCount,
  });

  factory _FeedbackMetrics.fromItems(List<Map<String, dynamic>> items) {
    final displayContents = items
        .map(
          (item) =>
              FeedbackDisplayContent.fromRaw(item['content']?.toString() ?? ''),
        )
        .toList(growable: false);
    return _FeedbackMetrics(
      feedbackWithImagesCount: displayContents
          .where((content) => content.imageUrls.isNotEmpty)
          .length,
      imageUrlCount: displayContents.fold<int>(
        0,
        (count, content) => count + content.imageUrls.length,
      ),
    );
  }
}

String? _ratingText(dynamic rating) {
  final value = int.tryParse(rating?.toString() ?? '');
  if (value == null) return null;
  return '$value/5 điểm';
}

String? _formatCreatedAt(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  final date = DateTime.tryParse(text);
  if (date == null) return text;
  return DateFormat('HH:mm dd/MM/yyyy').format(date.toLocal());
}

String? _functionNameFromBody(String body) {
  for (final line in body.replaceAll('\r\n', '\n').split('\n')) {
    final match = RegExp(
      r'^Chức năng\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line.trim());
    final value = match?.group(1)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

class _FeedbackImageStrip extends StatelessWidget {
  final List<String> imageUrls;

  const _FeedbackImageStrip({required this.imageUrls});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _FeedbackImageThumbnail(
          imageUrl: imageUrls[index],
          imageIndex: index,
        ),
      ),
    );
  }
}

class _FeedbackImageThumbnail extends StatelessWidget {
  final String imageUrl;
  final int imageIndex;

  const _FeedbackImageThumbnail({
    required this.imageUrl,
    required this.imageIndex,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadius.sm);
    return Semantics(
      label: 'Ảnh góp ý ${imageIndex + 1}',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showFeedbackImagePreview(
            context,
            imageUrl: imageUrl,
            imageIndex: imageIndex,
          ),
          child: SizedBox(
            width: 92,
            height: 92,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              httpHeaders: privateMediaHeaders(imageUrl),
              fit: BoxFit.cover,
              memCacheWidth: 360,
              memCacheHeight: 360,
              maxWidthDiskCache: 600,
              maxHeightDiskCache: 600,
              placeholder: (context, url) => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) {
                unawaited(
                  AppLogger.instance.warn(
                    'FeedbackAdmin',
                    'Feedback admin image thumbnail load failed',
                    context: {
                      'imageIndex': imageIndex,
                      'urlLength': url.length,
                      'protectedMedia': isProtectedPrivateMediaUrl(url),
                      'errorType': error.runtimeType.toString(),
                    },
                  ),
                );
                return const _FeedbackImageErrorPlaceholder();
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showFeedbackImagePreview(
  BuildContext context, {
  required String imageUrl,
  required int imageIndex,
}) async {
  await AppLogger.instance.info(
    'FeedbackAdmin',
    'Feedback admin image preview opened',
    context: {'imageIndex': imageIndex, 'urlLength': imageUrl.length},
  );
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: math.min(size.width * 0.9, 960),
          height: math.min(size.height * 0.82, 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ảnh góp ý ${imageIndex + 1}',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    httpHeaders: privateMediaHeaders(imageUrl),
                    fit: BoxFit.contain,
                    placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) {
                      unawaited(
                        AppLogger.instance.warn(
                          'FeedbackAdmin',
                          'Feedback admin image preview load failed',
                          context: {
                            'imageIndex': imageIndex,
                            'urlLength': url.length,
                            'protectedMedia': isProtectedPrivateMediaUrl(url),
                            'errorType': error.runtimeType.toString(),
                          },
                        ),
                      );
                      return const _FeedbackImageErrorPlaceholder();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _FeedbackImageErrorPlaceholder extends StatelessWidget {
  const _FeedbackImageErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 6),
            Text(
              'Chưa tải được ảnh',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
