import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_dialogs.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/sales_report_repository.dart';
import '../../domain/sales_report.dart';

typedef SalesReportImportFilePicker = Future<SalesReportImportFile?> Function();

Future<bool?> showSalesReportImportDialog({
  required BuildContext context,
  required SalesReportRepository repository,
  SalesReportImportFilePicker? filePicker,
}) => showDialog<bool>(
  context: context,
  builder: (_) => AppDirtyFormGuard(
    source: 'SalesReportImport',
    child: _SalesReportImportDialog(
      repository: repository,
      filePicker: filePicker,
    ),
  ),
);

class _SalesReportImportDialog extends StatefulWidget {
  final SalesReportRepository repository;
  final SalesReportImportFilePicker? filePicker;

  const _SalesReportImportDialog({
    required this.repository,
    required this.filePicker,
  });

  @override
  State<_SalesReportImportDialog> createState() =>
      _SalesReportImportDialogState();
}

class _SalesReportImportDialogState extends State<_SalesReportImportDialog> {
  static const _maxBytes = 5 * 1024 * 1024;

  SalesReportImportFile? _file;
  SalesReportImportPreview? _preview;
  SalesReportImportPreview? _result;
  bool _busy = false;
  String? _error;

  Future<SalesReportImportFile?> _defaultPickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return null;
    return SalesReportImportFile(
      name: file.name,
      size: file.size,
      bytes: file.bytes,
      path: file.path,
    );
  }

  Future<void> _pickFile() async {
    await AppLogger.instance.info(
      'SalesReportImport',
      'Historical customer import file picker opened',
    );
    final picked = await (widget.filePicker ?? _defaultPickFile)();
    if (picked == null) {
      await AppLogger.instance.info(
        'SalesReportImport',
        'Historical customer import file picker canceled',
      );
      return;
    }
    if (!picked.hasContent || picked.size <= 0 || picked.size > _maxBytes) {
      if (mounted) {
        setState(() {
          _error = picked.size > _maxBytes
              ? 'File vượt quá 5 MB. Vui lòng chia nhỏ dữ liệu rồi thử lại.'
              : 'Chưa đọc được nội dung file. Vui lòng chọn lại file Excel.';
        });
      }
      await AppLogger.instance.warn(
        'SalesReportImport',
        'Historical customer import file rejected locally',
        context: {'fileName': picked.name, 'size': picked.size},
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _file = picked;
      _preview = null;
      _result = null;
      _error = null;
    });
    notifyAppFormChanged(context);
    await AppLogger.instance.info(
      'SalesReportImport',
      'Historical customer import file selected',
      context: {
        'fileName': picked.name,
        'size': picked.size,
        'extension': _extension(picked.name),
      },
    );
  }

  Future<void> _previewFile() async {
    final file = _file;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'SalesReportImport',
      'Historical customer import preview started',
      context: {'fileName': file.name, 'size': file.size},
    );
    try {
      final preview = await widget.repository.previewImport(file);
      if (!mounted) return;
      setState(() => _preview = preview);
      await AppLogger.instance.info(
        'SalesReportImport',
        'Historical customer import preview succeeded',
        context: {
          'fileName': file.name,
          'fileHashPrefix': _hashPrefix(preview.fileHash),
          'totalRows': preview.totalRows,
          'validRows': preview.validRows,
          'invalidRows': preview.invalidRows,
          'duplicateRows': preview.duplicateRows,
          'purchasedRows': preview.purchasedRows,
          'unassignedRows': preview.unassignedRows,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (mounted) setState(() => _error = _friendlyError(error));
      await AppLogger.instance.error(
        'SalesReportImport',
        'Historical customer import preview failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'fileName': file.name,
          'size': file.size,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final file = _file;
    final preview = _preview;
    if (file == null || preview == null || !preview.canCommit || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'SalesReportImport',
      'Historical customer import commit started',
      context: {
        'fileName': file.name,
        'fileHashPrefix': _hashPrefix(preview.fileHash),
        'validRows': preview.validRows,
      },
    );
    try {
      final result = await widget.repository.commitImport(
        file,
        expectedFileHash: preview.fileHash,
      );
      if (!mounted) return;
      setState(() => _result = result);
      await AppLogger.instance.info(
        'SalesReportImport',
        'Historical customer import commit succeeded',
        context: {
          'batchId': result.batchId,
          'fileHashPrefix': _hashPrefix(result.fileHash),
          'importedRows': result.importedRows,
          'invalidRows': result.invalidRows,
          'duplicateRows': result.duplicateRows,
          'purchasedRows': result.purchasedRows,
          'unassignedRows': result.unassignedRows,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (mounted) setState(() => _error = _friendlyError(error));
      await AppLogger.instance.error(
        'SalesReportImport',
        'Historical customer import commit failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'fileName': file.name,
          'fileHashPrefix': _hashPrefix(preview.fileHash),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final preview = _preview;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: screen.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.upload_file_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nhập Excel khách chưa mua',
                          style: AppTextStyles.headingM,
                        ),
                        Text(
                          'Xem trước dữ liệu trước khi đưa vào Chăm sóc lại',
                          style: AppTextStyles.bodyS,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, result != null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (result != null)
                      _ImportResultPanel(result: result)
                    else ...[
                      const _TemplateHelp(),
                      const SizedBox(height: 16),
                      _FilePanel(file: _file, onPick: _busy ? null : _pickFile),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _ErrorPanel(message: _error!),
                      ],
                      if (preview != null) ...[
                        const SizedBox(height: 18),
                        _PreviewPanel(preview: preview),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppActionRow(
                children: result != null
                    ? [
                        AppPrimaryButton(
                          onPressed: () => Navigator.pop(context, true),
                          icon: Icons.check_rounded,
                          label: 'Hoàn tất',
                        ),
                      ]
                    : [
                        AppSecondaryButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context, false),
                          icon: Icons.close_rounded,
                          label: 'Đóng',
                        ),
                        if (_file == null)
                          AppPrimaryButton(
                            onPressed: _busy ? null : _pickFile,
                            icon: Icons.attach_file_rounded,
                            label: 'Chọn file Excel',
                          )
                        else if (preview == null)
                          AppPrimaryButton(
                            onPressed: _busy ? null : _previewFile,
                            icon: Icons.preview_rounded,
                            label: 'Xem trước dữ liệu',
                            isLoading: _busy,
                            loadingLabel: 'Đang kiểm tra file...',
                          )
                        else
                          AppPrimaryButton(
                            onPressed: preview.canCommit && !_busy
                                ? _commit
                                : null,
                            icon: Icons.cloud_upload_outlined,
                            label: 'Nhập ${preview.validRows} dòng hợp lệ',
                            isLoading: _busy,
                            loadingLabel: 'Đang nhập dữ liệu...',
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

class _TemplateHelp extends StatelessWidget {
  const _TemplateHelp();

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    backgroundColor: AppColors.primary.withValues(alpha: 0.05),
    borderColor: AppColors.primary.withValues(alpha: 0.16),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Yêu cầu file', style: AppTextStyles.labelL),
        SizedBox(height: 6),
        Text(
          '• Giữ nguyên tên các cột trong file nguồn.\n'
          '• Hỗ trợ .xlsx/.xls, tối đa 5 MB và 1.000 dòng.\n'
          '• Dòng đã mua, bị trùng hoặc không hợp lệ sẽ không được nhập.\n'
          '• Nhân viên chưa khớp sẽ để chưa phân công để quản lý xử lý sau.',
          style: AppTextStyles.bodyS,
        ),
      ],
    ),
  );
}

class _FilePanel extends StatelessWidget {
  final SalesReportImportFile? file;
  final VoidCallback? onPick;

  const _FilePanel({required this.file, required this.onPick});

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    child: Row(
      children: [
        const Icon(Icons.table_view_outlined, color: AppColors.success),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file?.name ?? 'Chưa chọn file',
                style: AppTextStyles.labelM,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                file == null
                    ? 'Chọn file Excel dữ liệu khách chưa mua'
                    : _formatBytes(file!.size),
                style: AppTextStyles.bodyS,
              ),
            ],
          ),
        ),
        AppLinkButton(
          onPressed: onPick,
          icon: file == null ? Icons.attach_file : Icons.swap_horiz,
          label: file == null ? 'Chọn file' : 'Đổi file',
          compact: true,
        ),
      ],
    ),
  );
}

class _PreviewPanel extends StatelessWidget {
  final SalesReportImportPreview preview;

  const _PreviewPanel({required this.preview});

  @override
  Widget build(BuildContext context) {
    final issues = preview.rows
        .where((row) => row.errors.isNotEmpty || row.warnings.isNotEmpty)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Kết quả xem trước', style: AppTextStyles.headingS),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(label: 'Tổng dòng', value: preview.totalRows),
            _CountChip(
              label: 'Hợp lệ',
              value: preview.validRows,
              color: AppColors.success,
            ),
            _CountChip(
              label: 'Đã mua',
              value: preview.purchasedRows,
              color: AppColors.neutral600,
            ),
            _CountChip(
              label: 'Bị trùng',
              value: preview.duplicateRows,
              color: AppColors.warning,
            ),
            _CountChip(
              label: 'Không hợp lệ',
              value: preview.invalidRows,
              color: AppColors.error,
            ),
            _CountChip(
              label: 'Chưa phân công',
              value: preview.unassignedRows,
              color: AppColors.warning,
            ),
          ],
        ),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Dòng cần lưu ý', style: AppTextStyles.labelL),
          const SizedBox(height: 8),
          ...issues.take(100).map(_RowIssueTile.new),
          if (issues.length > 100)
            Text(
              'Còn ${issues.length - 100} dòng khác. Vui lòng sửa file và xem trước lại.',
              style: AppTextStyles.bodyS,
            ),
        ],
        if (!preview.canCommit) ...[
          const SizedBox(height: 12),
          const _ErrorPanel(
            message:
                'File chưa có dòng hợp lệ để nhập. Vui lòng sửa dữ liệu rồi xem trước lại.',
          ),
        ],
      ],
    );
  }
}

class _RowIssueTile extends StatelessWidget {
  final SalesReportImportRowPreview row;

  const _RowIssueTile(this.row);

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dòng ${row.rowNumber} • ${row.customerName.isEmpty ? 'Chưa có tên khách' : row.customerName} • Showroom ${row.storeCode.isEmpty ? 'chưa có' : row.storeCode}',
          style: AppTextStyles.labelM,
        ),
        for (final error in row.errors)
          Text(
            'Lỗi: $error',
            style: AppTextStyles.bodyS.copyWith(color: AppColors.error),
          ),
        for (final warning in row.warnings)
          Text(
            'Lưu ý: $warning',
            style: AppTextStyles.bodyS.copyWith(color: AppColors.warning),
          ),
      ],
    ),
  );
}

class _ImportResultPanel extends StatelessWidget {
  final SalesReportImportPreview result;

  const _ImportResultPanel({required this.result});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Icon(
        Icons.check_circle_rounded,
        size: 64,
        color: AppColors.success,
      ),
      const SizedBox(height: 12),
      const Text('Đã nhập dữ liệu', style: AppTextStyles.headingM),
      const SizedBox(height: 6),
      Text(
        '${result.importedRows} hồ sơ đã được đưa vào Chăm sóc lại.',
        style: AppTextStyles.bodyM,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 18),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _CountChip(
            label: 'Đã nhập',
            value: result.importedRows,
            color: AppColors.success,
          ),
          _CountChip(label: 'Đã mua', value: result.purchasedRows),
          _CountChip(
            label: 'Bị trùng',
            value: result.duplicateRows,
            color: AppColors.warning,
          ),
          _CountChip(
            label: 'Không hợp lệ',
            value: result.invalidRows,
            color: AppColors.error,
          ),
          _CountChip(
            label: 'Chưa phân công',
            value: result.unassignedRows,
            color: AppColors.warning,
          ),
        ],
      ),
    ],
  );
}

class _CountChip extends StatelessWidget {
  final String label;
  final int value;
  final Color? color;

  const _CountChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Chip(
    avatar: CircleAvatar(
      backgroundColor: color ?? AppColors.neutral600,
      foregroundColor: AppColors.surface,
      child: Text('$value'),
    ),
    label: Text(label),
  );
}

class _ErrorPanel extends StatelessWidget {
  final String message;

  const _ErrorPanel({required this.message});

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    backgroundColor: AppColors.error.withValues(alpha: 0.06),
    borderColor: AppColors.error.withValues(alpha: 0.25),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: AppTextStyles.bodyM)),
      ],
    ),
  );
}

String _friendlyError(Object error) => error is ApiException
    ? error.message
    : 'Chưa xử lý được file Excel. Vui lòng thử lại.';

String _extension(String name) =>
    name.contains('.') ? name.split('.').last.toLowerCase() : '';

String _hashPrefix(String hash) =>
    hash.length <= 12 ? hash : hash.substring(0, 12);

String _formatBytes(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(1)} KB';
