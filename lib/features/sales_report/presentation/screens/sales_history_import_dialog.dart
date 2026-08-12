import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/sales_report_repository.dart';
import '../../domain/sales_report.dart';
import '../providers/sales_report_provider.dart';

const _maxHistoryImportBytes = 200 * 1024 * 1024;

Future<void> showSalesHistoryImportDialog({
  required BuildContext context,
  required SalesReportProvider provider,
}) async {
  await AppLogger.instance.info(
    'SalesHistoryImport',
    'Historical sales import dialog opened',
    context: {'isWeb': kIsWeb, 'platform': defaultTargetPlatform.name},
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _SalesHistoryImportDialog(provider: provider),
  );
  await AppLogger.instance.info(
    'SalesHistoryImport',
    'Historical sales import dialog closed',
    context: {
      'lastStatus': provider.historyImportJob?.status,
      'hasActiveJob': provider.isHistoryImportBusy,
    },
  );
}

class _SalesHistoryImportDialog extends StatefulWidget {
  const _SalesHistoryImportDialog({required this.provider});

  final SalesReportProvider provider;

  @override
  State<_SalesHistoryImportDialog> createState() =>
      _SalesHistoryImportDialogState();
}

class _SalesHistoryImportDialogState extends State<_SalesHistoryImportDialog> {
  bool _showHistory = false;
  _LocalLifecycleError? _localError;

  @override
  void initState() {
    super.initState();
    widget.provider.addListener(_clearResolvedDismissBlock);
  }

  @override
  void didUpdateWidget(covariant _SalesHistoryImportDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider == widget.provider) return;
    oldWidget.provider.removeListener(_clearResolvedDismissBlock);
    widget.provider.addListener(_clearResolvedDismissBlock);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_clearResolvedDismissBlock);
    super.dispose();
  }

  void _clearResolvedDismissBlock() {
    if (!mounted ||
        _localError?.kind != _LocalLifecycleErrorKind.dismissBlocked ||
        !widget.provider.canDismissHistoryImport) {
      return;
    }
    setState(() => _localError = null);
  }

  void _requestClose() {
    if (!widget.provider.canDismissHistoryImport) {
      setState(() {
        _localError = _LocalLifecycleError(
          kind: _LocalLifecycleErrorKind.dismissBlocked,
          message: widget.provider.canRetryHistoryImportPolling
              ? 'Tác vụ vẫn đang chạy. Chọn “Kiểm tra lại” để tiếp tục theo dõi hoặc hủy tác vụ trước khi đóng.'
              : 'Tác vụ đang chạy. Hãy hủy tác vụ trước khi đóng cửa sổ này.',
        );
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickFile() async {
    setState(() => _localError = null);
    await AppLogger.instance.info(
      'SalesHistoryImport',
      'Historical sales import file picker opened',
    );
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv'],
      withData: false,
      withReadStream: kIsWeb,
      lockParentWindow: true,
    );
    final selected = result?.files.singleOrNull;
    if (selected == null) {
      await AppLogger.instance.info(
        'SalesHistoryImport',
        'Historical sales import file picker cancelled',
      );
      return;
    }
    final extension = selected.extension?.toLowerCase();
    if (!const {'csv', 'tsv'}.contains(extension) ||
        selected.size <= 0 ||
        selected.size > _maxHistoryImportBytes) {
      setState(() {
        _localError = const _LocalLifecycleError(
          kind: _LocalLifecycleErrorKind.validation,
          message:
              'Tệp chưa phù hợp. Chọn CSV/TSV không quá 200 MiB rồi thử lại.',
        );
      });
      await AppLogger.instance.warn(
        'SalesHistoryImport',
        'Historical sales import file rejected locally',
        context: {
          'format': extension,
          'bytes': selected.size,
          'hasBytes': selected.bytes?.isNotEmpty == true,
          'hasPath': selected.path?.isNotEmpty == true,
        },
      );
      return;
    }
    await widget.provider.startHistoryImport(
      SalesReportImportFile(
        name: selected.name,
        size: selected.size,
        bytes: selected.bytes,
        path: selected.path,
        readStream: selected.readStream,
      ),
    );
  }

  Future<void> _showVersionHistory() async {
    setState(() => _showHistory = true);
    await widget.provider.loadHistoryVersions();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('sales-history-import-dialog'),
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: AppColors.raisedOf(context),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 520),
        child: AnimatedBuilder(
          animation: widget.provider,
          builder: (context, _) {
            final provider = widget.provider;
            return PopScope(
              canPop: provider.canDismissHistoryImport,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _requestClose();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HistoryImportHeader(
                    key: const Key('sales-history-import-header'),
                    onClose: _requestClose,
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                      child: _showHistory
                          ? _VersionHistory(
                              provider: provider,
                              onBack: () =>
                                  setState(() => _showHistory = false),
                            )
                          : _ImportLifecycle(
                              provider: provider,
                              localError: _localError,
                              onPickFile: _pickFile,
                              onShowHistory: _showVersionHistory,
                              onClose: _requestClose,
                            ),
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

class _HistoryImportHeader extends StatelessWidget {
  const _HistoryImportHeader({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Nhập dữ liệu bán hàng lịch sử',
              style: AppTextStyles.headingS,
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            onPressed: onClose,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(PhosphorIconsRegular.x),
          ),
        ],
      ),
    );
  }
}

class _ImportLifecycle extends StatelessWidget {
  const _ImportLifecycle({
    required this.provider,
    required this.localError,
    required this.onPickFile,
    required this.onShowHistory,
    required this.onClose,
  });

  final SalesReportProvider provider;
  final _LocalLifecycleError? localError;
  final Future<void> Function() onPickFile;
  final Future<void> Function() onShowHistory;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final job = provider.historyImportJob;
    final error = localError?.message ?? provider.historyImportError;
    final errorKind = error == null
        ? null
        : localError?.kind == _LocalLifecycleErrorKind.validation
        ? _LifecycleErrorKind.localValidation
        : localError?.kind == _LocalLifecycleErrorKind.dismissBlocked
        ? _LifecycleErrorKind.dismissBlocked
        : provider.canRetryHistoryImportPolling
        ? _LifecycleErrorKind.polling
        : job == null
        ? _LifecycleErrorKind.admission
        : _LifecycleErrorKind.operation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: error ?? _jobTitle(job),
          child: _LifecyclePanel(job: job, error: error, errorKind: errorKind),
        ),
        if (job?.status == 'UPLOADING') ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            label:
                'Tiến trình tải tệp ${(job!.uploadProgress * 100).round()} phần trăm',
            child: LinearProgressIndicator(value: job.uploadProgress),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Phạm vi được xác nhận theo ngày + showroom · Không lưu tệp gốc hoặc dữ liệu cá nhân.',
          style: AppTextStyles.bodyS.copyWith(
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        if (provider.historyImportMessage != null) ...[
          const SizedBox(height: 12),
          AppStatusBanner(
            icon: PhosphorIconsRegular.info,
            title: 'Trạng thái',
            message: provider.historyImportMessage!,
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 112,
              child: AppSecondaryButton(
                size: AppButtonSize.medium,
                onPressed: onClose,
                label: 'Đóng',
              ),
            ),
            if (job?.quarantinedGrains != 0 && job?.isTerminal == true)
              SizedBox(
                width: 164,
                child: AppSecondaryButton(
                  size: AppButtonSize.medium,
                  onPressed: provider.saveHistoryQuarantineReport,
                  icon: PhosphorIconsRegular.downloadSimple,
                  label: 'Tải báo cáo lỗi',
                ),
              ),
            if (job == null ||
                job.status == 'FAILED' ||
                job.status == 'CANCELLED')
              SizedBox(
                width: 144,
                child: AppPrimaryButton(
                  size: AppButtonSize.medium,
                  onPressed: provider.isHistoryImportBusy ? null : onPickFile,
                  icon: PhosphorIconsRegular.uploadSimple,
                  label: 'Chọn tệp',
                ),
              ),
            if (job != null && !job.isTerminal)
              SizedBox(
                width: 144,
                child: AppPrimaryButton(
                  size: AppButtonSize.medium,
                  onPressed: job.cancelRequested
                      ? null
                      : provider.cancelHistoryImport,
                  label: job.cancelRequested ? 'Đang hủy…' : 'Hủy tải',
                ),
              ),
            if (provider.canRetryHistoryImportPolling)
              SizedBox(
                width: 144,
                child: AppSecondaryButton(
                  size: AppButtonSize.medium,
                  onPressed: provider.retryHistoryImportPolling,
                  label: 'Kiểm tra lại',
                ),
              ),
            if (job?.canActivate == true)
              SizedBox(
                width: 176,
                child: AppPrimaryButton(
                  size: AppButtonSize.medium,
                  isLoading: provider.isHistoryImportBusy,
                  onPressed: () =>
                      provider.activateHistoryVersion(job!.versionId!),
                  label: 'Kích hoạt phiên bản',
                ),
              ),
            SizedBox(
              width: 132,
              child: AppSecondaryButton(
                size: AppButtonSize.medium,
                onPressed: onShowHistory,
                label: 'Xem lịch sử',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _LocalLifecycleErrorKind { validation, dismissBlocked }

class _LocalLifecycleError {
  const _LocalLifecycleError({required this.kind, required this.message});

  final _LocalLifecycleErrorKind kind;
  final String message;
}

enum _LifecycleErrorKind {
  localValidation,
  dismissBlocked,
  admission,
  polling,
  operation,
}

class _LifecyclePanel extends StatelessWidget {
  const _LifecyclePanel({
    required this.job,
    required this.error,
    required this.errorKind,
  });

  final SalesHistoryImportJob? job;
  final String? error;
  final _LifecycleErrorKind? errorKind;

  @override
  Widget build(BuildContext context) {
    final tone = error != null
        ? AppStateTone.error
        : (job?.quarantinedGrains ?? 0) > 0
        ? AppStateTone.warning
        : job?.status == 'READY'
        ? AppStateTone.success
        : AppStateTone.neutral;
    final title = error ?? _jobTitle(job);
    final detail = switch (errorKind) {
      _LifecycleErrorKind.localValidation =>
        'Sửa tệp rồi chọn lại để tiếp tục.',
      _LifecycleErrorKind.dismissBlocked =>
        'Tác vụ chưa hoàn tất. Hãy tiếp tục theo dõi hoặc hủy tác vụ trước khi đóng.',
      _LifecycleErrorKind.admission =>
        'Chưa tạo được tác vụ nhập dữ liệu. Vui lòng chờ ít phút rồi thử lại.',
      _LifecycleErrorKind.polling =>
        'Tác vụ vẫn đang chạy và chưa thể đóng cửa sổ. Chọn “Kiểm tra lại” để tiếp tục theo dõi hoặc hủy tác vụ.',
      _LifecycleErrorKind.operation =>
        'Kiểm tra thông báo phía trên rồi thử lại.',
      null => _jobDetail(job),
    };
    return AppSurfaceCard(
      backgroundColor: _toneSurface(context, tone),
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelL),
          const SizedBox(height: 8),
          Text(
            detail,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionHistory extends StatelessWidget {
  const _VersionHistory({required this.provider, required this.onBack});

  final SalesReportProvider provider;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Quay lại',
              onPressed: onBack,
              icon: const Icon(PhosphorIconsRegular.arrowLeft),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Lịch sử phiên bản', style: AppTextStyles.labelL),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (provider.isLoadingHistoryVersions)
          const AppStatePanel.loading(
            key: Key('sales-history-versions-loading'),
            title: 'Đang tải lịch sử phiên bản',
            message: 'Vui lòng chờ trong giây lát.',
          )
        else if (provider.historyImportError != null)
          AppStatePanel.error(
            key: const Key('sales-history-versions-error'),
            title: 'Chưa tải được lịch sử phiên bản',
            message: provider.historyImportError,
            actionLabel: 'Thử lại',
            onAction: provider.loadHistoryVersions,
          )
        else if (provider.historyVersions.isEmpty)
          const AppStatePanel.empty(
            key: Key('sales-history-versions-empty'),
            title: 'Chưa có phiên bản',
            message: 'Chọn tệp CSV/TSV để tạo phiên bản đầu tiên.',
          )
        else
          for (final version in provider.historyVersions) ...[
            _VersionTile(provider: provider, version: version),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({required this.provider, required this.version});

  final SalesReportProvider provider;
  final SalesHistoryVersion version;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${version.rangeStart} – ${version.rangeEnd}',
                  style: AppTextStyles.labelM,
                ),
                const SizedBox(height: 4),
                Text(
                  '${version.cleanRowCount} dòng hợp lệ · ${version.quarantinedRows} dòng cách ly · ${version.activeGrainCount} phạm vi đang dùng',
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: version.isActive ? 116 : 104,
            child: version.isActive
                ? AppSecondaryButton(
                    size: AppButtonSize.medium,
                    onPressed: provider.isHistoryImportBusy
                        ? null
                        : () => provider.rollbackHistoryVersion(version.id),
                    label: 'Hoàn tác',
                  )
                : AppPrimaryButton(
                    size: AppButtonSize.medium,
                    onPressed: provider.isHistoryImportBusy
                        ? null
                        : () => provider.activateHistoryVersion(version.id),
                    label: 'Kích hoạt',
                  ),
          ),
        ],
      ),
    );
  }
}

String _jobTitle(SalesHistoryImportJob? job) {
  if (job == null) return 'Chọn tệp CSV/TSV để bắt đầu';
  return switch (job.status) {
    'UPLOADING' => 'Đang tải tệp… ${(job.uploadProgress * 100).round()}%',
    'QUEUED' => 'Đã nhận tệp, đang xếp hàng kiểm tra',
    'PARSING' => 'Đang kiểm tra ${job.totalRows} dòng',
    'FINALIZING' => 'Đang tạo phiên bản dữ liệu',
    'READY' => '${job.cleanRows} hợp lệ · ${job.quarantinedRows} cách ly',
    'CANCELLED' => 'Đã hủy nhập dữ liệu',
    _ => 'Chưa hoàn tất nhập dữ liệu',
  };
}

String _jobDetail(SalesHistoryImportJob? job) {
  if (job == null) return 'Tối đa 200 MiB · 1.000.000 dòng';
  if (job.status == 'READY') {
    return '${job.cleanGrains} phạm vi sạch sẵn sàng kích hoạt · ${job.quarantinedGrains} phạm vi cần xử lý';
  }
  if (!job.isTerminal) {
    return switch (job.status) {
      'PARSING' =>
        'Chưa thể đóng cửa sổ khi OpsHub đang kiểm tra dữ liệu. Hãy chờ hoàn tất hoặc chọn Hủy tải.',
      'FINALIZING' =>
        'Chưa thể đóng cửa sổ khi OpsHub đang tạo phiên bản. Hãy chờ hoàn tất hoặc chọn Hủy tải.',
      _ =>
        'Chưa thể đóng cửa sổ khi tác vụ đang chạy. Hãy chờ hoàn tất hoặc chọn Hủy tải.',
    };
  }
  return 'Chọn tệp khác hoặc mở lịch sử để tiếp tục.';
}

Color _toneSurface(BuildContext context, AppStateTone tone) => switch (tone) {
  AppStateTone.success => AppColors.successSurfaceOf(context),
  AppStateTone.warning => AppColors.warningSurfaceOf(context),
  AppStateTone.error => AppColors.errorSurfaceOf(context),
  _ => AppColors.canvasOf(context),
};
