import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/feedback_upload_contract.dart';

import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_inputs.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const int _maxImages = 20;

  final _formKey = GlobalKey<FormState>();
  final _functionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppLogger.instance.info(
        'Feedback',
        'Suggestion screen opened',
        context: {'maxImages': _maxImages},
      ),
    );
  }

  @override
  void dispose() {
    _functionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<bool> _ensureImageCapacity(String source) async {
    if (_images.length < _maxImages) return true;
    await AppLogger.instance.warn(
      'Feedback',
      'Suggestion image add blocked at limit',
      context: {'source': source, 'imageCount': _images.length},
    );
    if (mounted) {
      _showSnackBar(
        'Mỗi góp ý đính kèm tối đa $_maxImages ảnh.',
        color: AppColors.warning,
      );
    }
    return false;
  }

  Future<void> _pickImage() async {
    if (!await _ensureImageCapacity('gallery')) return;
    try {
      final selectedImages = await _picker.pickMultiImage();
      if (selectedImages.isEmpty || !mounted) return;

      final remaining = _maxImages - _images.length;
      final accepted = selectedImages.take(remaining).toList(growable: false);
      setState(() {
        _images.addAll(accepted.map((image) => File(image.path)));
      });
      final truncated = selectedImages.length - accepted.length;
      await AppLogger.instance.info(
        'Feedback',
        'Suggestion images picked',
        context: {
          'pickedCount': selectedImages.length,
          'acceptedCount': accepted.length,
          'truncatedCount': truncated,
          'totalCount': _images.length,
        },
      );
      if (truncated > 0 && mounted) {
        _showSnackBar(
          'Đã giữ $_maxImages ảnh đầu tiên theo giới hạn hệ thống.',
          color: AppColors.warning,
        );
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'Feedback',
        'Suggestion image picker failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showSnackBar(
          'Chưa chọn được ảnh. Vui lòng thử lại.',
          color: AppColors.error,
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    if (!await _ensureImageCapacity('camera')) return;
    try {
      final image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null || !mounted) return;
      setState(() => _images.add(File(image.path)));
      await AppLogger.instance.info(
        'Feedback',
        'Suggestion photo captured',
        context: {'totalCount': _images.length},
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'Feedback',
        'Suggestion camera capture failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showSnackBar(
          'Chưa chụp được ảnh. Vui lòng thử lại.',
          color: AppColors.error,
        );
      }
    }
  }

  Future<void> _removeImage(int index) async {
    if (index < 0 || index >= _images.length) return;
    setState(() => _images.removeAt(index));
    await AppLogger.instance.info(
      'Feedback',
      'Suggestion image removed',
      context: {'removedIndex': index, 'totalCount': _images.length},
    );
  }

  void _showImageSourceDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thêm ảnh minh họa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_pickImage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Chụp ảnh mới'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_takePhoto());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) {
      await AppLogger.instance.warn(
        'Feedback',
        'Suggestion submit blocked by validation',
        context: {
          'functionLength': _functionController.text.trim().length,
          'descriptionLength': _descriptionController.text.trim().length,
          'imageCount': _images.length,
        },
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final startedAt = DateTime.now();

    try {
      final user = context.read<AuthProvider>().user;
      await AppLogger.instance.info(
        'Feedback',
        'Suggestion submit started',
        context: {
          'userId': user?.id,
          'storeId': user?.storeId,
          'functionLength': _functionController.text.trim().length,
          'descriptionLength': _descriptionController.text.trim().length,
          'imageCount': _images.length,
        },
      );

      final files = <http.MultipartFile>[];
      for (var i = 0; i < _images.length; i++) {
        files.add(
          await buildFeedbackImageMultipartFile(image: _images[i], index: i),
        );
      }

      final response = await ApiClient().postMultipart(
        ApiConstants.feedbackEndpoint,
        fields: buildFeedbackMultipartFields(
          functionName: _functionController.text,
          description: _descriptionController.text,
        ),
        files: files,
        timeout: ApiConstants.uploadTimeout,
      );
      final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

      if (response.statusCode == 200 || response.statusCode == 201) {
        await AppLogger.instance.info(
          'Feedback',
          'Suggestion submit succeeded',
          context: {
            'userId': user?.id,
            'storeId': user?.storeId,
            'imageCount': _images.length,
            'statusCode': response.statusCode,
            'durationMs': durationMs,
          },
        );
        if (!mounted) return;
        _showSnackBar(
          'Đã gửi góp ý. Cảm ơn bạn đã giúp OpsHub tốt hơn!',
          color: AppColors.success,
        );
        _functionController.clear();
        _descriptionController.clear();
        setState(_images.clear);
        Navigator.of(context).pop();
        return;
      }

      await AppLogger.instance.warn(
        'Feedback',
        'Suggestion submit returned non-success',
        context: {
          'statusCode': response.statusCode,
          'imageCount': _images.length,
          'durationMs': durationMs,
        },
      );
      if (mounted) {
        _showSnackBar(
          'Chưa gửi được góp ý. Vui lòng thử lại.',
          color: AppColors.error,
        );
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'Feedback',
        'Suggestion submit failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'imageCount': _images.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        _showSnackBar(
          'Chưa gửi được góp ý. Kiểm tra kết nối rồi thử lại.',
          color: AppColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, {required Color color}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Góp ý', showBack: true),
      body: Form(
        key: _formKey,
        child: AppResponsiveScrollView(
          maxWidth: AppLayoutTokens.formMaxWidth,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: AppFormColumn(
            spacing: AppLayoutTokens.formSectionGap,
            children: [
              const AppStatusBanner(
                icon: Icons.lightbulb_outline_rounded,
                title: 'Cùng cải thiện OpsHub',
                message:
                    'Chia sẻ đề xuất, điểm chưa thuận tiện hoặc lỗi bạn gặp '
                    'trong lúc làm việc.',
                tone: AppStateTone.info,
              ),
              AppFormTextInput(
                key: const ValueKey('suggestion-function-field'),
                controller: _functionController,
                enabled: !_isSubmitting,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                label: 'Chức năng liên quan',
                hintText: 'Ví dụ: FIFO, VietQR, Sao kê, Tiền vào, BH / SC...',
                helperText: 'Cho biết khu vực bạn đang sử dụng.',
                icon: Icons.category_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập chức năng liên quan';
                  }
                  return null;
                },
              ),
              AppFormTextInput(
                key: const ValueKey('suggestion-description-field'),
                controller: _descriptionController,
                enabled: !_isSubmitting,
                minLines: 5,
                maxLines: 8,
                maxLength: 5000,
                label: 'Nội dung góp ý',
                hintText:
                    'Bạn mong muốn thay đổi điều gì? Nếu là lỗi, hãy mô tả '
                    'các bước đã thực hiện.',
                alignLabelWithHint: true,
                icon: Icons.edit_note_rounded,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập nội dung góp ý';
                  }
                  return null;
                },
              ),
              _SuggestionImagesCard(
                images: _images,
                maxImages: _maxImages,
                isSubmitting: _isSubmitting,
                onAdd: _showImageSourceDialog,
                onRemove: (index) => unawaited(_removeImage(index)),
              ),
              AppPrimaryButton(
                key: const ValueKey('submit-suggestion-button'),
                onPressed: _submitFeedback,
                icon: Icons.send_rounded,
                label: 'Gửi góp ý',
                isLoading: _isSubmitting,
                loadingLabel: 'Đang gửi...',
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionImagesCard extends StatelessWidget {
  final List<File> images;
  final int maxImages;
  final bool isSubmitting;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _SuggestionImagesCard({
    required this.images,
    required this.maxImages,
    required this.isSubmitting,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ảnh minh họa', style: AppTextStyles.labelM),
                    const SizedBox(height: 3),
                    Text(
                      'Không bắt buộc, tối đa $maxImages ảnh',
                      style: AppTextStyles.labelS.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              AppDialogSecondaryButton(
                onPressed: isSubmitting || images.length >= maxImages
                    ? null
                    : onAdd,
                icon: Icons.add_photo_alternate_outlined,
                label: 'Thêm ảnh',
              ),
            ],
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          if (images.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.neutral50,
                borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
                border: Border.all(color: AppColors.neutral200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.image_outlined,
                    color: AppColors.neutral400,
                    size: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Thêm ảnh khi hình ảnh giúp mô tả góp ý rõ hơn.',
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columnCount = constraints.maxWidth >= 600
                    ? 4
                    : constraints.maxWidth < 360
                    ? 2
                    : 3;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: images.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) => _SuggestionImageTile(
                    image: images[index],
                    index: index,
                    enabled: !isSubmitting,
                    onRemove: () => onRemove(index),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SuggestionImageTile extends StatelessWidget {
  final File image;
  final int index;
  final bool enabled;
  final VoidCallback onRemove;

  const _SuggestionImageTile({
    required this.image,
    required this.index,
    required this.enabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Ảnh góp ý ${index + 1}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            child: Image.file(
              image,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => ColoredBox(
                color: AppColors.neutral50,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.error,
                ),
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: Tooltip(
              message: 'Xóa ảnh ${index + 1}',
              child: Material(
                color: enabled ? AppColors.error : AppColors.neutral400,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: enabled ? onRemove : null,
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.surface,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
