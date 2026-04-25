import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/warranty_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/widgets/barcode_scanner_screen.dart' show BarcodeScannerScreen;
import '../../../../app/widgets/gradient_header.dart';

class WarrantyScreen extends StatefulWidget {
  const WarrantyScreen({super.key});

  @override
  State<WarrantyScreen> createState() => _WarrantyScreenState();
}

class _WarrantyScreenState extends State<WarrantyScreen> {
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
        final receiptRegex = RegExp(r'^CP\d{2}-J\d{8}$', caseSensitive: false);
        if (!receiptRegex.hasMatch(value.trim().toUpperCase())) {
          _receiptError = 'Sai định dạng. Ví dụ: CP01-J12345678';
        } else {
          _receiptError = null;
        }
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> selectedImages = await _picker.pickMultiImage();
        if (selectedImages.isNotEmpty) {
          setState(() { _images.addAll(selectedImages); });
        }
      } else {
        final XFile? image = await _picker.pickImage(source: source);
        if (image != null) {
          setState(() { _images.add(image); });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi chọn ảnh: $e'), backgroundColor: Colors.red),
        );
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi quét mã: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() { _images.removeAt(index); });
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
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveWarranty() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất 1 hình ảnh'), backgroundColor: Colors.orange),
      );
      return;
    }

    final warrantyProvider = context.read<WarrantyProvider>();
    final authProvider = context.read<AuthProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy thông tin người dùng'), backgroundColor: Colors.red),
      );
      return;
    }

    final List<File> imageFiles = _images.map((xFile) => File(xFile.path)).toList();

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
            title: const Text('Thành công'),
            content: const Text('Lưu biên nhận thành công!'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Xác nhận'))],
          ),
        );
        if (mounted) {
          _receiptController.clear();
          setState(() { _images.clear(); _receiptError = null; });
        }
      } else {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error, color: Colors.red, size: 64),
            title: const Text('Thất bại'),
            content: Text(warrantyProvider.errorMessage ?? 'Lưu không thành công'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Xác nhận'))],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Lưu hình ảnh BH/SC', showBack: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
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
                    labelText: 'Số biên nhận',
                    hintText: 'CPxx-Jxxxxxxxx',
                    prefixIcon: const Icon(Icons.receipt_long),
                    border: const OutlineInputBorder(),
                    errorText: _receiptError,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
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
                const SizedBox(height: 12),

                // Add image button
                OutlinedButton.icon(
                  onPressed: _showImageSourceDialog,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Thêm hình ảnh'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),

                // Images grid
                if (_images.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                    return ElevatedButton(
                      onPressed: warrantyProvider.isLoading ? null : _saveWarranty,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: warrantyProvider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Lưu',
                              style: TextStyle(fontSize: 16),
                            ),
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
