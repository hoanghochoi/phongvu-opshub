import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/fifo_log_repository.dart';
import '../widgets/fifo_item_card.dart';
import '../widgets/fifo_search_bar.dart';
import '../widgets/fifo_tab_bar.dart';

class FifoHistoryScreen extends StatefulWidget {
  const FifoHistoryScreen({super.key});

  @override
  State<FifoHistoryScreen> createState() => _FifoHistoryScreenState();
}

class _FifoHistoryScreenState extends State<FifoHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late FifoLogRepository _fifoLogRepo;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _userFilterController = TextEditingController();

  final List<FifoLogItem> _checkLogs = [];
  final List<FifoLogItem> _sortLogs = [];
  int _checkTotal = 0;
  int _sortTotal = 0;
  int _checkPage = 1;
  int _sortPage = 1;
  bool _checkLoading = false;
  bool _sortLoading = false;
  String? _searchQuery;
  String? _filterUser;
  final int _limit = 20;
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fifoLogRepo = FifoLogRepository(ApiClient());
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0 && _checkLogs.isEmpty && !_checkLoading) {
          _loadCheckLogs();
        } else if (_tabController.index == 1 &&
            _sortLogs.isEmpty &&
            !_sortLoading) {
          _loadSortLogs();
        }
      }
    });
    // Wait for AuthProvider to finish initializing (JWT token restoration)
    _waitForAuthAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _userFilterController.dispose();
    super.dispose();
  }

  /// Wait for AuthProvider to finish restoring JWT token before loading logs
  Future<void> _waitForAuthAndLoad() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isInitialized) {
      _loadCheckLogs();
      return;
    }
    // Listen for initialization to complete
    void listener() {
      if (authProvider.isInitialized) {
        authProvider.removeListener(listener);
        if (mounted) _loadCheckLogs();
      }
    }

    authProvider.addListener(listener);
  }

  void _onSearch() {
    final q = _searchController.text.trim();
    final u = _userFilterController.text.trim();
    setState(() {
      _searchQuery = q.isEmpty ? null : q;
      _filterUser = u.isEmpty ? null : u;
    });
    if (_tabController.index == 0) {
      _loadCheckLogs();
    } else {
      _loadSortLogs();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _userFilterController.clear();
    setState(() {
      _searchQuery = null;
      _filterUser = null;
    });
    if (_tabController.index == 0) {
      _loadCheckLogs();
    } else {
      _loadSortLogs();
    }
  }

  Future<void> _loadCheckLogs({bool loadMore = false}) async {
    if (_checkLoading) return;
    setState(() => _checkLoading = true);

    final page = loadMore ? _checkPage + 1 : 1;
    final result = await _fifoLogRepo.getAdminLogs(
      type: 'FIFO_CHECK',
      page: page,
      limit: _limit,
      search: _searchQuery,
      filterUserEmail: _filterUser,
    );

    setState(() {
      if (loadMore) {
        _checkLogs.addAll(result['data'] as List<FifoLogItem>);
      } else {
        _checkLogs.clear();
        _checkLogs.addAll(result['data'] as List<FifoLogItem>);
      }
      _checkTotal = result['total'] as int;
      _checkPage = page;
      _checkLoading = false;
    });
  }

  Future<void> _loadSortLogs({bool loadMore = false}) async {
    if (_sortLoading) return;
    setState(() => _sortLoading = true);

    final page = loadMore ? _sortPage + 1 : 1;
    final result = await _fifoLogRepo.getAdminLogs(
      type: 'FIFO_SORT',
      page: page,
      limit: _limit,
      search: _searchQuery,
      filterUserEmail: _filterUser,
    );

    setState(() {
      if (loadMore) {
        _sortLogs.addAll(result['data'] as List<FifoLogItem>);
      } else {
        _sortLogs.clear();
        _sortLogs.addAll(result['data'] as List<FifoLogItem>);
      }
      _sortTotal = result['total'] as int;
      _sortPage = page;
      _sortLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Lịch sử FIFO', showBack: true),
      body: AppResponsiveContent(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            FifoHistorySearchBar(
              searchController: _searchController,
              userFilterController: _userFilterController,
              onSearch: _onSearch,
              onClearFilter: _clearSearch,
              totalCount: _tabController.index == 0 ? _checkTotal : _sortTotal,
              searchQuery: _searchQuery,
              filterUser: _filterUser,
            ),
            FifoHistoryTabBar(controller: _tabController),
            const SizedBox(height: 8),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLogList(
                    _checkLogs,
                    _checkLoading,
                    _checkLogs.length < _checkTotal,
                    () => _loadCheckLogs(loadMore: true),
                    () => _loadCheckLogs(),
                  ),
                  _buildLogList(
                    _sortLogs,
                    _sortLoading,
                    _sortLogs.length < _sortTotal,
                    () => _loadSortLogs(loadMore: true),
                    () => _loadSortLogs(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList(
    List<FifoLogItem> logs,
    bool loading,
    bool hasMore,
    VoidCallback onLoadMore,
    VoidCallback onRefresh,
  ) {
    if (loading && logs.isEmpty) {
      return const AppStatePanel.loading(title: 'Đang tải lịch sử FIFO');
    }

    if (logs.isEmpty) {
      return AppStatePanel.empty(
        title: _searchQuery != null || _filterUser != null
            ? 'Không tìm thấy kết quả'
            : 'Chưa có lịch sử',
        icon: Icons.inbox_rounded,
        actionLabel: 'Tải lại',
        onAction: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: logs.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == logs.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : AppDialogSecondaryButton(
                        onPressed: onLoadMore,
                        icon: Icons.expand_more,
                        label: 'Xem thêm',
                      ),
              ),
            );
          }

          final log = logs[index];
          return FifoItemCard(
            log: log,
            isExpanded: _expandedIds.contains(log.id),
            onTap: () {
              setState(() {
                if (_expandedIds.contains(log.id)) {
                  _expandedIds.remove(log.id);
                } else {
                  _expandedIds.add(log.id);
                }
              });
            },
          );
        },
      ),
    );
  }
}
