import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_chips.dart';
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
        color: AppColors.warningOf(context),
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
          color: AppColors.warningOf(context),
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
          color: AppColors.errorOf(context),
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
          color: AppColors.errorOf(context),
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
              leading: Icon(PhosphorIconsRegular.images),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                unawaited(_pickImage());
              },
            ),
            ListTile(
              leading: Icon(PhosphorIconsRegular.camera),
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
          color: AppColors.successOf(context),
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
          color: AppColors.errorOf(context),
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
          color: AppColors.errorOf(context),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, {required Color color}) {
    AppToast.show(
      context,
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isWide = viewportWidth >= AppLayoutTokens.desktopBreakpoint;
    final horizontalPadding = isWide ? 32.0 : 16.0;
    final topPadding = isWide ? 32.0 : 18.0;
    final contentWidth = isWide ? 1126.0 : AppLayoutTokens.contentMaxWidth;
    return Form(
      key: _formKey,
      child: AppResponsiveScrollView(
        // Exact Figma shell geometry: wide content is 1126px inside 32px
        // gutters; compact/tablet/expanded uses the approved 343px form lane.
        maxWidth: contentWidth,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          24,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        onRefresh: AppRefreshCallbacks.noop,
        refreshLogSource: 'Feedback',
        refreshLogContext: () => {
          'functionLength': _functionController.text.trim().length,
          'descriptionLength': _descriptionController.text.trim().length,
          'imageCount': _images.length,
          'isSubmitting': _isSubmitting,
        },
        child: SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: isWide ? double.infinity : 343,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FeedbackHeader(
                    imageCount: _images.length,
                    maxImages: _maxImages,
                    isSubmitting: _isSubmitting,
                    showHeading: isWide,
                  ),
                  SizedBox(height: isWide ? 19 : 18),
                  _FeedbackFormCard(
                    functionController: _functionController,
                    descriptionController: _descriptionController,
                    images: _images,
                    maxImages: _maxImages,
                    isSubmitting: _isSubmitting,
                    isWide: isWide,
                    onAddImage: _showImageSourceDialog,
                    onRemoveImage: (index) => unawaited(_removeImage(index)),
                    onSubmit: _submitFeedback,
                  ),
                  const SizedBox(height: 80.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackHeader extends StatelessWidget {
  final int imageCount;
  final int maxImages;
  final bool isSubmitting;
  final bool showHeading;

  const _FeedbackHeader({
    required this.imageCount,
    required this.maxImages,
    required this.isSubmitting,
    required this.showHeading,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      AppStatusChip(
        label: isSubmitting ? 'Đang gửi' : 'Sẵn sàng gửi',
        color: isSubmitting
            ? AppColors.warningOf(context)
            : AppColors.infoOf(context),
        backgroundColor: AppColors.infoSurfaceOf(context),
      ),
      AppStatusChip(
        label: '$imageCount/$maxImages ảnh',
        color: imageCount >= maxImages
            ? AppColors.warningOf(context)
            : AppColors.infoOf(context),
        backgroundColor: AppColors.infoSurfaceOf(context),
      ),
      AppStatusChip(
        label: 'Tối đa 20 ảnh',
        color: AppColors.infoOf(context),
        backgroundColor: AppColors.infoSurfaceOf(context),
      ),
    ];
    return Column(
      key: const Key('feedback-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Text('Chia sẻ phản hồi', style: AppTextStyles.pageTitle),
          const SizedBox(height: 18),
          Text(
            'Chia sẻ đề xuất, điểm chưa thuận tiện hoặc lỗi bạn gặp '
            'trong lúc làm việc.',
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (showHeading)
          Wrap(spacing: 8, runSpacing: 8, children: chips)
        else
          SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: isSubmitting ? 71 : 93, child: chips[0]),
                const SizedBox(width: 8),
                SizedBox(width: 72, child: chips[1]),
                const SizedBox(width: 8),
                SizedBox(width: 98, child: chips[2]),
              ],
            ),
          ),
      ],
    );
  }
}

class _FeedbackFormCard extends StatelessWidget {
  final TextEditingController functionController;
  final TextEditingController descriptionController;
  final List<File> images;
  final int maxImages;
  final bool isSubmitting;
  final bool isWide;
  final VoidCallback onAddImage;
  final ValueChanged<int> onRemoveImage;
  final VoidCallback onSubmit;

  const _FeedbackFormCard({
    required this.functionController,
    required this.descriptionController,
    required this.images,
    required this.maxImages,
    required this.isSubmitting,
    required this.isWide,
    required this.onAddImage,
    required this.onRemoveImage,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final slotHeight = isWide ? 86.0 : 56.0;
    final extraRows = images.length <= 2 ? 0 : (images.length - 2 + 1) ~/ 2;
    final extraHeight = extraRows * (slotHeight + 8);
    final cardHeight = (isWide ? 590.0 : 552.0) + extraHeight;
    final fieldWidth = isWide ? null : 311.0;
    return AppSurfaceCard(
      key: const Key('feedback-form-card'),
      radius: AppRadius.cardFigma,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: cardHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 15,
              right: 15,
              top: 15,
              child: SizedBox(
                height: 102,
                width: fieldWidth,
                child: _FeedbackField(
                  key: const ValueKey('suggestion-function-field'),
                  controller: functionController,
                  enabled: !isSubmitting,
                  label: 'Chức năng liên quan',
                  hintText:
                      'Ví dụ: FIFO, VietQR, Sao kê, Tiền vào, Bảo hành...',
                  helperText: 'Tối đa 120 ký tự',
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng nhập chức năng liên quan'
                      : null,
                ),
              ),
            ),
            Positioned(
              left: 15,
              right: 15,
              top: 123,
              child: SizedBox(
                height: isWide ? 192 : 174,
                child: _FeedbackTextArea(
                  key: const ValueKey('suggestion-description-field'),
                  controller: descriptionController,
                  enabled: !isSubmitting,
                  label: 'Nội dung góp ý',
                  hintText:
                      'Bạn mong muốn thay đổi điều gì? Nếu là lỗi, hãy mô tả '
                      'các bước đã thực hiện.',
                  maxLength: 5000,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng nhập nội dung góp ý'
                      : null,
                ),
              ),
            ),
            Positioned(
              left: 15,
              right: 15,
              top: isWide ? 321 : 313,
              child: SizedBox(
                height: (isWide ? 176.0 : 150.0) + extraHeight,
                child: _SuggestionImagesCard(
                  images: images,
                  maxImages: maxImages,
                  isSubmitting: isSubmitting,
                  isWide: isWide,
                  extraRows: extraRows,
                  onAdd: onAddImage,
                  onRemove: onRemoveImage,
                ),
              ),
            ),
            Positioned(
              left: 15,
              right: 15,
              top: (isWide ? 517.0 : 479.0) + extraHeight,
              child: AppPrimaryButton(
                key: const ValueKey('submit-suggestion-button'),
                onPressed: onSubmit,
                label: 'Gửi góp ý',
                isLoading: isSubmitting,
                loadingLabel: 'Đang gửi...',
                size: AppButtonSize.medium,
                height: 48,
                radius: isWide ? 12 : 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String hintText;
  final String helperText;
  final int maxLength;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;

  const _FeedbackField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.hintText,
    required this.helperText,
    required this.maxLength,
    required this.validator,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTextStyles.labelM),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: AppFormTextInput(
            controller: controller,
            label: label,
            showLabel: false,
            enabled: enabled,
            maxLength: maxLength,
            textInputAction: textInputAction,
            validator: validator,
            hintText: hintText,
            dense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          helperText,
          style: AppTextStyles.bodyS.copyWith(
            height: 18 / 13,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }
}

class _FeedbackTextArea extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String hintText;
  final int maxLength;
  final FormFieldValidator<String>? validator;

  const _FeedbackTextArea({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.hintText,
    required this.maxLength,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Text(label, style: AppTextStyles.labelM),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 28,
              child: SizedBox(
                height: 120,
                child: AppFormTextInput(
                  controller: controller,
                  label: label,
                  showLabel: false,
                  enabled: enabled,
                  maxLength: maxLength,
                  minLines: 5,
                  maxLines: 5,
                  textAlignVertical: TextAlignVertical.top,
                  validator: validator,
                  hintText: hintText,
                  dense: true,
                  alignLabelWithHint: true,
                  counterText: '',
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 156,
              child: SizedBox(
                height: 36,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Mô tả tình huống, kết quả mong đợi và bước đã thử.',
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${value.text.length}/$maxLength',
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodyCompact.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuggestionImagesCard extends StatelessWidget {
  final List<File> images;
  final int maxImages;
  final bool isSubmitting;
  final bool isWide;
  final int extraRows;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _SuggestionImagesCard({
    required this.images,
    required this.maxImages,
    required this.isSubmitting,
    required this.isWide,
    required this.extraRows,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cardRadius = isWide ? 10.0 : 10.0;
    final slotHeight = isWide ? 86.0 : 56.0;
    return AppSurfaceCard(
      radius: cardRadius,
      padding: EdgeInsets.zero,
      backgroundColor: AppColors.cardOf(context),
      borderColor: AppColors.subtleBorderOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: isWide ? 73 : 81,
            child: Stack(
              children: [
                Positioned(
                  left: 11,
                  top: 9,
                  child: Text('Ảnh minh họa', style: AppTextStyles.labelM),
                ),
                Positioned(
                  left: 11,
                  top: 33,
                  child: Text(
                    'Không bắt buộc, tối đa $maxImages ảnh',
                    style: AppTextStyles.bodyCompact.copyWith(
                      color: AppColors.textMutedOf(context),
                    ),
                  ),
                ),
                Positioned(
                  right: 11,
                  top: 13,
                  child: SizedBox(
                    width: 104,
                    height: 48,
                    child: AppPrimaryButton(
                      onPressed: isSubmitting || images.length >= maxImages
                          ? null
                          : onAdd,
                      label: 'Thêm ảnh',
                      size: AppButtonSize.medium,
                      height: 48,
                      radius: isWide ? 12 : 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              children: [
                Expanded(
                  child: _FeedbackImageSlot(
                    image: images.isNotEmpty ? images.first : null,
                    label: 'Ảnh 1',
                    height: slotHeight,
                    index: 0,
                    enabled: !isSubmitting,
                    onRemove: images.isNotEmpty ? () => onRemove(0) : null,
                  ),
                ),
                SizedBox(width: isWide ? 8 : 8),
                Expanded(
                  child: _FeedbackImageSlot(
                    image: images.length > 1 ? images[1] : null,
                    label: 'Ảnh 2',
                    height: slotHeight,
                    index: 1,
                    enabled: !isSubmitting,
                    onRemove: images.length > 1 ? () => onRemove(1) : null,
                  ),
                ),
              ],
            ),
          ),
          for (var row = 0; row < extraRows; row++) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: [
                  Expanded(
                    child: _FeedbackImageSlot(
                      image: images[2 + row * 2],
                      label: 'Ảnh ${3 + row * 2}',
                      height: slotHeight,
                      index: 2 + row * 2,
                      enabled: !isSubmitting,
                      onRemove: () => onRemove(2 + row * 2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (2 + row * 2 + 1 < images.length)
                    Expanded(
                      child: _FeedbackImageSlot(
                        image: images[2 + row * 2 + 1],
                        label: 'Ảnh ${4 + row * 2}',
                        height: slotHeight,
                        index: 2 + row * 2 + 1,
                        enabled: !isSubmitting,
                        onRemove: () => onRemove(2 + row * 2 + 1),
                      ),
                    )
                  else
                    const Spacer(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackImageSlot extends StatelessWidget {
  final File? image;
  final String label;
  final double height;
  final int index;
  final bool enabled;
  final VoidCallback? onRemove;

  const _FeedbackImageSlot({
    required this.image,
    required this.label,
    required this.height,
    required this.index,
    required this.enabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final infoSurface = AppColors.infoSurfaceOf(context);
    final infoColor = AppColors.infoOf(context);
    return Semantics(
      image: image != null,
      label: 'Ảnh góp ý ${index + 1}',
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: infoSurface,
                borderRadius: AppRadius.allSm,
                border: Border.all(color: infoSurface),
              ),
              child: image == null
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, top: 15),
                        child: Text(
                          label,
                          style: AppTextStyles.labelS.copyWith(
                            color: infoColor,
                          ),
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: AppRadius.allSm,
                      child: Image.file(
                        image!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Icon(
                            PhosphorIconsRegular.image,
                            color: infoColor,
                          ),
                        ),
                      ),
                    ),
            ),
            if (onRemove != null)
              Positioned(
                top: 4,
                right: 4,
                child: Tooltip(
                  message: 'Xóa ảnh ${index + 1}',
                  child: Material(
                    color: enabled
                        ? AppColors.errorOf(context)
                        : AppColors.textMutedOf(context),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: enabled ? onRemove : null,
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          PhosphorIconsRegular.x,
                          color: AppColors.surface,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
