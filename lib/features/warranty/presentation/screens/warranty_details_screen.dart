import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/warranty_provider.dart';

class WarrantyDetailsScreen extends StatefulWidget {
  final String receiptNumber;

  const WarrantyDetailsScreen({super.key, required this.receiptNumber});

  @override
  State<WarrantyDetailsScreen> createState() => _WarrantyDetailsScreenState();
}

class _WarrantyDetailsScreenState extends State<WarrantyDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDetails();
    });
  }

  Future<void> _loadDetails() async {
    final authProvider = context.read<AuthProvider>();
    final warrantyProvider = context.read<WarrantyProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isEmpty) return;

    await warrantyProvider.getWarrantyDetails(
      userEmail: userEmail,
      receiptNumber: widget.receiptNumber,
    );
  }

  Future<void> _downloadImage(String imageSource, int index) async {
    final isRemoteImage = _isUrl(imageSource);
    await AppLogger.instance.info(
      'Warranty',
      'Warranty detail image download started',
      context: {
        'receiptNumber': widget.receiptNumber,
        'imageIndex': index,
        'source': isRemoteImage ? 'url' : 'base64',
      },
    );

    try {
      if (Platform.isAndroid) {
        final permission = await Permission.photos.status;
        if (!permission.isGranted) {
          final result = await Permission.photos.request();

          if (result.isDenied) {
            await AppLogger.instance.warn(
              'Warranty',
              'Warranty detail image download permission denied',
              context: {
                'receiptNumber': widget.receiptNumber,
                'imageIndex': index,
                'permanentlyDenied': false,
              },
            );
            if (mounted) _showPermissionGuide(isPermanentlyDenied: false);
            return;
          }

          if (result.isPermanentlyDenied) {
            await AppLogger.instance.warn(
              'Warranty',
              'Warranty detail image download permission denied',
              context: {
                'receiptNumber': widget.receiptNumber,
                'imageIndex': index,
                'permanentlyDenied': true,
              },
            );
            if (mounted) _showPermissionGuide(isPermanentlyDenied: true);
            return;
          }
        }
      }

      final bytes = isRemoteImage
          ? await _downloadRemoteImageBytes(imageSource)
          : base64Decode(imageSource);
      final directory = await _downloadDirectory();
      if (directory == null) {
        throw Exception('Download directory unavailable');
      }

      final extension = _imageExtension(imageSource);
      final fileName =
          '${widget.receiptNumber}_${index + 1}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await AppLogger.instance.info(
        'Warranty',
        'Warranty detail image download succeeded',
        context: {
          'receiptNumber': widget.receiptNumber,
          'imageIndex': index,
          'fileName': fileName,
          'byteCount': bytes.length,
        },
      );

      if (mounted) {
        _showSnackBar(
          'Đã lưu vào: ${file.path}',
          backgroundColor: AppColors.success,
        );
      }
    } catch (error) {
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty detail image download failed',
        context: {
          'receiptNumber': widget.receiptNumber,
          'imageIndex': index,
          'message': error.toString(),
        },
      );
      if (mounted) {
        _showSnackBar(
          'Chưa tải được ảnh. Vui lòng thử lại.',
          backgroundColor: AppColors.error,
        );
      }
    }
  }

  Future<List<int>> _downloadRemoteImageBytes(String imageSource) async {
    final response = await http.get(Uri.parse(imageSource));
    if (response.statusCode != 200) {
      throw Exception('Image request failed with ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<Directory?> _downloadDirectory() async {
    if (Platform.isAndroid) return Directory('/storage/emulated/0/Download');
    if (Platform.isIOS) return getApplicationDocumentsDirectory();
    return getDownloadsDirectory();
  }

  String _imageExtension(String imageSource) {
    if (!_isUrl(imageSource)) return 'jpg';
    final path = Uri.parse(imageSource).path.toLowerCase();
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.jpeg') || path.endsWith('.jpg')) return 'jpg';
    if (path.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  void _showSnackBar(String message, {required Color backgroundColor}) {
    AppToast.show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showPermissionGuide({required bool isPermanentlyDenied}) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isPermanentlyDenied ? Icons.settings : Icons.info_outline,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              const Expanded(child: Text('Cần cấp quyền lưu ảnh')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPermanentlyDenied
                      ? 'Bạn đã từ chối quyền lưu ảnh. Vui lòng vào Cài đặt để cấp quyền.'
                      : 'Ứng dụng cần quyền truy cập bộ nhớ để lưu ảnh vào máy.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppLayoutTokens.formFieldGap),
                Text(
                  'Hướng dẫn cấp quyền:',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPermissionStep(
                  '1',
                  isPermanentlyDenied
                      ? 'Vào Cài đặt điện thoại'
                      : 'Chọn "Cho phép" khi ứng dụng yêu cầu',
                ),
                if (isPermanentlyDenied) ...[
                  _buildPermissionStep('2', 'Tìm và chọn "PhongVu OpsHub"'),
                  _buildPermissionStep('3', 'Chọn "Quyền" hoặc "Permissions"'),
                  _buildPermissionStep(
                    '4',
                    'Bật quyền "Ảnh và video" hoặc "Photos and videos"',
                  ),
                  const SizedBox(height: AppLayoutTokens.cardGap),
                  _PhonePermissionGuide(),
                ],
              ],
            ),
          ),
          actions: [
            if (isPermanentlyDenied)
              AppDialogSecondaryButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                icon: Icons.settings_outlined,
                label: 'Mở Cài đặt',
              ),
            AppDialogCancelButton(
              onPressed: () => Navigator.of(context).pop(),
              label: isPermanentlyDenied ? 'Đóng' : 'OK',
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: Text(
                  number,
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.surface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          Expanded(child: Text(text, style: AppTextStyles.bodyS)),
        ],
      ),
    );
  }

  bool _isUrl(String source) {
    return source.startsWith('http://') || source.startsWith('https://');
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Chưa có';

    try {
      DateTime? dateTime;
      try {
        dateTime = DateTime.parse(dateString);
      } catch (_) {
        final parts = dateString.split('/');
        if (parts.length == 3) {
          dateTime = DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      }

      return dateTime == null
          ? dateString
          : DateFormat('dd/MM/yyyy').format(dateTime);
    } catch (_) {
      return dateString;
    }
  }

  void _viewImage(String imageSource, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ImageViewScreen(
          imageSource: imageSource,
          title: '${widget.receiptNumber} - Ảnh ${index + 1}',
          onDownload: () => _downloadImage(imageSource, index),
        ),
      ),
    );
  }

  void _returnToLookup() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    context.go('/check-warranty');
  }

  List<String> _extractImages(Map<String, dynamic> details) {
    final images = <String>[];
    final listValue = details['images'];
    if (listValue is List) {
      for (final item in listValue) {
        final image = item?.toString();
        if (image != null && image.isNotEmpty) images.add(image);
      }
      return images;
    }

    var imageIndex = 0;
    while (details.containsKey('image$imageIndex')) {
      final image = details['image$imageIndex']?.toString();
      if (image != null && image.isNotEmpty) images.add(image);
      imageIndex++;
    }
    return images;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvasOf(context),
      child: Consumer<WarrantyProvider>(
        builder: (context, warrantyProvider, _) {
          final details = warrantyProvider.currentDetails;
          final images = details == null ? <String>[] : _extractImages(details);
          final imageCount = details == null ? null : images.length;

          if (warrantyProvider.isLoading) {
            return AppResponsiveScrollView(
              onRefresh: _loadDetails,
              refreshLogSource: 'Warranty',
              refreshLogContext: () => {
                'receiptNumber': widget.receiptNumber,
                'state': 'loading',
              },
              child: _WarrantyDetailLayout(
                receiptNumber: widget.receiptNumber,
                imageCount: imageCount,
                onBack: _returnToLookup,
                child: const AppSurfaceCard(
                  child: AppStatePanel.loading(
                    title: 'Đang tải chi tiết biên nhận',
                  ),
                ),
              ),
            );
          }

          if (warrantyProvider.errorMessage != null) {
            return AppResponsiveScrollView(
              onRefresh: _loadDetails,
              refreshLogSource: 'Warranty',
              refreshLogContext: () => {
                'receiptNumber': widget.receiptNumber,
                'state': 'error',
              },
              child: _WarrantyDetailLayout(
                receiptNumber: widget.receiptNumber,
                imageCount: imageCount,
                onBack: _returnToLookup,
                child: AppSurfaceCard(
                  child: AppStatePanel.error(
                    title: 'Chưa tải được chi tiết biên nhận',
                    message: warrantyProvider.errorMessage!,
                    actionLabel: 'Thử lại',
                    actionIcon: Icons.refresh_rounded,
                    onAction: _loadDetails,
                  ),
                ),
              ),
            );
          }

          if (details == null) {
            return AppResponsiveScrollView(
              onRefresh: _loadDetails,
              refreshLogSource: 'Warranty',
              refreshLogContext: () => {
                'receiptNumber': widget.receiptNumber,
                'state': 'empty',
              },
              child: _WarrantyDetailLayout(
                receiptNumber: widget.receiptNumber,
                imageCount: imageCount,
                onBack: _returnToLookup,
                child: const AppSurfaceCard(
                  child: AppStatePanel.empty(
                    title: 'Không có dữ liệu biên nhận',
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
              ),
            );
          }

          return AppResponsiveScrollView(
            onRefresh: _loadDetails,
            refreshLogSource: 'Warranty',
            refreshLogContext: () => {
              'receiptNumber': widget.receiptNumber,
              'state': 'details',
              'imageCount': imageCount,
            },
            child: _WarrantyDetailLayout(
              receiptNumber: widget.receiptNumber,
              imageCount: imageCount,
              onBack: _returnToLookup,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReceiptInfoCard(details: details, formatDate: _formatDate),
                  const SizedBox(height: AppLayoutTokens.formSectionGap),
                  _ImageSection(
                    images: images,
                    onView: _viewImage,
                    onDownload: _downloadImage,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WarrantyDetailLayout extends StatelessWidget {
  final String receiptNumber;
  final int? imageCount;
  final VoidCallback onBack;
  final Widget child;

  const _WarrantyDetailLayout({
    required this.receiptNumber,
    required this.imageCount,
    required this.onBack,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WarrantyDetailHeader(
          receiptNumber: receiptNumber,
          imageCount: imageCount,
          onBack: onBack,
        ),
        const SizedBox(height: AppLayoutTokens.sectionGap),
        child,
      ],
    );
  }
}

class _WarrantyDetailHeader extends StatelessWidget {
  final String receiptNumber;
  final int? imageCount;
  final VoidCallback onBack;

  const _WarrantyDetailHeader({
    required this.receiptNumber,
    required this.imageCount,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final imageLabel = imageCount == null ? 'Đang tải ảnh' : '$imageCount ảnh';
    return AppSurfaceCard(
      key: const Key('warranty-detail-header'),
      backgroundColor: AppColors.infoSurface,
      borderColor: AppColors.info.withValues(alpha: 0.22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.tabletBreakpoint;
          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.info,
            ),
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chi tiết biên nhận', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                receiptNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.neutral600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppLayoutTokens.cardGap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: imageLabel,
                    color: imageCount == null || imageCount == 0
                        ? AppColors.neutral700
                        : AppColors.info,
                    backgroundColor: AppColors.surface,
                  ),
                  const AppStatusChip(
                    label: 'Có thể tải ảnh',
                    color: AppColors.info,
                    backgroundColor: AppColors.surface,
                  ),
                ],
              ),
            ],
          );
          final backButton = SizedBox(
            width: 132,
            child: AppSecondaryButton(
              onPressed: onBack,
              icon: Icons.arrow_back_rounded,
              label: 'Quay lại',
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [icon, const Spacer(), backButton]),
                const SizedBox(height: 14),
                content,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(child: content),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              backButton,
            ],
          );
        },
      ),
    );
  }
}

class _PhonePermissionGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _PhonePermissionHeader(),
            SizedBox(height: 8),
            _PhoneGuideRow(
              brand: 'Samsung',
              path: 'Cài đặt -> Ứng dụng -> PhongVu OpsHub -> Quyền',
            ),
            _PhoneGuideRow(
              brand: 'Xiaomi/Redmi',
              path:
                  'Cài đặt -> Ứng dụng -> Quản lý ứng dụng -> PhongVu OpsHub -> Quyền ứng dụng',
            ),
            _PhoneGuideRow(
              brand: 'Oppo/Realme',
              path:
                  'Cài đặt -> Quyền riêng tư -> Trình quản lý quyền -> PhongVu OpsHub',
            ),
            _PhoneGuideRow(
              brand: 'Vivo',
              path:
                  'Cài đặt -> Ứng dụng và thông báo -> Quản lý ứng dụng -> PhongVu OpsHub -> Quyền',
            ),
          ],
        ),
      ),
    );
  }
}

class _PhonePermissionHeader extends StatelessWidget {
  const _PhonePermissionHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.phone_android, size: 16, color: AppColors.info),
        const SizedBox(width: 6),
        Text(
          'Tùy theo hãng điện thoại:',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.info,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PhoneGuideRow extends StatelessWidget {
  final String brand;
  final String path;

  const _PhoneGuideRow({required this.brand, required this.path});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '- ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.info,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                children: [
                  TextSpan(text: '$brand: ', style: AppTextStyles.labelM),
                  TextSpan(text: path),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptInfoCard extends StatelessWidget {
  final Map<String, dynamic> details;
  final String Function(String? value) formatDate;

  const _ReceiptInfoCard({required this.details, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Thông tin biên nhận', style: AppTextStyles.headingM),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          _InfoRow(
            label: 'Biên nhận:',
            value: details['receipt']?.toString() ?? 'Chưa có',
          ),
          _InfoRow(
            label: 'Người lưu:',
            value: details['user']?.toString() ?? 'Chưa có',
          ),
          _InfoRow(
            label: 'Ngày lưu:',
            value: formatDate(details['date']?.toString()),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTextStyles.bodyM.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyM.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSection extends StatelessWidget {
  final List<String> images;
  final void Function(String imageSource, int index) onView;
  final void Function(String imageSource, int index) onDownload;

  const _ImageSection({
    required this.images,
    required this.onView,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Không có hình ảnh',
        icon: Icons.image_not_supported_outlined,
        compact: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hình ảnh (${images.length})', style: AppTextStyles.headingS),
        const SizedBox(height: AppLayoutTokens.cardGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = _columnsForWidth(constraints.maxWidth);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: AppLayoutTokens.cardGap,
                mainAxisSpacing: AppLayoutTokens.cardGap,
                childAspectRatio: 1,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) => _ImageCard(
                imageSource: images[index],
                index: index,
                onTap: () => onView(images[index], index),
                onDownload: () => onDownload(images[index], index),
              ),
            );
          },
        ),
      ],
    );
  }

  int _columnsForWidth(double width) {
    if (width >= 980) return 4;
    if (width >= 680) return 3;
    return 2;
  }
}

class _ImageCard extends StatelessWidget {
  final String imageSource;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _ImageCard({
    required this.imageSource,
    required this.index,
    required this.onTap,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: Key('warranty-image-card-$index'),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ImageContent(imageSource: imageSource, index: index),
            Positioned(
              top: 8,
              right: 8,
              child: _ImageBadge(text: '${index + 1}'),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: IconButton(
                tooltip: 'Tải về',
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded),
                color: AppColors.surface,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.neutral900.withValues(alpha: 0.62),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageBadge extends StatelessWidget {
  final String text;

  const _ImageBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.neutral900.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: AppTextStyles.labelS.copyWith(color: AppColors.surface),
        ),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final String imageSource;
  final int? index;

  const _ImageContent({required this.imageSource, this.index});

  bool _isUrl(String source) {
    return source.startsWith('http://') || source.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    if (_isUrl(imageSource)) {
      return CachedNetworkImage(
        imageUrl: imageSource,
        fit: BoxFit.cover,
        memCacheWidth: 800,
        memCacheHeight: 800,
        maxWidthDiskCache: 1000,
        maxHeightDiskCache: 1000,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) =>
            _BrokenImagePlaceholder(index: index),
      );
    }

    try {
      return Image.memory(
        base64Decode(imageSource),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _BrokenImagePlaceholder(index: index),
      );
    } catch (_) {
      return _BrokenImagePlaceholder(index: index);
    }
  }
}

class _BrokenImagePlaceholder extends StatelessWidget {
  final int? index;

  const _BrokenImagePlaceholder({this.index});

  @override
  Widget build(BuildContext context) {
    final text = index == null
        ? 'Chưa hiển thị được ảnh'
        : 'Ảnh ${index! + 1} chưa tải được';
    return ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkNeutral100
          : AppColors.neutral100,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 48, color: AppColors.error),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageViewScreen extends StatelessWidget {
  final String imageSource;
  final String title;
  final VoidCallback onDownload;

  const _ImageViewScreen({
    required this.imageSource,
    required this.title,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.neutral900,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(child: _ImageContent(imageSource: imageSource)),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              right: 12,
              child: _ImageViewerToolbar(
                title: title,
                onBack: () => Navigator.of(context).maybePop(),
                onDownload: onDownload,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageViewerToolbar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onDownload;

  const _ImageViewerToolbar({
    required this.title,
    required this.onBack,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: AppColors.surface.withValues(alpha: 0.18));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.neutral900.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.fromBorderSide(border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Quay lại',
              color: AppColors.surface,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.surface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Tải về',
              color: AppColors.surface,
            ),
          ],
        ),
      ),
    );
  }
}
