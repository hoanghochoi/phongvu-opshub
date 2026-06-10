import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/admin_personnel_definition.dart';

class StoreAdminScreen extends StatefulWidget {
  const StoreAdminScreen({super.key});

  @override
  State<StoreAdminScreen> createState() => _StoreAdminScreenState();
}

class _StoreAdminScreenState extends State<StoreAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  final _searchController = TextEditingController();
  List<StoreBranch> _stores = [];
  List<AdminAreaDefinition> _areas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repository.listAdminStores(query: _searchController.text),
        _repository.listAdminAreas(),
      ]);
      if (!mounted) return;
      setState(() {
        _stores = results[0] as List<StoreBranch>;
        _areas = results[1] as List<AdminAreaDefinition>;
      });
    } catch (error) {
      if (mounted) {
        _showMessage('Chưa tải được danh sách showroom. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([StoreBranch? store]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _StoreEditorDialog(
        repository: _repository,
        store: store,
        areas: _areas,
        currentRole: context.read<AuthProvider>().user?.role,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _deleteStore(StoreBranch store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa showroom'),
        content: Text('Xóa showroom ${store.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Hủy',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Xóa',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repository.deleteAdminStore(store.storeId);
      await _load();
      if (mounted) _showMessage('Đã xóa ${store.storeId}');
    } catch (error) {
      if (mounted) _showMessage('Chưa xóa được showroom. Vui lòng thử lại.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select<AuthProvider, String?>(
      (auth) => auth.user?.role,
    );
    final canCreateStores = role == 'SUPER_ADMIN';
    final canEditStores =
        role == 'SUPER_ADMIN' ||
        role == 'MANAGER' ||
        role == 'ADMIN_PHONGVU' ||
        role == 'ADMIN_ACARE';

    return Scaffold(
      appBar: GradientHeader(
        title: 'Quản lý showroom',
        showBack: true,
        actions: canCreateStores
            ? [
                IconButton(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_business_outlined),
                  tooltip: 'Thêm showroom',
                ),
              ]
            : null,
      ),
      body: AppResponsiveContent(
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm mã, tên, tài khoản hoặc ngân hàng',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: AppIconAction(
                  onPressed: _load,
                  icon: Icons.refresh,
                  tooltip: 'Tải lại',
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _stores.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final store = _stores[index];
                          return _StoreCard(
                            store: store,
                            onEdit: canEditStores
                                ? () => _openEditor(store)
                                : null,
                            onDelete: canCreateStores && store.userCount == 0
                                ? () => _deleteStore(store)
                                : null,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final StoreBranch store;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _StoreCard({
    required this.store,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final account = [
      if ((store.transferBankName ?? '').isNotEmpty) store.transferBankName,
      if ((store.transferAccountNumber ?? '').isNotEmpty)
        store.transferAccountNumber,
    ].whereType<String>().join(' • ');
    final mapAccount = [
      if ((store.mapVietinUsername ?? '').isNotEmpty)
        'Tài khoản tiền vào: ${store.mapVietinUsername}',
      if (store.hasMapVietinPassword) 'đã lưu mật khẩu',
    ].join(' • ');

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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.store_mall_directory_outlined,
                color: Color(0xFF059669),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.isEmpty
                            ? '${store.userCount} người dùng'
                            : account,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                      if (mapAccount.isNotEmpty)
                        Text(
                          mapAccount,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.teal[300]!
                                : const Color(0xFF0F766E),
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        store.regionAreaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppIconAction(
              onPressed: onEdit,
              icon: Icons.edit_outlined,
              tooltip: 'Sửa showroom',
            ),
            const SizedBox(width: 8),
            AppIconAction(
              onPressed: onDelete,
              icon: Icons.delete_outline,
              tooltip: store.userCount == 0
                  ? 'Xóa showroom'
                  : 'Showroom đang có người dùng',
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final StoreBranch? store;
  final List<AdminAreaDefinition> areas;
  final String? currentRole;

  const _StoreEditorDialog({
    required this.repository,
    required this.areas,
    required this.currentRole,
    this.store,
  });

  @override
  State<_StoreEditorDialog> createState() => _StoreEditorDialogState();
}

class _StoreEditorDialogState extends State<_StoreEditorDialog> {
  final _storeIdController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankBinController = TextEditingController();
  final _mapUsernameController = TextEditingController();
  final _mapPasswordController = TextEditingController();
  String? _areaCode;
  bool _saving = false;

  bool get _isScopedMapEditor =>
      widget.store != null &&
      (widget.currentRole == 'ADMIN_PHONGVU' ||
          widget.currentRole == 'ADMIN_ACARE');

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    _storeIdController.text = store?.storeId ?? '';
    _storeNameController.text = store?.storeName ?? '';
    _accountNumberController.text = store?.transferAccountNumber ?? '';
    _accountNameController.text = store?.transferAccountName ?? '';
    _bankNameController.text = store?.transferBankName ?? '';
    _bankBinController.text = store?.transferBankBin ?? '';
    _mapUsernameController.text = store?.mapVietinUsername ?? '';
    _areaCode = store?.areaCode;
  }

  @override
  void dispose() {
    _storeIdController.dispose();
    _storeNameController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    _bankNameController.dispose();
    _bankBinController.dispose();
    _mapUsernameController.dispose();
    _mapPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final store = widget.store;
    final mapPasswordProvided = _mapPasswordController.text.trim().isNotEmpty;
    try {
      final body = _isScopedMapEditor
          ? <String, dynamic>{
              'mapVietinUsername': _mapUsernameController.text.trim(),
              if (mapPasswordProvided)
                'mapVietinPassword': _mapPasswordController.text.trim(),
            }
          : <String, dynamic>{
              'storeId': _storeIdController.text.trim().toUpperCase(),
              'storeName': _storeNameController.text.trim(),
              'areaCode': _areaCode,
              'transferAccountNumber': _accountNumberController.text.trim(),
              'transferAccountName': _accountNameController.text.trim(),
              'transferBankName': _bankNameController.text.trim(),
              'transferBankBin': _bankBinController.text.trim(),
              'mapVietinUsername': _mapUsernameController.text.trim(),
              if (mapPasswordProvided)
                'mapVietinPassword': _mapPasswordController.text.trim(),
            };

      await AppLogger.instance.info(
        'StoreAdmin',
        'Store save started',
        context: {
          'role': widget.currentRole,
          'storeId': store?.storeId ?? body['storeId'],
          'mode': store == null ? 'create' : 'update',
          'mapOnly': _isScopedMapEditor,
          'mapUsernameChanged': body.containsKey('mapVietinUsername'),
          'mapPasswordProvided': mapPasswordProvided,
        },
      );

      if (store == null) {
        await widget.repository.createAdminStore(body);
      } else {
        await widget.repository.updateAdminStore(store.storeId, body);
      }
      await AppLogger.instance.info(
        'StoreAdmin',
        'Store save succeeded',
        context: {
          'role': widget.currentRole,
          'storeId': store?.storeId ?? body['storeId'],
          'mode': store == null ? 'create' : 'update',
          'mapOnly': _isScopedMapEditor,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      await AppLogger.instance.error(
        'StoreAdmin',
        'Store save failed',
        error: error,
        context: {
          'role': widget.currentRole,
          'storeId': store?.storeId,
          'mode': store == null ? 'create' : 'update',
          'mapOnly': _isScopedMapEditor,
        },
      );
      if (mounted) {
        final message = error is ApiException
            ? error.message
            : 'Chưa lưu được showroom. Vui lòng thử lại.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockStoreFields = _isScopedMapEditor;
    return AlertDialog(
      title: Text(widget.store == null ? 'Thêm showroom' : 'Sửa showroom'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AppFormColumn(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _storeIdController,
                decoration: const InputDecoration(labelText: 'Mã showroom'),
                textCapitalization: TextCapitalization.characters,
                enabled: !lockStoreFields,
              ),
              TextField(
                controller: _storeNameController,
                decoration: const InputDecoration(labelText: 'Tên showroom'),
                enabled: !lockStoreFields,
              ),
              DropdownButtonFormField<String?>(
                initialValue: _areaCode,
                decoration: const InputDecoration(labelText: 'Vung/Mien'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Chua gan'),
                  ),
                  ...widget.areas.map(
                    (area) => DropdownMenuItem<String?>(
                      value: area.code,
                      child: Text('${area.abbreviation} - ${area.title}'),
                    ),
                  ),
                ],
                onChanged: lockStoreFields
                    ? null
                    : (value) => setState(() => _areaCode = value),
              ),
              TextField(
                controller: _accountNumberController,
                decoration: const InputDecoration(
                  labelText: 'Số tài khoản chuyển khoản',
                ),
                keyboardType: TextInputType.number,
                enabled: !lockStoreFields,
              ),
              TextField(
                controller: _accountNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên tài khoản chuyển khoản',
                ),
                enabled: !lockStoreFields,
              ),
              TextField(
                controller: _bankNameController,
                decoration: const InputDecoration(labelText: 'Ngân hàng'),
                enabled: !lockStoreFields,
              ),
              TextField(
                controller: _bankBinController,
                decoration: const InputDecoration(labelText: 'BIN ngân hàng'),
                keyboardType: TextInputType.number,
                enabled: !lockStoreFields,
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              TextField(
                controller: _mapUsernameController,
                decoration: const InputDecoration(
                  labelText: 'Tài khoản nhận tiền VietinBank',
                ),
              ),
              TextField(
                controller: _mapPasswordController,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu tài khoản nhận tiền',
                  helperText: widget.store?.hasMapVietinPassword == true
                      ? 'Để trống nếu muốn giữ mật khẩu hiện tại'
                      : null,
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            'Hủy',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving ? 'Đang lưu...' : 'Lưu',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}
