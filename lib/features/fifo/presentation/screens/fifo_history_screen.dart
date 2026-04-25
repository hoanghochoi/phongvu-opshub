import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/fifo_log_repository.dart';

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
        } else if (_tabController.index == 1 && _sortLogs.isEmpty && !_sortLoading) {
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
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Lịch sử FIFO', showBack: true),
      body: Column(
        children: [
          // Search + Filter bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Search field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo Serial / SKU / BIN...',
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _clearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF5F7FB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _onSearch(),
                  textInputAction: TextInputAction.search,
                ),
                const SizedBox(height: 8),
                // User filter
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _userFilterController,
                        decoration: InputDecoration(
                          hintText: 'Lọc theo email user...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                          prefixIcon: Icon(Icons.person_outline, color: Colors.grey[500], size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _onSearch(),
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: const Color(0xFF0277BD),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _onSearch,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.search, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Result count
                Row(
                  children: [
                    Text(
                      'Tổng: ${_tabController.index == 0 ? _checkTotal : _sortTotal} bản ghi',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    if (_searchQuery != null || _filterUser != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearSearch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.filter_alt_off, size: 12, color: Colors.orange[700]),
                              const SizedBox(width: 4),
                              Text(
                                'Xóa bộ lọc',
                                style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[700],
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0277BD), Color(0xFF29B6F6)],
                ),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerHeight: 0,
              tabs: const [
                Tab(text: 'Kiểm tra FIFO'),
                Tab(text: 'Sắp xếp FIFO'),
              ],
            ),
          ),
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
      return const Center(child: CircularProgressIndicator());
    }

    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              _searchQuery != null || _filterUser != null
                  ? 'Không tìm thấy kết quả'
                  : 'Chưa có lịch sử',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tải lại'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0277BD),
                foregroundColor: Colors.white,
              ),
            ),
          ],
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
                    : TextButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Xem thêm'),
                      ),
              ),
            );
          }

          final log = logs[index];
          return _buildLogCard(log);
        },
      ),
    );
  }

  Widget _buildLogCard(FifoLogItem log) {
    final date = DateTime.tryParse(log.createdAt);
    final dateStr = date != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal())
        : log.createdAt;

    final isCorrect = log.result?.contains('Đúng') ?? false;
    final isWrong = log.result?.contains('Sai') ?? log.result?.contains('Chưa') ?? false;
    final resultColor = isCorrect
        ? Colors.green
        : isWrong
            ? Colors.red
            : Colors.grey[700];

    final isExpanded = _expandedIds.contains(log.id);
    final items = _parseResultJson(log.resultJson);
    final hasItems = items.isNotEmpty;

    return GestureDetector(
      onTap: hasItems
          ? () {
              setState(() {
                if (isExpanded) {
                  _expandedIds.remove(log.id);
                } else {
                  _expandedIds.add(log.id);
                }
              });
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isExpanded
              ? Border.all(color: const Color(0xFF0277BD).withValues(alpha: 0.3), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: User + Time
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF0277BD).withValues(alpha: 0.15),
                    child: Text(
                      (log.userName ?? log.userEmail ?? '?')[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0277BD),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.userName ?? log.userEmail ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (log.storeName != null)
                          Text(
                            '${log.storeId ?? ''} - ${log.storeName}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Query + Item count + expand arrow
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Query',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.query,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (hasItems) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0277BD).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${items.length} items',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0277BD),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                  ],
                ],
              ),
              // Result
              if (log.result != null && log.result!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (resultColor ?? Colors.grey).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Kết quả',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: resultColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log.result!,
                        style: TextStyle(
                          fontSize: 13,
                          color: resultColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Expanded detail: show each item
              if (isExpanded && hasItems) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return _buildItemDetail(item, idx + 1);
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Parse resultJson into a list of maps
  List<Map<String, dynamic>> _parseResultJson(dynamic resultJson) {
    if (resultJson == null) return [];
    if (resultJson is List) {
      return resultJson
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  /// Build a single item detail row
  Widget _buildItemDetail(Map<String, dynamic> item, int index) {
    final sku = item['sku']?.toString() ?? '';
    final skuName = item['sku_name']?.toString() ?? '';
    final serial = item['serial_number']?.toString() ?? '';
    final bin = item['bin']?.toString() ?? '';
    final importDate = item['import_date']?.toString() ?? '';
    final fifo = item['fifo']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(8),
        border: fifo == 'yes'
            ? Border.all(color: Colors.green.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SKU Name
          Row(
            children: [
              Text(
                '#$index',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  skuName.isNotEmpty ? skuName : sku,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (fifo == 'yes')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'FIFO ✓',
                    style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Serial + BIN + Date
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (serial.isNotEmpty)
                _infoChip(Icons.qr_code, serial),
              if (bin.isNotEmpty)
                _infoChip(Icons.inventory_2_outlined, bin),
              if (importDate.isNotEmpty)
                _infoChip(Icons.calendar_today, importDate),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[500]),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey[700], fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
