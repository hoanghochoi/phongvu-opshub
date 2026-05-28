import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/store_branch.dart';
import '../providers/auth_provider.dart';

class StoreSelectionScreen extends StatefulWidget {
  const StoreSelectionScreen({super.key});

  @override
  State<StoreSelectionScreen> createState() => _StoreSelectionScreenState();
}

class _StoreSelectionScreenState extends State<StoreSelectionScreen> {
  final _repository = AuthRepository(ApiClient());
  final _searchController = TextEditingController();
  List<StoreBranch> _stores = [];
  StoreBranch? _selected;
  bool _loading = true;
  Timer? _searchDebounce;
  int _loadSequence = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadStores();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _loadStores);
  }

  Future<void> _loadStores() async {
    final sequence = ++_loadSequence;
    setState(() => _loading = true);
    try {
      final stores = await _repository.getStores(query: _searchController.text);
      if (!mounted || sequence != _loadSequence) return;
      setState(() {
        _stores = stores;
        if (_selected != null &&
            !stores.any((store) => store.storeId == _selected!.storeId)) {
          _selected = null;
        }
      });
    } finally {
      if (mounted && sequence == _loadSequence) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirm() async {
    final selected = _selected;
    if (selected == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Khóa chi nhánh?'),
        content: Text(
          'Bạn đang chọn ${selected.displayName}. Thông tin chi nhánh sẽ không thay đổi được sau khi xác nhận.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Xem lại',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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
    if (ok != true || !mounted) return;

    final success = await context.read<AuthProvider>().selectStore(
      selected.storeId,
    );
    if (!success && mounted) {
      final error =
          context.read<AuthProvider>().errorMessage ??
          'Không chọn được chi nhánh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Chọn chi nhánh'),
      body: AppResponsiveContent(
        maxWidth: AppLayoutTokens.formMaxWidth,
        child: Column(
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline),
                    SizedBox(width: AppLayoutTokens.formInlineGap),
                    Expanded(
                      child: Text(
                        'Chọn chi nhánh lần đầu đăng nhập. Sau khi xác nhận, chi nhánh sẽ bị khóa.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm mã hoặc tên chi nhánh',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _loadStores,
                  icon: const Icon(Icons.refresh),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _loadStores(),
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: _stores.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppLayoutTokens.cardGap),
                      itemBuilder: (context, index) {
                        final store = _stores[index];
                        return ListTile(
                          leading: Icon(
                            _selected?.storeId == store.storeId
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          onTap: () => setState(() => _selected = store),
                          title: Text(store.displayName),
                          subtitle: Text(
                            [
                              store.transferBankName,
                              store.transferAccountNumber,
                            ].whereType<String>().join(' - '),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: AppLayoutTokens.formSectionGap),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selected == null ? null : _confirm,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'Xác nhận chi nhánh',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
