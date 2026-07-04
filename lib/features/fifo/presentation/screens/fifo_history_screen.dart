import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/fifo_log_repository.dart';
import '../widgets/fifo_item_card.dart';
import '../widgets/fifo_search_bar.dart';
import '../widgets/fifo_tab_bar.dart';

class FifoHistoryScreen extends StatefulWidget {
  final FifoLogRepository? repository;

  const FifoHistoryScreen({super.key, this.repository});

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
  String? _checkError;
  String? _sortError;
  String? _searchQuery;
  String? _filterUser;
  final int _limit = 20;
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fifoLogRepo = widget.repository ?? FifoLogRepository(ApiClient());
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (mounted) setState(() {});
        if (_tabController.index == 0 && _checkLogs.isEmpty && !_checkLoading) {
          unawaited(_loadCheckLogs());
        } else if (_tabController.index == 1 &&
            _sortLogs.isEmpty &&
            !_sortLoading) {
          unawaited(_loadSortLogs());
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
    unawaited(
      AppLogger.instance.info(
        'FifoHistory',
        'FIFO history filters applied',
        context: {
          'tab': _activeType,
          'searchLength': q.length,
          'hasUserFilter': u.isNotEmpty,
        },
      ),
    );
    if (_tabController.index == 0) {
      unawaited(_loadCheckLogs());
    } else {
      unawaited(_loadSortLogs());
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _userFilterController.clear();
    setState(() {
      _searchQuery = null;
      _filterUser = null;
    });
    unawaited(
      AppLogger.instance.info(
        'FifoHistory',
        'FIFO history filters cleared',
        context: {'tab': _activeType},
      ),
    );
    if (_tabController.index == 0) {
      unawaited(_loadCheckLogs());
    } else {
      unawaited(_loadSortLogs());
    }
  }

  Future<void> _loadCheckLogs({bool loadMore = false}) async {
    await _loadLogs(type: 'FIFO_CHECK', loadMore: loadMore);
  }

  Future<void> _loadSortLogs({bool loadMore = false}) async {
    await _loadLogs(type: 'FIFO_SORT', loadMore: loadMore);
  }

  String get _activeType =>
      _tabController.index == 0 ? 'FIFO_CHECK' : 'FIFO_SORT';

  Future<void> _loadLogs({required String type, required bool loadMore}) async {
    final isCheck = type == 'FIFO_CHECK';
    if (isCheck ? _checkLoading : _sortLoading) return;
    final page = loadMore ? (isCheck ? _checkPage : _sortPage) + 1 : 1;
    final startedAt = DateTime.now();
    setState(() {
      if (isCheck) {
        _checkLoading = true;
        _checkError = null;
      } else {
        _sortLoading = true;
        _sortError = null;
      }
    });
    await AppLogger.instance.info(
      'FifoHistory',
      'FIFO history load started',
      context: {
        'type': type,
        'page': page,
        'loadMore': loadMore,
        'hasSearch': _searchQuery?.isNotEmpty == true,
        'hasUserFilter': _filterUser?.isNotEmpty == true,
      },
    );

    try {
      final result = await _fifoLogRepo.getAdminLogs(
        type: type,
        page: page,
        limit: _limit,
        search: _searchQuery,
        filterUserEmail: _filterUser,
      );
      final items = List<FifoLogItem>.from(result['data'] as List<FifoLogItem>);
      final total = result['total'] as int;
      if (!mounted) return;
      setState(() {
        final target = isCheck ? _checkLogs : _sortLogs;
        if (!loadMore) target.clear();
        target.addAll(items);
        if (isCheck) {
          _checkTotal = total;
          _checkPage = page;
          _checkError = null;
        } else {
          _sortTotal = total;
          _sortPage = page;
          _sortError = null;
        }
      });
      await AppLogger.instance.info(
        'FifoHistory',
        'FIFO history load succeeded',
        context: {
          'type': type,
          'page': page,
          'loadMore': loadMore,
          'count': items.length,
          'total': total,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FifoHistory',
        'FIFO history load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'type': type,
          'page': page,
          'loadMore': loadMore,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        setState(() {
          if (isCheck) {
            _checkError = 'Chưa tải được lịch sử kiểm tra FIFO.';
          } else {
            _sortError = 'Chưa tải được lịch sử sắp xếp FIFO.';
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isCheck) {
            _checkLoading = false;
          } else {
            _sortLoading = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeLoading = _tabController.index == 0
        ? _checkLoading
        : _sortLoading;
    return AppResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FifoHistoryHeader(
            key: const Key('fifo-history-header'),
            checkTotal: _checkTotal,
            sortTotal: _sortTotal,
            loading: activeLoading,
            onReload: () =>
                _tabController.index == 0 ? _loadCheckLogs() : _loadSortLogs(),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          FifoHistorySearchBar(
            key: const Key('fifo-history-filter-card'),
            searchController: _searchController,
            userFilterController: _userFilterController,
            onSearch: _onSearch,
            onClearFilter: _clearSearch,
            totalCount: _tabController.index == 0 ? _checkTotal : _sortTotal,
            searchQuery: _searchQuery,
            filterUser: _filterUser,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          FifoHistoryTabBar(
            key: const Key('fifo-history-tabs'),
            controller: _tabController,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          Expanded(
            key: const Key('fifo-history-tab-view'),
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLogList(
                  _checkLogs,
                  _checkLoading,
                  _checkError,
                  _checkLogs.length < _checkTotal,
                  () => _loadCheckLogs(loadMore: true),
                  () => _loadCheckLogs(),
                ),
                _buildLogList(
                  _sortLogs,
                  _sortLoading,
                  _sortError,
                  _sortLogs.length < _sortTotal,
                  () => _loadSortLogs(loadMore: true),
                  () => _loadSortLogs(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(
    List<FifoLogItem> logs,
    bool loading,
    String? error,
    bool hasMore,
    VoidCallback onLoadMore,
    VoidCallback onRefresh,
  ) {
    if (loading && logs.isEmpty) {
      return const _FifoHistoryStateViewport(
        child: AppStatePanel.loading(title: 'Đang tải lịch sử FIFO'),
      );
    }

    if (error != null && logs.isEmpty) {
      return _FifoHistoryStateViewport(
        child: AppStatePanel.error(
          key: const Key('fifo-history-error'),
          title: error,
          message: 'Kiểm tra kết nối rồi thử tải lại.',
          actionLabel: 'Thử tải lại',
          actionIcon: Icons.refresh_outlined,
          onAction: onRefresh,
          compact: true,
        ),
      );
    }

    if (logs.isEmpty) {
      return _FifoHistoryStateViewport(
        child: AppStatePanel.empty(
          title: _searchQuery != null || _filterUser != null
              ? 'Không tìm thấy kết quả'
              : 'Chưa có lịch sử',
          icon: Icons.inbox_rounded,
          actionLabel: 'Tải lại',
          onAction: onRefresh,
          compact: true,
        ),
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
            key: ValueKey('fifo-history-item-${log.id}'),
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

class _FifoHistoryStateViewport extends StatelessWidget {
  const _FifoHistoryStateViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: child,
          ),
        );
      },
    );
  }
}

class _FifoHistoryHeader extends StatelessWidget {
  final int checkTotal;
  final int sortTotal;
  final bool loading;
  final Future<void> Function() onReload;

  const _FifoHistoryHeader({
    super.key,
    required this.checkTotal,
    required this.sortTotal,
    required this.loading,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lịch sử FIFO', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Tra cứu lịch sử kiểm tra và sắp xếp FIFO theo người dùng.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: 'Kiểm tra $checkTotal',
                    color: AppColors.info,
                  ),
                  AppStatusChip(
                    label: 'Sắp xếp $sortTotal',
                    color: AppColors.indigo600,
                  ),
                ],
              ),
            ],
          );
          final action = AppIconAction(
            onPressed: loading ? null : () => unawaited(onReload()),
            icon: Icons.refresh_outlined,
            tooltip: 'Tải lại lịch sử',
          );
          final icon = DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.history_rounded, color: AppColors.primary),
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [icon, const Spacer(), action],
                ),
                const SizedBox(height: 12),
                title,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: title),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}
