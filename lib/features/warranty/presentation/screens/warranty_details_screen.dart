import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/warranty_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_state_widgets.dart';

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
    try {
      // Request storage permission
      if (Platform.isAndroid) {
        // For Android 13+ (API 33+), use photos permission
        final permission = await Permission.photos.status;

        if (!permission.isGranted) {
          // Request permission
          final result = await Permission.photos.request();

          if (result.isDenied) {
            // Permission denied - show guide
            if (mounted) {
              _showPermissionGuide(isPermanentlyDenied: false);
            }
            return;
          } else if (result.isPermanentlyDenied) {
            // Permission permanently denied - show settings guide
            if (mounted) {
              _showPermissionGuide(isPermanentlyDenied: true);
            }
            return;
          }
        }
      }

      // Get image bytes
      List<int> bytes;
      if (_isUrl(imageSource)) {
        // Download from URL
        final response = await http.get(Uri.parse(imageSource));
        if (response.statusCode != 200) {
          throw Exception('Không tải được ảnh');
        }
        bytes = response.bodyBytes;
      } else {
        // Decode from base64 (backward compatibility)
        bytes = base64Decode(imageSource);
      }

      // Get download directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory();
      }

      if (directory == null) {
        throw Exception('Không tìm thấy thư mục download');
      }

      // Create file name with original extension
      String extension = 'jpg'; // default
      if (_isUrl(imageSource)) {
        // Extract extension from URL
        final uri = Uri.parse(imageSource);
        final path = uri.path.toLowerCase();
        if (path.endsWith('.png')) {
          extension = 'png';
        } else if (path.endsWith('.jpeg') || path.endsWith('.jpg')) {
          extension = 'jpg';
        } else if (path.endsWith('.webp')) {
          extension = 'webp';
        }
      }

      final fileName =
          '${widget.receiptNumber}_${index + 1}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = '${directory.path}/$fileName';

      // Write file with original quality (no compression)
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lưu vào: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chưa tải được ảnh. Vui lòng thử lại.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPermissionGuide({required bool isPermanentlyDenied}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isPermanentlyDenied ? Icons.settings : Icons.info_outline,
                color: Colors.orange,
              ),
              const SizedBox(width: 12),
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
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Hướng dẫn cấp quyền:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.phone_android,
                              size: 16,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Tùy theo hãng điện thoại:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildPhoneGuide(
                          'Samsung',
                          'Cài đặt → Ứng dụng → PhongVu OpsHub → Quyền',
                        ),
                        _buildPhoneGuide(
                          'Xiaomi/Redmi',
                          'Cài đặt → Ứng dụng → Quản lý ứng dụng → PhongVu OpsHub → Quyền ứng dụng',
                        ),
                        _buildPhoneGuide(
                          'Oppo/Realme',
                          'Cài đặt → Quyền riêng tư → Trình quản lý quyền → PhongVu OpsHub',
                        ),
                        _buildPhoneGuide(
                          'Vivo',
                          'Cài đặt → Ứng dụng và thông báo → Quản lý ứng dụng → PhongVu OpsHub → Quyền',
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (isPermanentlyDenied)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: const Text(
                  'Mở Cài đặt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                isPermanentlyDenied ? 'Đóng' : 'OK',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
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
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildPhoneGuide(String brand, String path) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue[700],
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                children: [
                  TextSpan(
                    text: '$brand: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: path),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isUrl(String source) {
    return source.startsWith('http://') || source.startsWith('https://');
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return 'Chưa có';
    }

    try {
      // Try to parse different date formats
      DateTime? dateTime;

      // Try ISO format first (yyyy-MM-dd or yyyy-MM-ddTHH:mm:ss)
      try {
        dateTime = DateTime.parse(dateString);
      } catch (e) {
        // Try dd/MM/yyyy format
        try {
          final parts = dateString.split('/');
          if (parts.length == 3) {
            dateTime = DateTime(
              int.parse(parts[2]), // year
              int.parse(parts[1]), // month
              int.parse(parts[0]), // day
            );
          }
        } catch (e) {
          // If all parsing fails, return original string
          return dateString;
        }
      }

      if (dateTime != null) {
        // Format as dd/MM/yyyy
        return DateFormat('dd/MM/yyyy').format(dateTime);
      }

      return dateString;
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: GradientHeader(title: widget.receiptNumber, showBack: true),
      body: SafeArea(
        child: Consumer<WarrantyProvider>(
          builder: (context, warrantyProvider, _) {
            if (warrantyProvider.isLoading) {
              return const AppStatePanel.loading(
                title: 'Đang tải chi tiết biên nhận',
              );
            }

            if (warrantyProvider.errorMessage != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      warrantyProvider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadDetails,
                      child: const Text(
                        'Thử lại',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              );
            }

            final details = warrantyProvider.currentDetails;
            if (details == null) {
              return const Center(child: Text('Không có dữ liệu'));
            }

            // Extract images
            final List<String> images = [];

            // Try to get images from array format first (new format)
            if (details.containsKey('images') && details['images'] is List) {
              final imagesList = details['images'] as List;
              for (var img in imagesList) {
                final imgStr = img?.toString();
                if (imgStr != null && imgStr.isNotEmpty) {
                  images.add(imgStr);
                }
              }
            } else {
              // Fallback to old format (image0, image1, image2...)
              int imageIndex = 0;
              while (details.containsKey('image$imageIndex')) {
                final img = details['image$imageIndex']?.toString();
                if (img != null && img.isNotEmpty) {
                  images.add(img);
                }
                imageIndex++;
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Receipt info card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thông tin biên nhận',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
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
                            value: _formatDate(details['date']?.toString()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Images section
                  if (images.isNotEmpty) ...[
                    Text(
                      'Hình ảnh (${images.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        return _ImageCard(
                          imageSource: images[index],
                          index: index,
                          onTap: () => _viewImage(images[index], index),
                          onDownload: () =>
                              _downloadImage(images[index], index),
                        );
                      },
                    ),
                  ] else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('Không có hình ảnh'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
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
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
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

  bool _isUrl(String source) {
    return source.startsWith('http://') || source.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _isUrl(imageSource)
                ? CachedNetworkImage(
                    imageUrl: imageSource,
                    fit: BoxFit.cover,
                    memCacheWidth: 800,
                    memCacheHeight: 800,
                    maxWidthDiskCache: 1000,
                    maxHeightDiskCache: 1000,
                    placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (context, url, error) {
                      return Container(
                        color: Colors.grey[300],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 48,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ảnh ${index + 1} chưa tải được',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : Image.memory(
                    base64Decode(imageSource),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 48,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ảnh ${index + 1} chưa tải được',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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

class _ImageViewScreen extends StatelessWidget {
  final String imageSource;
  final String title;
  final VoidCallback onDownload;

  const _ImageViewScreen({
    required this.imageSource,
    required this.title,
    required this.onDownload,
  });

  bool _isUrl(String source) {
    return source.startsWith('http://') || source.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: GradientHeader(
        title: title,
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: onDownload,
            tooltip: 'Tải về',
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: _isUrl(imageSource)
              ? CachedNetworkImage(
                  imageUrl: imageSource,
                  placeholder: (context, url) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 64, color: Colors.red),
                          SizedBox(height: 16),
                          Text('Chưa hiển thị được ảnh'),
                        ],
                      ),
                    );
                  },
                )
              : Image.memory(
                  base64Decode(imageSource),
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 64, color: Colors.red),
                          SizedBox(height: 16),
                          Text('Chưa hiển thị được ảnh'),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
