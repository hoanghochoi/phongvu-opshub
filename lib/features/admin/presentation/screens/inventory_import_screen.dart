import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../data/repositories/inventory_import_repository.dart';

class InventoryImportScreen extends StatefulWidget {
  const InventoryImportScreen({super.key});

  @override
  State<InventoryImportScreen> createState() => _InventoryImportScreenState();
}

class _InventoryImportScreenState extends State<InventoryImportScreen> {
  final InventoryImportRepository _repository = InventoryImportRepository(
    ApiClient(),
  );

  String? _fileName;
  String? _filePath;
  bool _isUploading = false;
  InventoryImportResult? _result;

  Future<void> _pickFile() async {
    await AppLogger.instance.info(
      'InventoryImport',
      'Manual inventory file picker opened',
    );
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      allowMultiple: false,
      withData: false,
    );
    final file = picked?.files.single;
    if (file == null || file.path == null) return;
    setState(() {
      _fileName = file.name;
      _filePath = file.path;
      _result = null;
    });
    await AppLogger.instance.info(
      'InventoryImport',
      'Manual inventory file selected',
      context: {'fileName': file.name, 'size': file.size},
    );
  }

  Future<void> _upload() async {
    final path = _filePath;
    if (path == null || _isUploading) return;
    setState(() => _isUploading = true);
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'InventoryImport',
        'Manual inventory upload started',
        context: {'fileName': _fileName},
      );
      final result = await _repository.uploadInventoryFile(path);
      if (!mounted) return;
      setState(() => _result = result);
      await AppLogger.instance.info(
        'InventoryImport',
        'Manual inventory upload succeeded',
        context: {
          'fileName': _fileName,
          'importedRows': result.importedRows,
          'deactivatedRows': result.deactivatedRows,
          'skippedRows': result.skippedRows,
          'srCount': result.srCodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      await AppLogger.instance.error(
        'InventoryImport',
        'Manual inventory upload failed',
        error: error,
        stackTrace: stackTrace,
        context: {'fileName': _fileName},
        upload: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa cập nhật được tồn kho. Vui lòng thử lại.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Cập nhật tồn kho', showBack: true),
      body: AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.formMaxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UploadPanel(
              fileName: _fileName,
              isUploading: _isUploading,
              onPickFile: _pickFile,
              onUpload: _filePath == null ? null : _upload,
            ),
            if (result != null) ...[
              const SizedBox(height: AppLayoutTokens.sectionGap),
              _ResultPanel(result: result),
            ],
          ],
        ),
      ),
    );
  }
}

class _UploadPanel extends StatelessWidget {
  final String? fileName;
  final bool isUploading;
  final VoidCallback onPickFile;
  final VoidCallback? onUpload;

  const _UploadPanel({
    required this.fileName,
    required this.isUploading,
    required this.onPickFile,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: AppLayoutTokens.formInlineGap),
                Expanded(
                  child: Text(
                    fileName ?? 'Chưa chọn file Excel',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isUploading ? null : onPickFile,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text(
                      'Chọn file',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ),
                const SizedBox(width: AppLayoutTokens.formInlineGap),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isUploading ? null : onUpload,
                    icon: isUploading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      isUploading ? 'Đang cập nhật' : 'Cập nhật',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final InventoryImportResult result;

  const _ResultPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kết quả', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppLayoutTokens.cardGap),
            _ResultRow(label: 'Dòng hợp lệ', value: '${result.importedRows}'),
            _ResultRow(label: 'Dòng bỏ qua', value: '${result.skippedRows}'),
            _ResultRow(
              label: 'Dòng ngừng active',
              value: '${result.deactivatedRows}',
            ),
            _ResultRow(label: 'SR', value: result.srCodes.join(', ')),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
