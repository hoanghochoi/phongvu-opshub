import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/repositories/help_content_repository.dart';
import '../../domain/help_content_page.dart';

class HelpContentAdminScreen extends StatefulWidget {
  const HelpContentAdminScreen({super.key, this.repository});

  final HelpContentRepository? repository;

  @override
  State<HelpContentAdminScreen> createState() => _HelpContentAdminScreenState();
}

class _HelpContentAdminScreenState extends State<HelpContentAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keyController = TextEditingController();
  final _titleController = TextEditingController();
  final _fileNameController = TextEditingController();
  final _sortOrderController = TextEditingController(text: '0');
  final _markdownController = TextEditingController();
  late final HelpContentRepository _repository;

  List<HelpContentPage> _pages = const [];
  bool _loading = true;
  bool _saving = false;
  bool _restoring = false;
  String? _errorMessage;
  String? _selectedKey;
  String? _selectedParentKey;
  bool _isPublished = true;
  bool _isCreating = true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? HelpContentRepository(ApiClient());
    unawaited(_load(reason: 'screen_open'));
  }

  @override
  void dispose() {
    _keyController.dispose();
    _titleController.dispose();
    _fileNameController.dispose();
    _sortOrderController.dispose();
    _markdownController.dispose();
    super.dispose();
  }

  Future<void> _load({
    required String reason,
    String? preferredKey,
    bool logOpenEditor = true,
  }) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'HelpContentAdmin',
      'Help content admin load started',
      context: {
        'reason': reason,
        'hasSelection': _selectedKey != null,
        'isCreating': _isCreating,
      },
    );
    try {
      final snapshot = await _repository.fetchAdminSnapshot();
      if (!mounted) return;

      final pages = snapshot.pages;
      final resolvedKey = _resolvePreferredKey(pages, preferredKey);
      setState(() {
        _pages = pages;
        _loading = false;
        _errorMessage = null;
      });

      if (resolvedKey != null) {
        _applyPageToEditor(
          pages.firstWhere((page) => page.key == resolvedKey),
          logEvent: logOpenEditor,
        );
      } else {
        _startCreateDraft(logEvent: false);
      }

      await AppLogger.instance.info(
        'HelpContentAdmin',
        'Help content admin load succeeded',
        context: {
          'reason': reason,
          'pageCount': pages.length,
          'publishedCount': pages.where((page) => page.isPublished).length,
          'draftCount': pages.where((page) => !page.isPublished).length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } on ApiException catch (error) {
      await AppLogger.instance.warn(
        'HelpContentAdmin',
        'Help content admin load failed',
        context: {
          'reason': reason,
          'message': error.message,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'HelpContentAdmin',
        'Help content admin load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'reason': reason,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Không tải được nội dung hướng dẫn.';
      });
    }
  }

  Future<void> _save() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    final sortOrder = int.tryParse(_sortOrderController.text.trim());
    if (sortOrder == null || sortOrder < 0) {
      _showSnackBar('Thứ tự hiển thị phải từ 0 trở lên.');
      return;
    }

    final key = _keyController.text.trim().toLowerCase();
    final title = _titleController.text.trim();
    final fileName = _fileNameController.text.trim();
    final markdown = _markdownController.text;
    final startedAt = DateTime.now();

    setState(() => _saving = true);
    await AppLogger.instance.info(
      'HelpContentAdmin',
      'Help content save started',
      context: {
        'mode': _isCreating ? 'create' : 'update',
        'key': key,
        'parentKey': _selectedParentKey,
        'sortOrder': sortOrder,
        'isPublished': _isPublished,
        'markdownLength': markdown.length,
      },
    );

    try {
      final saved = _isCreating
          ? await _repository.createPage(
              key: key,
              title: title,
              fileName: fileName,
              parentKey: _selectedParentKey,
              sortOrder: sortOrder,
              markdown: markdown,
              isPublished: _isPublished,
            )
          : await _repository.updatePage(
              _selectedKey ?? key,
              title: title,
              fileName: fileName,
              parentKey: _selectedParentKey,
              sortOrder: sortOrder,
              markdown: markdown,
              isPublished: _isPublished,
            );
      await AppLogger.instance.info(
        'HelpContentAdmin',
        'Help content save succeeded',
        context: {
          'mode': _isCreating ? 'create' : 'update',
          'key': saved.key,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      _showSnackBar(
        _isCreating
            ? 'Đã tạo trang hướng dẫn mới.'
            : 'Đã cập nhật nội dung hướng dẫn.',
      );
      await _load(
        reason: _isCreating ? 'create_save' : 'update_save',
        preferredKey: saved.key,
        logOpenEditor: false,
      );
    } on ApiException catch (error) {
      await AppLogger.instance.warn(
        'HelpContentAdmin',
        'Help content save failed',
        context: {
          'mode': _isCreating ? 'create' : 'update',
          'key': key,
          'message': error.message,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) _showSnackBar(error.message);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'HelpContentAdmin',
        'Help content save failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'mode': _isCreating ? 'create' : 'update',
          'key': key,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        _showSnackBar('Chưa lưu được nội dung hướng dẫn. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _restoreFromDocs() async {
    final confirmed = await _confirmRestoreFromDocs();
    if (confirmed != true) return;

    final startedAt = DateTime.now();
    setState(() => _restoring = true);
    await AppLogger.instance.info(
      'HelpContentAdmin',
      'Help content restore from docs started',
      context: {'overwriteExisting': true},
    );
    try {
      final result = await _repository.restoreFromDocs();
      await AppLogger.instance.info(
        'HelpContentAdmin',
        'Help content restore from docs succeeded',
        context: {
          'pageCount': result.pageCount,
          'sourcePath': result.sourcePath,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      _showSnackBar(
        'Đã khôi phục ${result.pageCount} trang từ docs/help hiện tại.',
      );
      await _load(
        reason: 'restore_from_docs',
        preferredKey: 'guide',
        logOpenEditor: false,
      );
    } on ApiException catch (error) {
      await AppLogger.instance.warn(
        'HelpContentAdmin',
        'Help content restore from docs failed',
        context: {
          'message': error.message,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) _showSnackBar(error.message);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'HelpContentAdmin',
        'Help content restore from docs failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        _showSnackBar('Chưa khôi phục được dữ liệu hướng dẫn.');
      }
    } finally {
      if (mounted) {
        setState(() => _restoring = false);
      }
    }
  }

  void _startCreateDraft({bool logEvent = true}) {
    setState(() {
      _isCreating = true;
      _selectedKey = null;
      _selectedParentKey = null;
      _isPublished = true;
      _keyController.clear();
      _titleController.clear();
      _fileNameController.clear();
      _sortOrderController.text = _pages
          .where((page) => page.parentKey == null)
          .length
          .toString();
      _markdownController.clear();
    });
    if (logEvent) {
      unawaited(
        AppLogger.instance.info(
          'HelpContentAdmin',
          'Help content editor opened',
          context: {'mode': 'create'},
        ),
      );
    }
  }

  void _applyPageToEditor(HelpContentPage page, {bool logEvent = true}) {
    setState(() {
      _isCreating = false;
      _selectedKey = page.key;
      _selectedParentKey = page.parentKey;
      _isPublished = page.isPublished;
      _keyController.text = page.key;
      _titleController.text = page.title;
      _fileNameController.text = page.fileName;
      _sortOrderController.text = page.sortOrder.toString();
      _markdownController.text = page.markdown;
    });
    if (logEvent) {
      unawaited(
        AppLogger.instance.info(
          'HelpContentAdmin',
          'Help content editor opened',
          context: {
            'mode': 'edit',
            'key': page.key,
            'isPublished': page.isPublished,
          },
        ),
      );
    }
  }

  String? _resolvePreferredKey(
    List<HelpContentPage> pages,
    String? preferredKey,
  ) {
    if (preferredKey != null && pages.any((page) => page.key == preferredKey)) {
      return preferredKey;
    }
    if (_selectedKey != null && pages.any((page) => page.key == _selectedKey)) {
      return _selectedKey;
    }
    return pages.isEmpty ? null : pages.first.key;
  }

  Future<bool?> _confirmRestoreFromDocs() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Khôi phục từ docs/help?'),
        content: const Text(
          'Thao tác này sẽ ghi đè toàn bộ nội dung runtime hiện tại bằng dữ liệu trong docs/help.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HelpContentHeader(
            loading: _loading,
            saving: _saving,
            restoring: _restoring,
            totalPages: _pages.length,
            publishedCount: _pages.where((page) => page.isPublished).length,
            draftCount: _pages.where((page) => !page.isPublished).length,
            updatedAt: _pages.isEmpty
                ? null
                : _pages
                      .map((page) => page.updatedAt)
                      .whereType<DateTime>()
                      .fold<DateTime?>(null, (latest, value) {
                        if (latest == null || value.isAfter(latest)) {
                          return value;
                        }
                        return latest;
                      }),
            onRefresh: _loading
                ? null
                : () => _load(reason: 'manual_refresh', logOpenEditor: false),
            onCreatePage: _saving || _restoring ? null : _startCreateDraft,
            onRestoreFromDocs: _loading || _saving || _restoring
                ? null
                : _restoreFromDocs,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppSurfaceCard(
        child: AppStatePanel.loading(
          title: 'Đang tải nội dung hướng dẫn',
          message: 'Hệ thống đang đồng bộ danh sách trang và nội dung runtime.',
        ),
      );
    }

    if (_errorMessage != null) {
      return AppSurfaceCard(
        child: AppStatePanel.error(
          title: 'Chưa tải được nội dung hướng dẫn',
          message: _errorMessage,
          actionLabel: 'Thử lại',
          actionIcon: Icons.refresh_rounded,
          onAction: () => _load(reason: 'retry', logOpenEditor: false),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 960;
        final listCard = _HelpContentPageListCard(
          pages: _pages,
          selectedKey: _selectedKey,
          isCreating: _isCreating,
          onSelectPage: (page) => _applyPageToEditor(page),
          onCreatePage: _saving || _restoring ? null : _startCreateDraft,
        );
        final editorCard = _HelpContentEditorCard(
          formKey: _formKey,
          isCreating: _isCreating,
          isSaving: _saving,
          selectedPage: _selectedPage,
          keyController: _keyController,
          titleController: _titleController,
          fileNameController: _fileNameController,
          sortOrderController: _sortOrderController,
          markdownController: _markdownController,
          selectedParentKey: _selectedParentKey,
          isPublished: _isPublished,
          availableParents: _availableParentPages,
          onParentChanged: (value) =>
              setState(() => _selectedParentKey = value),
          onPublishedChanged: (value) => setState(() => _isPublished = value),
          onSave: _saving || _restoring ? null : _save,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              listCard,
              const SizedBox(height: AppLayoutTokens.cardGap),
              editorCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 340, child: listCard),
            const SizedBox(width: AppLayoutTokens.cardGap),
            Expanded(child: editorCard),
          ],
        );
      },
    );
  }

  HelpContentPage? get _selectedPage {
    if (_selectedKey == null) return null;
    for (final page in _pages) {
      if (page.key == _selectedKey) return page;
    }
    return null;
  }

  List<HelpContentPage> get _availableParentPages =>
      _pages.where((page) => page.key != _selectedKey).toList(growable: false);
}

class _HelpContentHeader extends StatelessWidget {
  const _HelpContentHeader({
    required this.loading,
    required this.saving,
    required this.restoring,
    required this.totalPages,
    required this.publishedCount,
    required this.draftCount,
    required this.updatedAt,
    required this.onRefresh,
    required this.onCreatePage,
    required this.onRestoreFromDocs,
  });

  final bool loading;
  final bool saving;
  final bool restoring;
  final int totalPages;
  final int publishedCount;
  final int draftCount;
  final DateTime? updatedAt;
  final VoidCallback? onRefresh;
  final VoidCallback? onCreatePage;
  final VoidCallback? onRestoreFromDocs;

  @override
  Widget build(BuildContext context) {
    final actions = [
      SizedBox(
        width: 180,
        child: AppSecondaryButton(
          onPressed: onRefresh,
          icon: Icons.refresh_rounded,
          label: 'Tải lại',
          isLoading: loading,
          loadingLabel: 'Đang tải',
          expand: false,
        ),
      ),
      SizedBox(
        width: 180,
        child: AppSecondaryButton(
          onPressed: onCreatePage,
          icon: Icons.note_add_outlined,
          label: 'Tạo trang',
          expand: false,
        ),
      ),
      SizedBox(
        width: 220,
        child: AppSecondaryButton(
          onPressed: onRestoreFromDocs,
          icon: Icons.restore_page_outlined,
          label: 'Khôi phục từ docs',
          isLoading: restoring,
          loadingLabel: 'Đang khôi phục',
          expand: false,
        ),
      ),
    ];

    return AppSurfaceCard(
      key: const Key('help-content-admin-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quản lý hướng dẫn', style: AppTextStyles.headingM),
          const SizedBox(height: 6),
          Text(
            'Super Admin có thể chỉnh sửa nội dung runtime và khôi phục nhanh từ docs/help khi cần rollback.',
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppStatusChip(
                label: '$totalPages trang',
                color: AppColors.primary,
              ),
              AppStatusChip(
                label: '$publishedCount đang xuất bản',
                color: AppColors.success,
              ),
              AppStatusChip(
                label: '$draftCount bản nháp',
                color: AppColors.warning,
              ),
              if (updatedAt != null)
                AppStatusChip(
                  label:
                      'Cập nhật ${DateFormat('HH:mm dd/MM').format(updatedAt!.toLocal())}',
                  color: AppColors.neutral700,
                ),
              const AppStatusChip(
                label: 'Chỉ Super Admin',
                color: AppColors.neutral700,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ),
    );
  }
}

class _HelpContentPageListCard extends StatelessWidget {
  const _HelpContentPageListCard({
    required this.pages,
    required this.selectedKey,
    required this.isCreating,
    required this.onSelectPage,
    required this.onCreatePage,
  });

  final List<HelpContentPage> pages;
  final String? selectedKey;
  final bool isCreating;
  final ValueChanged<HelpContentPage> onSelectPage;
  final VoidCallback? onCreatePage;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Danh sách trang', style: AppTextStyles.headingS),
              ),
              TextButton.icon(
                onPressed: onCreatePage,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Trang mới'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (pages.isEmpty)
            const AppStatePanel.empty(
              title: 'Chưa có trang hướng dẫn',
              message: 'Tạo trang đầu tiên hoặc khôi phục từ docs/help.',
              icon: Icons.menu_book_outlined,
            )
          else
            Column(
              children: [
                for (final page in pages) ...[
                  _HelpContentPageListItem(
                    page: page,
                    selected: !isCreating && page.key == selectedKey,
                    depth: _depthOf(page, pages),
                    onTap: () => onSelectPage(page),
                  ),
                  if (page != pages.last)
                    const SizedBox(height: AppLayoutTokens.formInlineGap),
                ],
              ],
            ),
        ],
      ),
    );
  }

  static int _depthOf(HelpContentPage page, List<HelpContentPage> pages) {
    final lookup = {for (final item in pages) item.key: item};
    var depth = 0;
    var parentKey = page.parentKey;
    final visited = <String>{page.key};
    while (parentKey != null && lookup[parentKey] != null && depth < 6) {
      if (!visited.add(parentKey)) break;
      depth += 1;
      parentKey = lookup[parentKey]?.parentKey;
    }
    return depth;
  }
}

class _HelpContentPageListItem extends StatelessWidget {
  const _HelpContentPageListItem({
    required this.page,
    required this.selected,
    required this.depth,
    required this.onTap,
  });

  final HelpContentPage page;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primary.withValues(alpha: 0.30)
        : AppColors.borderOf(context);
    final backgroundColor = selected
        ? AppColors.primary.withValues(alpha: 0.06)
        : AppColors.cardOf(context);

    return InkWell(
      key: Key('help-content-page-item-${page.key}'),
      borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: depth * 12),
              Icon(
                page.isPublished
                    ? Icons.menu_book_outlined
                    : Icons.edit_note_outlined,
                color: page.isPublished ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(page.title, style: AppTextStyles.labelL),
                    const SizedBox(height: 4),
                    Text(
                      page.parentKey == null
                          ? '${page.key} • Trang gốc'
                          : '${page.key} • Thuộc ${page.parentKey}',
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppStatusChip(
                label: page.isPublished ? 'Đang mở' : 'Nháp',
                color: page.isPublished ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpContentEditorCard extends StatelessWidget {
  const _HelpContentEditorCard({
    required this.formKey,
    required this.isCreating,
    required this.isSaving,
    required this.selectedPage,
    required this.keyController,
    required this.titleController,
    required this.fileNameController,
    required this.sortOrderController,
    required this.markdownController,
    required this.selectedParentKey,
    required this.isPublished,
    required this.availableParents,
    required this.onParentChanged,
    required this.onPublishedChanged,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final bool isCreating;
  final bool isSaving;
  final HelpContentPage? selectedPage;
  final TextEditingController keyController;
  final TextEditingController titleController;
  final TextEditingController fileNameController;
  final TextEditingController sortOrderController;
  final TextEditingController markdownController;
  final String? selectedParentKey;
  final bool isPublished;
  final List<HelpContentPage> availableParents;
  final ValueChanged<String?> onParentChanged;
  final ValueChanged<bool> onPublishedChanged;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Form(
        key: formKey,
        child: AppFormColumn(
          children: [
            Text(
              isCreating ? 'Tạo trang hướng dẫn' : 'Chỉnh sửa nội dung',
              style: AppTextStyles.headingS,
            ),
            Text(
              isCreating
                  ? 'Tạo một trang markdown mới cho runtime help. Khóa trang sẽ được giữ cố định sau khi tạo.'
                  : 'Cập nhật nội dung runtime. Lưu xong API public sẽ thấy thay đổi ngay.',
              style: AppTextStyles.bodyM.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            if (selectedPage != null) _HelpContentMetaWrap(page: selectedPage!),
            AppFormTextInput(
              controller: keyController,
              label: 'Khóa trang',
              readOnly: !isCreating,
              helperText: isCreating
                  ? 'Dùng chữ thường, số và dấu gạch ngang. Ví dụ: quy-trinh-moi'
                  : 'Khóa trang đang được giữ cố định để không làm gãy cấu trúc.',
              validator: (value) {
                final text = value?.trim().toLowerCase() ?? '';
                if (text.isEmpty) return 'Nhập khóa trang.';
                final valid = RegExp(r'^[a-z0-9-]+$').hasMatch(text);
                if (!valid) return 'Chỉ dùng chữ thường, số và dấu gạch ngang.';
                return null;
              },
            ),
            AppFormTextInput(
              controller: titleController,
              label: 'Tiêu đề hiển thị',
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Nhập tiêu đề trang.';
                }
                return null;
              },
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final fileNameField = AppFormTextInput(
                  controller: fileNameController,
                  label: 'Tệp markdown tham chiếu',
                  helperText: 'Để trống sẽ tự sinh từ khóa trang.',
                );
                final sortOrderField = AppFormTextInput(
                  controller: sortOrderController,
                  label: 'Thứ tự hiển thị',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final number = int.tryParse((value ?? '').trim());
                    if (number == null) return 'Nhập số thứ tự.';
                    if (number < 0) return 'Thứ tự phải từ 0 trở lên.';
                    return null;
                  },
                );

                if (compact) {
                  return AppFormColumn(
                    children: [fileNameField, sortOrderField],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: fileNameField),
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                    Expanded(child: sortOrderField),
                  ],
                );
              },
            ),
            AppSelectField<String?>(
              label: 'Trang cha',
              value: selectedParentKey,
              onChanged: onParentChanged,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Không có, hiển thị ở cấp gốc'),
                ),
                for (final page in availableParents)
                  DropdownMenuItem<String?>(
                    value: page.key,
                    child: Text('${page.title} (${page.key})'),
                  ),
              ],
            ),
            SwitchListTile.adaptive(
              value: isPublished,
              contentPadding: EdgeInsets.zero,
              title: const Text('Cho phép hiển thị công khai'),
              subtitle: Text(
                isPublished
                    ? 'API public sẽ trả về trang này ngay sau khi lưu.'
                    : 'Giữ ở trạng thái nháp để chưa hiển thị ra public.',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              onChanged: onPublishedChanged,
            ),
            AppFormTextInput(
              controller: markdownController,
              label: 'Nội dung markdown',
              maxLines: 18,
              minLines: 12,
              alignLabelWithHint: true,
              textCapitalization: TextCapitalization.sentences,
              validator: (value) {
                if ((value ?? '').isEmpty) return 'Nhập nội dung markdown.';
                return null;
              },
            ),
            SizedBox(
              width: 220,
              child: AppPrimaryButton(
                onPressed: onSave,
                icon: isCreating
                    ? Icons.note_add_outlined
                    : Icons.save_outlined,
                label: isCreating ? 'Tạo trang' : 'Lưu thay đổi',
                isLoading: isSaving,
                loadingLabel: 'Đang lưu',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpContentMetaWrap extends StatelessWidget {
  const _HelpContentMetaWrap({required this.page});

  final HelpContentPage page;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (page.updatedByEmail != null)
          AppStatusChip(
            label: 'Cập nhật bởi ${page.updatedByEmail}',
            color: AppColors.info,
          ),
        if (page.updatedAt != null)
          AppStatusChip(
            label:
                'Lưu lúc ${DateFormat('HH:mm dd/MM').format(page.updatedAt!.toLocal())}',
            color: AppColors.neutral700,
          ),
        if (page.seededFromDocsAt != null)
          AppStatusChip(
            label: 'Có seed từ docs/help',
            color: AppColors.secondary,
          ),
      ],
    );
  }
}
