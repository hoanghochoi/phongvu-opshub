import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../data/repositories/inventory_import_repository.dart';

typedef InventoryFilePicker = Future<InventoryPickedFile?> Function();
typedef InventoryImportUploader =
    Future<InventoryImportResult> Function(String path);

class InventoryPickedFile {
  final String name;
  final String path;
  final int size;

  const InventoryPickedFile({
    required this.name,
    required this.path,
    required this.size,
  });
}

class InventoryImportScreen extends StatefulWidget {
  final InventoryImportRepository? repository;
  final InventoryFilePicker? filePicker;
  final InventoryImportUploader? uploader;

  const InventoryImportScreen({
    super.key,
    this.repository,
    this.filePicker,
    this.uploader,
  });

  @override
  State<InventoryImportScreen> createState() => _InventoryImportScreenState();
}

class _InventoryImportScreenState extends State<InventoryImportScreen> {
  late final InventoryImportRepository _repository;

  InventoryPickedFile? _selectedFile;
  bool _isUploading = false;
  InventoryImportResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? InventoryImportRepository(ApiClient());
  }

  Future<InventoryPickedFile?> _defaultPickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      allowMultiple: false,
      withData: false,
    );
    final file = picked?.files.single;
    if (file == null || file.path == null) return null;
    return InventoryPickedFile(
      name: file.name,
      path: file.path!,
      size: file.size,
    );
  }

  Future<void> _pickFile() async {
    await AppLogger.instance.info(
      'InventoryImport',
      'Manual inventory file picker opened',
    );
    final picked = await (widget.filePicker ?? _defaultPickFile)();
    if (picked == null) {
      await AppLogger.instance.info(
        'InventoryImport',
        'Manual inventory file picker canceled',
      );
      return;
    }
    setState(() {
      _selectedFile = picked;
      _result = null;
      _errorMessage = null;
    });
    await AppLogger.instance.info(
      'InventoryImport',
      'Manual inventory file selected',
      context: {
        'fileName': picked.name,
        'size': picked.size,
        'extension': _extensionOf(picked.name),
      },
    );
  }

  Future<void> _upload() async {
    final file = _selectedFile;
    if (file == null) {
      await AppLogger.instance.warn(
        'InventoryImport',
        'Manual inventory upload blocked',
        context: {'reason': 'missing_file'},
      );
      setState(() {
        _errorMessage = 'Vui lòng chọn file tồn kho trước khi cập nhật.';
      });
      return;
    }
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'InventoryImport',
        'Manual inventory upload started',
        context: {
          'fileName': file.name,
          'size': file.size,
          'extension': _extensionOf(file.name),
        },
      );
      final uploader = widget.uploader ?? _repository.uploadInventoryFile;
      final result = await uploader(file.path);
      if (!mounted) return;
      setState(() => _result = result);
      await AppLogger.instance.info(
        'InventoryImport',
        'Manual inventory upload succeeded',
        context: {
          'fileName': file.name,
          'importedRows': result.importedRows,
          'deactivatedRows': result.deactivatedRows,
          'skippedRows': result.skippedRows,
          'totalRows': result.totalRows,
          'srCount': result.srCodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'InventoryImport',
        'Manual inventory upload failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'fileName': file.name,
          'size': file.size,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
        upload: true,
      );
      if (mounted) {
        setState(() {
          _result = null;
          _errorMessage = 'Chưa cập nhật được tồn kho. Vui lòng thử lại.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final errorMessage = _errorMessage;

    return AppResponsiveScrollView(
      maxWidth: 980,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InventoryImportHeader(
            selectedFile: _selectedFile,
            isUploading: _isUploading,
            hasResult: result != null,
          ),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          _UploadPanel(
            file: _selectedFile,
            isUploading: _isUploading,
            onPickFile: _pickFile,
            onUpload: _selectedFile == null ? null : _upload,
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: AppLayoutTokens.sectionGap),
            _ImportErrorPanel(
              message: errorMessage,
              canRetry: _selectedFile != null && !_isUploading,
              onRetry: _upload,
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: AppLayoutTokens.sectionGap),
            _ResultPanel(result: result),
          ],
        ],
      ),
    );
  }
}

class _InventoryImportHeader extends StatelessWidget {
  final InventoryPickedFile? selectedFile;
  final bool isUploading;
  final bool hasResult;

  const _InventoryImportHeader({
    required this.selectedFile,
    required this.isUploading,
    required this.hasResult,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = isUploading
        ? 'Đang cập nhật'
        : hasResult
        ? 'Đã có kết quả'
        : selectedFile == null
        ? 'Chưa chọn file'
        : 'Sẵn sàng cập nhật';
    final statusColor = isUploading
        ? AppColors.info
        : hasResult
        ? AppColors.success
        : selectedFile == null
        ? AppColors.warning
        : AppColors.primary;

    return AppSurfaceCard(
      key: const Key('inventory-import-header'),
      backgroundColor: AppColors.primarySurface,
      borderColor: AppColors.primary.withValues(alpha: 0.18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.tabletBreakpoint;
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cập nhật tồn kho FIFO', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Nhập file tồn kho vật lý để bổ sung dữ liệu FIFO thủ công.',
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
                    label: statusLabel,
                    color: statusColor,
                    backgroundColor: statusColor.withValues(alpha: 0.10),
                  ),
                  const AppStatusChip(
                    label: 'Excel .xlsx/.xls',
                    color: AppColors.info,
                    backgroundColor: AppColors.infoSurface,
                  ),
                  const AppStatusChip(
                    label: 'Không ghi đè trạng thái xuất',
                    color: AppColors.success,
                    backgroundColor: AppColors.successSurface,
                  ),
                ],
              ),
            ],
          );

          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.primary,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [icon, const SizedBox(height: 14), titleBlock],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(child: titleBlock),
            ],
          );
        },
      ),
    );
  }
}

class _UploadPanel extends StatelessWidget {
  final InventoryPickedFile? file;
  final bool isUploading;
  final VoidCallback onPickFile;
  final VoidCallback? onUpload;

  const _UploadPanel({
    required this.file,
    required this.isUploading,
    required this.onPickFile,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('inventory-import-upload-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.table_chart_outlined, color: AppColors.info),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('File tồn kho', style: AppTextStyles.headingS),
                    const SizedBox(height: 4),
                    Text(
                      file?.name ?? 'Chưa chọn file Excel',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyM.copyWith(
                        color: file == null
                            ? AppColors.neutral500
                            : AppColors.neutral800,
                      ),
                    ),
                    if (file != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          AppInfoChip(
                            Icons.insert_drive_file_outlined,
                            _extensionOf(file!.name).toUpperCase(),
                            color: AppColors.info,
                          ),
                          AppInfoChip(
                            Icons.data_usage_rounded,
                            _formatFileSize(file!.size),
                            color: AppColors.neutral600,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayoutTokens.formSectionGap),
          AppActionRow(
            children: [
              AppSecondaryButton(
                onPressed: isUploading ? null : onPickFile,
                icon: Icons.folder_open_outlined,
                label: 'Chọn file',
              ),
              AppPrimaryButton(
                onPressed: onUpload,
                icon: Icons.upload_file_outlined,
                label: 'Cập nhật tồn kho',
                isLoading: isUploading,
                loadingLabel: 'Đang cập nhật',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImportErrorPanel extends StatelessWidget {
  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  const _ImportErrorPanel({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('inventory-import-error-panel'),
      borderColor: AppColors.error.withValues(alpha: 0.24),
      backgroundColor: AppColors.errorSurface,
      child: AppStatePanel.error(
        title: message,
        message: 'Kiểm tra lại mẫu file hoặc thử cập nhật lại.',
        actionLabel: canRetry ? 'Thử cập nhật lại' : null,
        actionIcon: Icons.refresh_rounded,
        onAction: canRetry ? onRetry : null,
        compact: true,
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final InventoryImportResult result;

  const _ResultPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('inventory-import-result-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt_rounded, color: AppColors.success),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(
                child: Text(
                  'Kết quả cập nhật',
                  style: AppTextStyles.headingS,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          _ResultMetrics(result: result),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          Text('Showroom trong file', style: AppTextStyles.labelM),
          const SizedBox(height: 8),
          if (result.srCodes.isEmpty)
            const AppInfoChip(Icons.storefront_outlined, 'Chưa có showroom')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in result.srCodes)
                  AppStatusChip(
                    label: code,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primarySurface,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResultMetrics extends StatelessWidget {
  final InventoryImportResult result;

  const _ResultMetrics({required this.result});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricData(
        label: 'Tổng dòng',
        value: '${result.totalRows}',
        icon: Icons.format_list_numbered_rounded,
        color: AppColors.neutral700,
      ),
      _MetricData(
        label: 'Dòng hợp lệ',
        value: '${result.importedRows}',
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
      ),
      _MetricData(
        label: 'Dòng bỏ qua',
        value: '${result.skippedRows}',
        icon: Icons.skip_next_outlined,
        color: AppColors.warning,
      ),
      _MetricData(
        label: 'Dòng ngừng active',
        value: '${result.deactivatedRows}',
        icon: Icons.inventory_rounded,
        color: AppColors.info,
      ),
    ];

    return Wrap(
      spacing: AppLayoutTokens.cardGap,
      runSpacing: AppLayoutTokens.cardGap,
      children: [
        for (final metric in metrics)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 142, maxWidth: 210),
            child: _MetricTile(metric: metric),
          ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final _MetricData metric;

  const _MetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: metric.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(color: metric.color.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(metric.icon, color: metric.color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.value,
                    style: AppTextStyles.headingS.copyWith(color: metric.color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

String _extensionOf(String fileName) {
  final index = fileName.lastIndexOf('.');
  if (index < 0 || index == fileName.length - 1) return 'excel';
  return fileName.substring(index + 1).toLowerCase();
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return 'Không rõ dung lượng';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
}
