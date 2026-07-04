import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/warranty_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart'
    show showBarcodeScanner;
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/validators.dart';

class WarrantyScreen extends StatefulWidget {
  const WarrantyScreen({super.key});

  @override
  State<WarrantyScreen> createState() => _WarrantyScreenState();
}

class _WarrantyScreenState extends State<WarrantyScreen> {
  static const int _maxImages = 20;

  final _formKey = GlobalKey<FormState>();
  final _receiptController = TextEditingController();
  final _receiptFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _images = [];
  String? _receiptError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _receiptFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _receiptController.dispose();
    _receiptFocusNode.dispose();
    super.dispose();
  }

  void _validateReceipt(String value) {
    setState(() {
      if (value.isEmpty) {
        _receiptError = null;
      } else {
        if (!Validators.isValidWarrantyReceiptNumber(value)) {
          _receiptError = 'Sai định dạng. Ví dụ: CP01-J12345678 hoặc ST-123456';
        } else {
          _receiptError = null;
        }
      }
    });
  }

  Future<bool> _ensureImageCapacity(String source) async {
    if (_images.length < _maxImages) return true;
    await AppLogger.instance.warn(
      'WarrantyUpload',
      'Warranty image add blocked at limit',
      context: {
        'source': source,
        'imageCount': _images.length,
        'maxImages': _maxImages,
      },
    );
    if (mounted) {
      _showSnackBar(
        'Mỗi biên nhận đính kèm tối đa $_maxImages ảnh.',
        AppColors.warning,
      );
    }
    return false;
  }

  Future<void> _pickImage(ImageSource source) async {
    final sourceName = source == ImageSource.gallery ? 'gallery' : 'camera';
    if (!await _ensureImageCapacity(sourceName)) return;
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> selectedImages = await _picker.pickMultiImage();
        if (selectedImages.isNotEmpty) {
          final remaining = _maxImages - _images.length;
          final accepted = selectedImages.take(remaining).toList();
          setState(() {
            _images.addAll(accepted);
          });
          final truncated = selectedImages.length - accepted.length;
          await AppLogger.instance.info(
            'WarrantyUpload',
            'Warranty images picked',
            context: {
              'pickedCount': selectedImages.length,
              'acceptedCount': accepted.length,
              'truncatedCount': truncated,
              'totalCount': _images.length,
              'maxImages': _maxImages,
            },
          );
          if (truncated > 0 && mounted) {
            _showSnackBar(
              'Đã giữ $_maxImages ảnh đầu tiên theo giới hạn hệ thống.',
              AppColors.warning,
            );
          }
        }
      } else {
        final XFile? image = await _picker.pickImage(source: source);
        if (image != null) {
          setState(() {
            _images.add(image);
          });
          await AppLogger.instance.info(
            'WarrantyUpload',
            'Warranty photo captured',
            context: {'totalCount': _images.length, 'maxImages': _maxImages},
          );
        }
      }
    } catch (e, stackTrace) {
      await AppLogger.instance.error(
        'WarrantyUpload',
        'Warranty image picker failed',
        error: e,
        stackTrace: stackTrace,
        context: {
          'source': sourceName,
          'imageCount': _images.length,
          'maxImages': _maxImages,
        },
      );
      if (mounted) {
        _showSnackBar('Chưa thêm được ảnh. Vui lòng thử lại.', AppColors.error);
      }
    }
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await showBarcodeScanner(context);
      if (result != null && mounted) {
        _receiptController.text = result;
        _validateReceipt(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa quét được mã. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Chụp ảnh'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveWarranty() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_images.isEmpty) {
      _showSnackBar('Vui lòng chọn ít nhất 1 hình ảnh', AppColors.warning);
      return;
    }

    if (_images.length > _maxImages) {
      await AppLogger.instance.warn(
        'WarrantyUpload',
        'Warranty save blocked by image limit',
        context: {'imageCount': _images.length, 'maxImages': _maxImages},
      );
      _showSnackBar(
        'Mỗi biên nhận đính kèm tối đa $_maxImages ảnh.',
        AppColors.warning,
      );
      return;
    }

    final warrantyProvider = context.read<WarrantyProvider>();
    final authProvider = context.read<AuthProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn cần đăng nhập lại để lưu biên nhận.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final List<File> imageFiles = _images
        .map((xFile) => File(xFile.path))
        .toList();

    final success = await warrantyProvider.saveWarranty(
      userEmail: userEmail,
      receiptNumber: _receiptController.text.trim().toUpperCase(),
      images: imageFiles,
    );

    if (mounted) {
      if (success) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 64,
            ),
            title: const Text('Đã lưu biên nhận'),
            content: const Text('Ảnh đã được lưu vào biên nhận này.'),
            actions: [
              AppDialogConfirmButton(
                onPressed: () => Navigator.of(context).pop(),
                label: 'Xác nhận',
              ),
            ],
          ),
        );
        if (mounted) {
          _receiptController.clear();
          setState(() {
            _images.clear();
            _receiptError = null;
          });
        }
      } else {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error, color: AppColors.error, size: 64),
            title: const Text('Chưa lưu được biên nhận'),
            content: Text(
              warrantyProvider.errorMessage ??
                  'Vui lòng kiểm tra lại và thử lại.',
            ),
            actions: [
              AppDialogConfirmButton(
                onPressed: () => Navigator.of(context).pop(),
                label: 'Xác nhận',
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveScrollView(
      maxWidth: AppLayoutTokens.formMaxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WarrantyUploadHeader(
            receipt: _receiptController.text.trim(),
            imageCount: _images.length,
            maxImages: _maxImages,
          ),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          AppSurfaceCard(
            key: const Key('warranty-upload-form-card'),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormTextInput(
                    controller: _receiptController,
                    focusNode: _receiptFocusNode,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: _validateReceipt,
                    label: 'Số biên nhận / mã sửa chữa',
                    hintText: 'CPxx-Jxxxxxxxx hoặc ST-123456',
                    icon: Icons.receipt_long,
                    errorText: _receiptError,
                    suffixIcon: AppIconAction(
                      icon: Icons.qr_code_scanner,
                      onPressed: _scanBarcode,
                      tooltip: 'Quét mã',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng nhập số biên nhận';
                      }
                      return _receiptError;
                    },
                  ),
                  const SizedBox(height: 24),
                  _ImageSectionHeader(
                    count: _images.length,
                    maxImages: _maxImages,
                  ),
                  const SizedBox(height: AppLayoutTokens.formInlineGap),
                  AppSecondaryButton(
                    onPressed: _images.length >= _maxImages
                        ? null
                        : _showImageSourceDialog,
                    icon: Icons.add_photo_alternate,
                    label: 'Thêm hình ảnh',
                  ),
                  const SizedBox(height: AppLayoutTokens.formFieldGap),
                  if (_images.isNotEmpty)
                    _ImageGrid(images: _images, onRemove: _removeImage),
                  const SizedBox(height: 32),
                  Consumer<WarrantyProvider>(
                    builder: (context, warrantyProvider, child) {
                      return AppPrimaryButton(
                        onPressed: _saveWarranty,
                        icon: Icons.save_outlined,
                        label: 'Lưu',
                        isLoading: warrantyProvider.isLoading,
                        loadingLabel: 'Đang lưu...',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarrantyUploadHeader extends StatelessWidget {
  final String receipt;
  final int imageCount;
  final int maxImages;

  const _WarrantyUploadHeader({
    required this.receipt,
    required this.imageCount,
    required this.maxImages,
  });

  @override
  Widget build(BuildContext context) {
    final receiptLabel = receipt.isEmpty ? 'Chưa nhập biên nhận' : receipt;
    return AppSurfaceCard(
      key: const Key('warranty-upload-header'),
      backgroundColor: AppColors.successSurface,
      borderColor: AppColors.success.withValues(alpha: 0.22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.tabletBreakpoint;
          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(
              Icons.add_photo_alternate_rounded,
              color: AppColors.success,
            ),
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lưu hình ảnh bảo hành', style: AppTextStyles.headingM),
              const SizedBox(height: AppLayoutTokens.cardGap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: receiptLabel,
                    color: receipt.isEmpty
                        ? AppColors.neutral700
                        : AppColors.success,
                    backgroundColor: AppColors.surface,
                  ),
                  AppStatusChip(
                    key: const Key('warranty-image-count-chip'),
                    label: '$imageCount/$maxImages ảnh',
                    color: imageCount == 0
                        ? AppColors.neutral700
                        : AppColors.success,
                    backgroundColor: AppColors.surface,
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [icon, const SizedBox(height: 14), content],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _ImageSectionHeader extends StatelessWidget {
  final int count;
  final int maxImages;

  const _ImageSectionHeader({required this.count, required this.maxImages});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('Hình ảnh', style: AppTextStyles.headingS)),
        AppStatusChip(
          label: '$count/$maxImages',
          color: count >= maxImages ? AppColors.warning : AppColors.neutral700,
          backgroundColor: count >= maxImages
              ? AppColors.warningSurface
              : AppColors.neutral100,
        ),
      ],
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<XFile> images;
  final void Function(int index) onRemove;

  const _ImageGrid({required this.images, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
              child: Image.file(
                File(images[index].path),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.neutral900.withValues(alpha: 0.60),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.surface,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
