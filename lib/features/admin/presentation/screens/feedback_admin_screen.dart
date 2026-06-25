import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../data/feedback_display_content.dart';

class FeedbackAdminScreen extends StatefulWidget {
  const FeedbackAdminScreen({super.key});

  @override
  State<FeedbackAdminScreen> createState() => _FeedbackAdminScreenState();
}

class _FeedbackAdminScreenState extends State<FeedbackAdminScreen> {
  final _apiClient = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'FeedbackAdmin',
      'Feedback admin list load started',
    );
    try {
      final response = await _apiClient.get(ApiConstants.adminFeedbackEndpoint);
      final data = jsonDecode(response.body) as List<dynamic>;
      final items = data.whereType<Map<String, dynamic>>().toList(
        growable: false,
      );
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
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa tải được danh sách góp ý')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientHeader(
        title: 'Danh sách góp ý',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: AppResponsiveContent(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppLayoutTokens.formInlineGap),
                itemBuilder: (context, index) =>
                    _FeedbackTile(item: _items[index]),
              ),
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _FeedbackTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final user = item['user'] is Map<String, dynamic>
        ? item['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final email = user['email']?.toString() ?? 'unknown';
    final name = user['firstName']?.toString();
    final content = item['content']?.toString() ?? '';
    final displayContent = FeedbackDisplayContent.fromRaw(content);
    final rating = item['rating']?.toString();
    final createdAt = item['createdAt']?.toString();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: const Icon(Icons.lightbulb_outline_rounded),
        title: Text(
          name?.isNotEmpty == true ? '$name • $email' : email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rating?.isNotEmpty == true) Text('Rating: $rating'),
            Text(
              displayContent.body,
              maxLines: displayContent.imageUrls.isEmpty ? 4 : 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (displayContent.imageUrls.isNotEmpty) ...[
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              _FeedbackImageStrip(imageUrls: displayContent.imageUrls),
            ],
            if (createdAt?.isNotEmpty == true)
              Text(createdAt!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
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
    final borderRadius = BorderRadius.circular(8);
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
                      'error': error.toString(),
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
                    fit: BoxFit.contain,
                    placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) =>
                        const _FeedbackImageErrorPlaceholder(),
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
