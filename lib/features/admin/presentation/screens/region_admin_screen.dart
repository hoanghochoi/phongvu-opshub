import 'package:flutter/material.dart';

import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_personnel_definition.dart';

class RegionAdminScreen extends StatefulWidget {
  const RegionAdminScreen({super.key});

  @override
  State<RegionAdminScreen> createState() => _RegionAdminScreenState();
}

class _RegionAdminScreenState extends State<RegionAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminRegionDefinition> _regions = [];
  List<AdminAreaDefinition> _areas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info('AdminRegions', 'Catalog load started');
      final results = await Future.wait([
        _repository.listAdminRegions(),
        _repository.listAdminAreas(),
      ]);
      if (!mounted) return;
      setState(() {
        _regions = results[0];
        _areas = results[1] as List<AdminAreaDefinition>;
      });
      await AppLogger.instance.info(
        'AdminRegions',
        'Catalog load succeeded',
        context: {
          'regions': _regions.length,
          'areas': _areas.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminRegions',
        'Catalog load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
      if (mounted) _showMessage('Chưa tải được Vùng/Miền. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegionEditor([AdminRegionDefinition? region]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _RegionEditorDialog(repository: _repository, region: region),
    );
    if (updated == true) await _load();
  }

  Future<void> _openAreaEditor([AdminAreaDefinition? area]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _AreaEditorDialog(
        repository: _repository,
        regions: _regions,
        area: area,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _deleteRegion(AdminRegionDefinition region) async {
    final confirmed = await _confirm(
      title: 'Xóa Miền',
      message: 'Xóa Miền ${region.title}?',
    );
    if (!confirmed) return;
    try {
      await AppLogger.instance.warn(
        'AdminRegions',
        'Region delete started',
        context: {'regionCode': region.code},
      );
      await _repository.deleteAdminRegion(region.code);
      await AppLogger.instance.warn(
        'AdminRegions',
        'Region delete succeeded',
        context: {'regionCode': region.code},
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminRegions',
        'Region delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'regionCode': region.code},
      );
      if (mounted) {
        _showMessage('Chưa xóa được Miền. Có thể đang được sử dụng.');
      }
    }
  }

  Future<void> _deleteArea(AdminAreaDefinition area) async {
    final confirmed = await _confirm(
      title: 'Xóa Vùng',
      message: 'Xóa Vùng ${area.title}?',
    );
    if (!confirmed) return;
    try {
      await AppLogger.instance.warn(
        'AdminRegions',
        'Area delete started',
        context: {'areaCode': area.code, 'regionCode': area.regionCode},
      );
      await _repository.deleteAdminArea(area.code);
      await AppLogger.instance.warn(
        'AdminRegions',
        'Area delete succeeded',
        context: {'areaCode': area.code},
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminRegions',
        'Area delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'areaCode': area.code},
      );
      if (mounted) {
        _showMessage('Chưa xóa được Vùng. Có thể đang được sử dụng.');
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Xóa'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: GradientHeader(
          title: 'Quản lý Vùng/Miền',
          showBack: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Miền'),
              Tab(text: 'Vùng'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : () => _openRegionEditor(),
              icon: const Icon(Icons.public_outlined),
              tooltip: 'Thêm Miền',
            ),
            IconButton(
              onPressed: _loading ? null : () => _openAreaEditor(),
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Thêm Vùng',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _CatalogList(
                    emptyText: 'Chưa có Miền',
                    itemCount: _regions.length,
                    itemBuilder: (context, index) {
                      final region = _regions[index];
                      return _RegionCard(
                        title: region.title,
                        code: region.code,
                        abbreviation: region.abbreviation,
                        description: region.description,
                        isSystem: region.isSystem,
                        isActive: region.isActive,
                        metadata:
                            '${region.areaCount} vùng • ${region.userCount} user',
                        icon: Icons.public_outlined,
                        color: const Color(0xFF2563EB),
                        onEdit: () => _openRegionEditor(region),
                        onDelete: region.isSystem
                            ? null
                            : () => _deleteRegion(region),
                      );
                    },
                  ),
                  _CatalogList(
                    emptyText: 'Chưa có Vùng',
                    itemCount: _areas.length,
                    itemBuilder: (context, index) {
                      final area = _areas[index];
                      return _RegionCard(
                        title: area.title,
                        code: area.code,
                        abbreviation: area.abbreviation,
                        description: area.description,
                        isSystem: area.isSystem,
                        isActive: area.isActive,
                        metadata:
                            '${area.regionTitle ?? area.regionCode} • ${area.storeCount} SR • ${area.userCount} user',
                        icon: Icons.map_outlined,
                        color: const Color(0xFF059669),
                        onEdit: () => _openAreaEditor(area),
                        onDelete: area.isSystem
                            ? null
                            : () => _deleteArea(area),
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class _CatalogList extends StatelessWidget {
  final String emptyText;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _CatalogList({
    required this.emptyText,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
      return Center(child: Text(emptyText));
    }
    return AppResponsiveContent(
      padding: EdgeInsets.zero,
      child: RefreshIndicator(
        onRefresh: () async {},
        child: ListView.separated(
          padding: AppLayoutTokens.pagePaddingFor(
            MediaQuery.sizeOf(context).width,
          ),
          itemCount: itemCount,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  final String title;
  final String code;
  final String abbreviation;
  final String description;
  final bool isSystem;
  final bool isActive;
  final String metadata;
  final IconData icon;
  final Color color;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _RegionCard({
    required this.title,
    required this.code,
    required this.abbreviation,
    required this.description,
    required this.isSystem,
    required this.isActive,
    required this.metadata,
    required this.icon,
    required this.color,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$abbreviation - $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description.isEmpty
                        ? '$code • $metadata'
                        : '$code • $metadata • $description',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isActive ? 'Đang bật' : 'Đang tắt'}${isSystem ? ' • hệ thống' : ''}',
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppIconAction(
              onPressed: onEdit,
              icon: Icons.edit_outlined,
              tooltip: 'Sửa',
            ),
            const SizedBox(width: 8),
            AppIconAction(
              onPressed: onDelete,
              icon: Icons.delete_outline,
              tooltip: isSystem ? 'Dòng hệ thống' : 'Xóa',
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminRegionDefinition? region;

  const _RegionEditorDialog({required this.repository, this.region});

  @override
  State<_RegionEditorDialog> createState() => _RegionEditorDialogState();
}

class _RegionEditorDialogState extends State<_RegionEditorDialog> {
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _abbreviationController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final region = widget.region;
    _codeController.text = region?.code ?? '';
    _titleController.text = region?.title ?? '';
    _abbreviationController.text = region?.abbreviation ?? '';
    _descriptionController.text = region?.description ?? '';
    _isActive = region?.isActive ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _abbreviationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final region = AdminRegionDefinition(
      code: _codeController.text.trim().toUpperCase(),
      title: _titleController.text.trim(),
      abbreviation: _abbreviationController.text.trim().toUpperCase(),
      description: _descriptionController.text.trim(),
      isActive: _isActive,
    );
    try {
      await AppLogger.instance.info(
        'AdminRegions',
        'Region save started',
        context: {
          'regionCode': region.code,
          'mode': widget.region == null ? 'create' : 'update',
        },
      );
      final current = widget.region;
      if (current == null) {
        await widget.repository.createAdminRegion(region);
      } else {
        await widget.repository.updateAdminRegion(current.code, region);
      }
      await AppLogger.instance.info(
        'AdminRegions',
        'Region save succeeded',
        context: {'regionCode': region.code},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminRegions',
        'Region save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'regionCode': region.code},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa lưu được Miền. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.region?.isSystem == true;
    return AlertDialog(
      title: Text(widget.region == null ? 'Thêm Miền' : 'Sửa Miền'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AppFormColumn(
            children: [
              TextField(
                controller: _codeController,
                enabled: !isSystem,
                decoration: const InputDecoration(labelText: 'Mã Miền'),
                textCapitalization: TextCapitalization.characters,
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Tên Miền'),
              ),
              TextField(
                controller: _abbreviationController,
                decoration: const InputDecoration(labelText: 'Viết tắt'),
                textCapitalization: TextCapitalization.characters,
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Mô tả'),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Đang bật'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Đang lưu...' : 'Lưu'),
        ),
      ],
    );
  }
}

class _AreaEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final List<AdminRegionDefinition> regions;
  final AdminAreaDefinition? area;

  const _AreaEditorDialog({
    required this.repository,
    required this.regions,
    this.area,
  });

  @override
  State<_AreaEditorDialog> createState() => _AreaEditorDialogState();
}

class _AreaEditorDialogState extends State<_AreaEditorDialog> {
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _abbreviationController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _regionCode;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final area = widget.area;
    _codeController.text = area?.code ?? '';
    _titleController.text = area?.title ?? '';
    _abbreviationController.text = area?.abbreviation ?? '';
    _descriptionController.text = area?.description ?? '';
    _regionCode =
        area?.regionCode ??
        (widget.regions.isEmpty ? null : widget.regions.first.code);
    _isActive = area?.isActive ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _abbreviationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final regionCode = _regionCode;
    if (regionCode == null || regionCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn Miền cho Vùng.')),
      );
      return;
    }
    setState(() => _saving = true);
    final area = AdminAreaDefinition(
      code: _codeController.text.trim().toUpperCase(),
      title: _titleController.text.trim(),
      abbreviation: _abbreviationController.text.trim().toUpperCase(),
      description: _descriptionController.text.trim(),
      regionCode: regionCode,
      isActive: _isActive,
    );
    try {
      await AppLogger.instance.info(
        'AdminRegions',
        'Area save started',
        context: {
          'areaCode': area.code,
          'regionCode': regionCode,
          'mode': widget.area == null ? 'create' : 'update',
        },
      );
      final current = widget.area;
      if (current == null) {
        await widget.repository.createAdminArea(area);
      } else {
        await widget.repository.updateAdminArea(current.code, area);
      }
      await AppLogger.instance.info(
        'AdminRegions',
        'Area save succeeded',
        context: {'areaCode': area.code, 'regionCode': regionCode},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminRegions',
        'Area save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'areaCode': area.code, 'regionCode': regionCode},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa lưu được Vùng. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.area?.isSystem == true;
    return AlertDialog(
      title: Text(widget.area == null ? 'Thêm Vùng' : 'Sửa Vùng'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AppFormColumn(
            children: [
              TextField(
                controller: _codeController,
                enabled: !isSystem,
                decoration: const InputDecoration(labelText: 'Mã Vùng'),
                textCapitalization: TextCapitalization.characters,
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Tên Vùng'),
              ),
              TextField(
                controller: _abbreviationController,
                decoration: const InputDecoration(labelText: 'Viết tắt'),
                textCapitalization: TextCapitalization.characters,
              ),
              DropdownButtonFormField<String>(
                initialValue: _regionCode,
                decoration: const InputDecoration(labelText: 'Miền'),
                items: widget.regions
                    .map(
                      (region) => DropdownMenuItem(
                        value: region.code,
                        child: Text('${region.abbreviation} - ${region.title}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _regionCode = value),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Mô tả'),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Đang bật'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Đang lưu...' : 'Lưu'),
        ),
      ],
    );
  }
}
