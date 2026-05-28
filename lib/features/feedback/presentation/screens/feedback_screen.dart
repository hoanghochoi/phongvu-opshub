import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _functionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _functionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _images.addAll(images.map((xFile) => File(xFile.path)));
        });
        await AppLogger.instance.info(
          'Feedback',
          'Feedback images picked',
          context: {'pickedCount': images.length, 'totalCount': _images.length},
        );
      }
    } catch (e) {
      await AppLogger.instance.error(
        'Feedback',
        'Pick images failed',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa chọn được ảnh. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _images.add(File(image.path));
        });
        await AppLogger.instance.info(
          'Feedback',
          'Feedback photo captured',
          context: {'totalCount': _images.length},
        );
      }
    } catch (e) {
      await AppLogger.instance.error('Feedback', 'Take photo failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa chụp được ảnh. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
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

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Chọn nguồn ảnh'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Thư viện ảnh'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Chụp ảnh'),
                onTap: () {
                  Navigator.of(context).pop();
                  _takePhoto();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final userEmail = authProvider.user?.email ?? '';
      await AppLogger.instance.info(
        'Feedback',
        'Feedback submit started',
        context: {
          'userEmail': userEmail,
          'functionLength': _functionController.text.trim().length,
          'descriptionLength': _descriptionController.text.trim().length,
          'imageCount': _images.length,
        },
      );

      final files = <http.MultipartFile>[];
      for (var i = 0; i < _images.length; i++) {
        files.add(
          await http.MultipartFile.fromPath(
            'images',
            _images[i].path,
            filename: 'feedback_$i.jpg',
          ),
        );
      }

      final response = await ApiClient().postMultipart(
        ApiConstants.feedbackEndpoint,
        fields: {
          'function': _functionController.text.trim(),
          'description': _descriptionController.text.trim(),
          'user_email': userEmail,
          'timestamp': DateTime.now().toIso8601String(),
        },
        files: files,
        timeout: ApiConstants.uploadTimeout,
      );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          await AppLogger.instance.info(
            'Feedback',
            'Feedback submit succeeded',
            context: {'userEmail': userEmail, 'imageCount': _images.length},
          );
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gửi phản hồi thành công! Cảm ơn bạn đã đóng góp.'),
              backgroundColor: Colors.green,
            ),
          );
          _functionController.clear();
          _descriptionController.clear();
          setState(() {
            _images.clear();
          });
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        } else {
          await AppLogger.instance.warn(
            'Feedback',
            'Feedback submit returned non-success',
            context: {'statusCode': response.statusCode},
          );
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Chưa gửi được phản hồi. Vui lòng thử lại.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      await AppLogger.instance.error(
        'Feedback',
        'Feedback submit failed',
        error: e,
        upload: true,
        context: {'imageCount': _images.length},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa gửi được phản hồi. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Phản hồi', showBack: true),
      body: Form(
        key: _formKey,
        child: AppResponsiveScrollView(
          maxWidth: AppLayoutTokens.formMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info card
              Card(
                color: Colors.blue.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Gửi phản hồi về lỗi hoặc góp ý cải thiện ứng dụng',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Function field
              Text(
                'Chức năng',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              TextFormField(
                controller: _functionController,
                decoration: const InputDecoration(
                  hintText: 'Ví dụ: Chat, Bảo hành, Đăng nhập...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập chức năng';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppLayoutTokens.formSectionGap),

              // Description field
              Text(
                'Mô tả',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  hintText: 'Mô tả chi tiết lỗi hoặc góp ý của bạn...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập mô tả';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppLayoutTokens.formSectionGap),

              // Images section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Hình ảnh (Tùy chọn)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isSubmitting ? null : _showImageSourceDialog,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text(
                      'Thêm ảnh',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),

              // Images grid
              if (_images.isEmpty)
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade50,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Chưa có hình ảnh',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nhấn "Thêm ảnh" để chọn',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_images[index], fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

              const SizedBox(height: 32),

              AppPrimaryButton(
                onPressed: _submitFeedback,
                icon: Icons.send_rounded,
                label: 'Gửi phản hồi',
                isLoading: _isSubmitting,
                loadingLabel: 'Đang gửi...',
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
