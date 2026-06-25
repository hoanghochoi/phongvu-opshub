import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/warranty_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/widgets/barcode_scanner_screen.dart'
    show BarcodeScannerScreen;
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
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
        Colors.orange,
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
              Colors.orange,
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
        _showSnackBar('Chưa thêm được ảnh. Vui lòng thử lại.', Colors.red);
      }
    }
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );
      if (result != null && mounted) {
        _receiptController.text = result;
        _validateReceipt(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa quét được mã. Vui lòng thử lại.'),
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
      _showSnackBar('Vui lòng chọn ít nhất 1 hình ảnh', Colors.orange);
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
        Colors.orange,
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
          backgroundColor: Colors.red,
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
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
            title: const Text('Đã lưu biên nhận'),
            content: const Text('Ảnh đã được lưu vào biên nhận này.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Xác nhận',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
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
            icon: const Icon(Icons.error, color: Colors.red, size: 64),
            title: const Text('Chưa lưu được biên nhận'),
            content: Text(
              warrantyProvider.errorMessage ??
                  'Vui lòng kiểm tra lại và thử lại.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Xác nhận',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Lưu hình ảnh BH/SC', showBack: true),
      body: SafeArea(
        child: AppResponsiveScrollView(
          maxWidth: AppLayoutTokens.formMaxWidth,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Số biên nhận
                TextFormField(
                  controller: _receiptController,
                  focusNode: _receiptFocusNode,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: _validateReceipt,
                  decoration: InputDecoration(
                    labelText: 'Số biên nhận / mã sửa chữa',
                    hintText: 'CPxx-Jxxxxxxxx hoặc ST-123456',
                    prefixIcon: const Icon(Icons.receipt_long),
                    border: const OutlineInputBorder(),
                    errorText: _receiptError,
                    suffixIcon: AppIconAction(
                      icon: Icons.qr_code_scanner,
                      onPressed: _scanBarcode,
                      tooltip: 'Quét mã',
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập số biên nhận';
                    }
                    // Return current error if exists
                    return _receiptError;
                  },
                ),
                const SizedBox(height: 24),

                // Hình ảnh section
                Text(
                  'Hình ảnh',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Tối đa $_maxImages ảnh',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),

                // Add image button
                AppSecondaryButton(
                  onPressed: _images.length >= _maxImages
                      ? null
                      : _showImageSourceDialog,
                  icon: Icons.add_photo_alternate,
                  label: 'Thêm hình ảnh',
                ),
                const SizedBox(height: AppLayoutTokens.formFieldGap),

                // Images grid
                if (_images.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_images[index].path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removeImage(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                const SizedBox(height: 32),

                // Save button
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
      ),
    );
  }
}
