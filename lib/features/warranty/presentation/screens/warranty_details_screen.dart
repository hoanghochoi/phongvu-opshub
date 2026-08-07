import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
import '../../../../core/network/private_media_headers.dart';
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

    if (userEmail.isEmpty) {
      await AppLogger.instance.warn(
        'WarrantyDetails',
        'Warranty detail load skipped because no authenticated user is available',
        context: {'receiptLength': widget.receiptNumber.length},
      );
      return;
    }

    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'WarrantyDetails',
      'Warranty detail load started',
      context: {'receiptLength': widget.receiptNumber.length},
    );
    final succeeded = await warrantyProvider.getWarrantyDetails(
      userEmail: userEmail,
      receiptNumber: widget.receiptNumber,
    );
    final details = warrantyProvider.currentDetails;
    final logContext = {
      'receiptLength': widget.receiptNumber.length,
      'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      'imageCount': details == null ? 0 : _extractImages(details).length,
    };
    if (succeeded) {
      await AppLogger.instance.info(
        'WarrantyDetails',
        'Warranty detail load succeeded',
        context: logContext,
      );
      return;
    }
    await AppLogger.instance.warn(
      'WarrantyDetails',
      'Warranty detail load failed',
      context: logContext,
    );
  }

  Future<void> _downloadImage(String imageSource, int index) async {
    final isRemoteImage = _isUrl(imageSource);
    await AppLogger.instance.info(
      'Warranty',
      'Warranty detail image download started',
      context: {
        'receiptLength': widget.receiptNumber.length,
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
                'receiptLength': widget.receiptNumber.length,
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
                'receiptLength': widget.receiptNumber.length,
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
          'receiptLength': widget.receiptNumber.length,
          'imageIndex': index,
          'extension': extension,
          'byteCount': bytes.length,
        },
      );

      if (mounted) {
        _showSnackBar(
          'Đã lưu ảnh vào thư mục Tải xuống.',
          backgroundColor: AppColors.successOf(context),
        );
      }
    } catch (error) {
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty detail image download failed',
        context: {
          'receiptLength': widget.receiptNumber.length,
          'imageIndex': index,
          'errorType': error.runtimeType.toString(),
        },
      );
      if (mounted) {
        _showSnackBar(
          'Chưa tải được ảnh. Vui lòng thử lại.',
          backgroundColor: AppColors.errorOf(context),
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
                isPermanentlyDenied
                    ? PhosphorIconsRegular.gear
                    : PhosphorIconsRegular.info,
                color: AppColors.warningOf(context),
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
                icon: PhosphorIconsRegular.gear,
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
            decoration: BoxDecoration(
              color: AppColors.warningOf(context),
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: Text(
                  number,
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.primaryForegroundOf(context),
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
    unawaited(
      AppLogger.instance.info(
        'WarrantyDetails',
        'Warranty image viewer opened',
        context: {
          'receiptLength': widget.receiptNumber.length,
          'imageIndex': index,
          'source': _isUrl(imageSource) ? 'url' : 'base64',
        },
      ),
    );
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
      unawaited(
        AppLogger.instance.info(
          'WarrantyDetails',
          'Warranty detail returned through navigator history',
        ),
      );
      navigator.maybePop();
      return;
    }
    unawaited(
      AppLogger.instance.info(
        'WarrantyDetails',
        'Warranty detail returned through the lookup route fallback',
      ),
    );
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

  Widget _detailPage({
    required bool isWide,
    required int? imageCount,
    required Widget child,
    required double contentGap,
    required String state,
  }) {
    final pagePadding = isWide
        ? const EdgeInsets.fromLTRB(32, 32, 32, 24)
        : const EdgeInsets.fromLTRB(16, 12, 16, 16);
    return AppResponsiveScrollView(
      maxWidth: double.infinity,
      padding: pagePadding,
      onRefresh: _loadDetails,
      refreshLogSource: 'Warranty',
      refreshLogContext: () => {
        'receiptLength': widget.receiptNumber.length,
        'state': state,
        if (imageCount != null) 'imageCount': imageCount,
      },
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWide ? double.infinity : 343),
          child: _WarrantyDetailLayout(
            receiptNumber: widget.receiptNumber,
            imageCount: imageCount,
            isWide: isWide,
            contentGap: contentGap,
            onBack: _returnToLookup,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isWide = viewportWidth >= AppLayoutTokens.desktopBreakpoint;
    final hasCompactStateAuthority =
        viewportWidth < AppLayoutTokens.compactBreakpoint;
    return ColoredBox(
      color: AppColors.canvasOf(context),
      child: Consumer<WarrantyProvider>(
        builder: (context, warrantyProvider, _) {
          final details = warrantyProvider.currentDetails;
          final images = details == null ? <String>[] : _extractImages(details);
          final imageCount = details == null ? null : images.length;

          if (warrantyProvider.isLoading) {
            return _detailPage(
              isWide: isWide,
              imageCount: imageCount,
              contentGap: hasCompactStateAuthority ? 90 : 24,
              state: 'loading',
              child: SizedBox(
                key: const Key('warranty-detail-loading'),
                child: const AppSurfaceCard(
                  padding: EdgeInsets.zero,
                  child: AppStatePanel.loading(
                    title: 'Đang tải chi tiết biên nhận',
                    message: 'Hệ thống đang lấy thông tin và danh sách ảnh.',
                    compact: true,
                  ),
                ),
              ),
            );
          }

          if (warrantyProvider.errorMessage != null) {
            return _detailPage(
              isWide: isWide,
              imageCount: imageCount,
              contentGap: hasCompactStateAuthority ? 90 : 24,
              state: 'error',
              child: SizedBox(
                key: const Key('warranty-detail-error'),
                child: AppSurfaceCard(
                  padding: EdgeInsets.zero,
                  child: AppStatePanel.error(
                    title: 'Chưa tải được chi tiết biên nhận',
                    message: 'Kiểm tra kết nối rồi thử lại.',
                    actionLabel: 'Thử lại',
                    actionIcon: PhosphorIconsRegular.arrowCounterClockwise,
                    onAction: _loadDetails,
                    compact: hasCompactStateAuthority,
                  ),
                ),
              ),
            );
          }

          if (details == null) {
            return _detailPage(
              isWide: isWide,
              imageCount: imageCount,
              contentGap: hasCompactStateAuthority ? 90 : 24,
              state: 'empty',
              child: SizedBox(
                key: const Key('warranty-detail-empty'),
                child: AppSurfaceCard(
                  padding: EdgeInsets.zero,
                  child: AppStatePanel.empty(
                    title: 'Không có dữ liệu biên nhận',
                    message:
                        'Biên nhận có thể đã bị xóa hoặc không thuộc phạm vi của bạn.',
                    icon: PhosphorIconsRegular.receipt,
                    actionLabel: 'Quay lại',
                    actionIcon: PhosphorIconsRegular.arrowLeft,
                    onAction: _returnToLookup,
                    compact: hasCompactStateAuthority,
                  ),
                ),
              ),
            );
          }

          return _detailPage(
            isWide: isWide,
            imageCount: imageCount,
            contentGap: 24,
            state: 'details',
            child: _WarrantyDetailContent(
              isWide: isWide,
              details: details,
              images: images,
              formatDate: _formatDate,
              onView: _viewImage,
              onDownload: _downloadImage,
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
  final bool isWide;
  final double contentGap;
  final VoidCallback onBack;
  final Widget child;

  const _WarrantyDetailLayout({
    required this.receiptNumber,
    required this.imageCount,
    required this.isWide,
    required this.contentGap,
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
          isWide: isWide,
          onBack: onBack,
        ),
        SizedBox(height: contentGap),
        child,
      ],
    );
  }
}

class _WarrantyDetailHeader extends StatelessWidget {
  final String receiptNumber;
  final int? imageCount;
  final bool isWide;
  final VoidCallback onBack;

  const _WarrantyDetailHeader({
    required this.receiptNumber,
    required this.imageCount,
    required this.isWide,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final imageLabel = imageCount == null
        ? 'Đang tải ảnh'
        : '$imageCount hình ảnh';
    final chips = Wrap(
      key: const Key('warranty-detail-chips'),
      spacing: 8,
      runSpacing: 8,
      children: [
        AppStatusChip(
          label: imageLabel,
          color: imageCount == null || imageCount == 0
              ? AppColors.neutral700Of(context)
              : AppColors.infoOf(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        AppStatusChip(
          label: 'Có thể tải ảnh',
          color: AppColors.infoOf(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ],
    );
    final backButton = SizedBox(
      key: const Key('warranty-detail-back'),
      width: isWide ? 140 : 120,
      child: AppPrimaryButton(
        onPressed: onBack,
        label: 'Quay lại',
        size: AppButtonSize.medium,
      ),
    );

    return Column(
      key: const Key('warranty-detail-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isWide) ...[
          SizedBox(
            height: 26,
            child: Text('Chi tiết biên nhận', style: AppTextStyles.headingS),
          ),
          const SizedBox(height: 18),
          Text(
            receiptNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 20 / 13,
            ),
          ),
          SizedBox(
            height: 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: chips,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: backButton,
                ),
              ],
            ),
          ),
        ] else
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: chips,
                  ),
                ),
                backButton,
              ],
            ),
          ),
      ],
    );
  }
}

class _PhonePermissionGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.infoSurfaceOf(context),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(
          color: AppColors.infoOf(context).withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PhonePermissionHeader(),
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
        Icon(
          PhosphorIconsRegular.deviceMobile,
          size: 16,
          color: AppColors.infoOf(context),
        ),
        const SizedBox(width: 6),
        Text(
          'Tùy theo hãng điện thoại:',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.infoOf(context),
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
              color: AppColors.infoOf(context),
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

class _WarrantyDetailContent extends StatelessWidget {
  final bool isWide;
  final Map<String, dynamic> details;
  final List<String> images;
  final String Function(String? value) formatDate;
  final void Function(String imageSource, int index) onView;
  final void Function(String imageSource, int index) onDownload;

  const _WarrantyDetailContent({
    required this.isWide,
    required this.details,
    required this.images,
    required this.formatDate,
    required this.onView,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final receiptInfo = _ReceiptInfoCard(
      details: details,
      formatDate: formatDate,
      isWide: isWide,
    );
    final gallery = _ImageSection(
      images: images,
      isWide: isWide,
      onView: onView,
      onDownload: onDownload,
    );
    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [receiptInfo, const SizedBox(height: 16), gallery],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 399.6, child: receiptInfo),
        const SizedBox(width: 16),
        Expanded(child: gallery),
      ],
    );
  }
}

class _ReceiptInfoCard extends StatelessWidget {
  final Map<String, dynamic> details;
  final String Function(String? value) formatDate;
  final bool isWide;

  const _ReceiptInfoCard({
    required this.details,
    required this.formatDate,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    final metadataStyle = AppTextStyles.bodyS.copyWith(height: 20 / 13);
    return SizedBox(
      key: const Key('warranty-detail-receipt-info'),
      height: isWide ? 190 : 156,
      child: AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thông tin biên nhận', style: AppTextStyles.labelL),
            const SizedBox(height: 12),
            Text(
              'Biên nhận: ${details['receipt']?.toString() ?? 'Chưa có'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metadataStyle,
            ),
            Text(
              'Người lưu: ${details['user']?.toString() ?? 'Chưa có'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metadataStyle,
            ),
            Text(
              'Ngày lưu: ${formatDate(details['date']?.toString())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metadataStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSection extends StatelessWidget {
  final List<String> images;
  final bool isWide;
  final void Function(String imageSource, int index) onView;
  final void Function(String imageSource, int index) onDownload;

  const _ImageSection({
    required this.images,
    required this.isWide,
    required this.onView,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Không có hình ảnh',
        icon: PhosphorIconsRegular.imageBroken,
        compact: true,
      );
    }

    final columns = isWide ? 3 : 2;
    final itemHeight = isWide ? 138.0 : 108.0;
    final rowCount = (images.length / columns).ceil();
    final gridHeight =
        (rowCount * itemHeight) + (rowCount > 1 ? (rowCount - 1) * 10 : 0);
    final contentHeight = 52 + gridHeight + 8;
    final cardHeight = isWide
        ? contentHeight.clamp(360, double.infinity).toDouble()
        : contentHeight.clamp(286, double.infinity).toDouble();

    return SizedBox(
      key: const Key('warranty-detail-gallery'),
      height: cardHeight,
      child: AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hình ảnh (${images.length})', style: AppTextStyles.labelL),
            const SizedBox(height: 18),
            SizedBox(
              height: gridHeight,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: itemHeight,
                ),
                itemCount: images.length,
                itemBuilder: (context, index) => _ImageCard(
                  imageSource: images[index],
                  index: index,
                  onTap: () => onView(images[index], index),
                  onDownload: () => onDownload(images[index], index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
                icon: const Icon(PhosphorIconsRegular.downloadSimple),
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
        httpHeaders: privateMediaHeaders(imageSource),
        imageRenderMethodForWeb: privateMediaImageRenderMethodForWeb(
          imageSource,
        ),
        fit: BoxFit.cover,
        memCacheWidth: 800,
        memCacheHeight: 800,
        maxWidthDiskCache: 1000,
        maxHeightDiskCache: 1000,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) {
          unawaited(
            AppLogger.instance.warn(
              'WarrantyDetails',
              'Warranty image load failed',
              context: {
                'imageIndex': index,
                'protectedMedia': isProtectedPrivateMediaUrl(url),
                'urlLength': url.length,
                'errorType': error.runtimeType.toString(),
              },
            ),
          );
          return _BrokenImagePlaceholder(index: index);
        },
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
      color: AppColors.neutral100Of(context),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsRegular.imageBroken,
              size: 48,
              color: AppColors.errorOf(context),
            ),
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
              icon: const Icon(PhosphorIconsRegular.arrowLeft),
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
              icon: const Icon(PhosphorIconsRegular.downloadSimple),
              tooltip: 'Tải về',
              color: AppColors.surface,
            ),
          ],
        ),
      ),
    );
  }
}
