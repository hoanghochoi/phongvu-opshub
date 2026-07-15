import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_dialogs.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_pagination.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/app_toast.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../data/sales_report_repository.dart';
import '../../domain/sales_report.dart';
import '../providers/sales_report_provider.dart';
import 'sales_report_screen.dart';

const _outcomeNotPurchased = 'NOT_PURCHASED';
const _outcomePurchased = 'PURCHASED';
const _outcomePurchasedElsewhere = 'PURCHASED_ELSEWHERE';
const _outcomeNoLongerInterested = 'NO_LONGER_INTERESTED';

const _reasonOptions = <String, String>{
  'NOT_SOLD': 'Chưa kinh doanh',
  'SERVICE': 'Dịch vụ',
  'CUSTOMER_BROWSING': 'Khách tham khảo',
  'NO_DEMO_STOCK': 'Không có hàng trải nghiệm',
  'NO_AVAILABLE_STOCK': 'Không có sẵn hàng',
  'PRICE_HESITATION': 'Phân vân giá',
  'COMPARE_COMPETITOR': 'So sánh đối thủ',
  'SPEC_NOT_COMPATIBLE': 'Thông số kỹ thuật chưa tương thích',
  'OTHER': 'Khác',
};

class NotPurchasedCustomersScreen extends StatefulWidget {
  final SalesReportRepository? repository;
  final RealtimeClient? realtimeClient;
  final Duration realtimeDebounce;
  final Duration realtimeMaxWait;

  const NotPurchasedCustomersScreen({
    super.key,
    this.repository,
    this.realtimeClient,
    this.realtimeDebounce = const Duration(seconds: 2),
    this.realtimeMaxWait = const Duration(seconds: 5),
  });

  @override
  State<NotPurchasedCustomersScreen> createState() =>
      _NotPurchasedCustomersScreenState();
}

class _NotPurchasedCustomersScreenState
    extends State<NotPurchasedCustomersScreen> {
  static const String _realtimeTopic = 'sales-report.orders';
  static const String _realtimeKind = 'SALES_REPORT_ORDERS_UPDATED';

  late final SalesReportRepository _repository;
  late final RealtimeClient _realtimeClient;
  final _searchController = TextEditingController();
  SalesReportFollowUpPage? _data;
  Timer? _searchDebounce;
  String _status = 'OPEN';
  int _page = 0;
  bool _loading = false;
  String? _error;
  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  Timer? _realtimeDebounceTimer;
  Timer? _realtimeMaxWaitTimer;
  bool _realtimeRefreshDirty = false;
  bool _realtimeRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SalesReportRepository(ApiClient());
    _realtimeClient =
        widget.realtimeClient ?? RealtimeConnectionManager.instance;
    _realtimeEventSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _cancelRealtimeTimers();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    _searchController.dispose();
    super.dispose();
  }

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    if (!mounted ||
        envelope.topic != _realtimeTopic ||
        envelope.kind != _realtimeKind ||
        !envelope.data['source'].toString().startsWith('follow_up_')) {
      return;
    }
    _scheduleRealtimeRefresh();
    unawaited(
      AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime invalidation received',
        context: {
          'eventId': envelope.id,
          'sequence': envelope.sequence,
          'source': envelope.data['source'],
        },
      ),
    );
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (!mounted) return;
    unawaited(
      AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime sync requested',
        context: {'reason': reason.name},
      ),
    );
    _scheduleRealtimeRefresh(immediate: true);
  }

  void _scheduleRealtimeRefresh({bool immediate = false}) {
    if (!mounted) return;
    _realtimeRefreshDirty = true;
    if (immediate) {
      _cancelRealtimeTimers();
      unawaited(_refreshFromRealtime());
      return;
    }
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(
      widget.realtimeDebounce,
      () => unawaited(_refreshFromRealtime()),
    );
    _realtimeMaxWaitTimer ??= Timer(
      widget.realtimeMaxWait,
      () => unawaited(_refreshFromRealtime()),
    );
  }

  Future<void> _refreshFromRealtime() async {
    _cancelRealtimeTimers();
    if (!mounted || !_realtimeRefreshDirty) return;
    if (_loading) return;
    if (_realtimeRefreshInFlight) return;
    _realtimeRefreshDirty = false;
    _realtimeRefreshInFlight = true;
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime refresh started',
      );
      await _load();
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up realtime refresh completed',
        context: {
          'succeeded': _error == null,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      _realtimeRefreshInFlight = false;
      if (_realtimeRefreshDirty && mounted) {
        _scheduleRealtimeRefresh(immediate: true);
      }
    }
  }

  void _cancelRealtimeTimers() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    _realtimeMaxWaitTimer?.cancel();
    _realtimeMaxWaitTimer = null;
  }

  Future<void> _load({int? page}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (page != null) _page = page;
    });
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer list load started',
        context: {
          'status': _status,
          'page': _page,
          'hasSearch': _searchController.text.trim().isNotEmpty,
        },
      );
      final result = await _repository.fetchFollowUpCases(
        status: _status,
        search: _searchController.text,
        page: _page,
      );
      if (!mounted) return;
      setState(() => _data = result);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer list load succeeded',
        context: {
          'status': _status,
          'page': result.page,
          'count': result.items.length,
          'total': result.total,
          'managedScope': result.managedScope,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () =>
              _error = 'Chưa tải được danh sách khách hàng. Vui lòng thử lại.',
        );
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up customer list load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'status': _status,
          'page': _page,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_realtimeRefreshDirty && !_realtimeRefreshInFlight) {
          _scheduleRealtimeRefresh(immediate: true);
        }
      }
    }
  }

  void _searchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_load(page: 0));
    });
  }

  Future<void> _openCase(SalesReportFollowUpCase item) async {
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Follow-up customer dialog opened',
      context: {'caseId': item.id, 'status': item.status},
    );
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          _FollowUpCaseDialog(repository: _repository, initial: item),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AppResponsiveScrollView(
      onRefresh: _load,
      refreshLogSource: 'SalesReportFollowUp',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(total: data?.total ?? 0),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final search = AppTextInput(
                controller: _searchController,
                label: 'Tìm theo tên, điện thoại hoặc Zalo',
                icon: Icons.search_rounded,
                onChanged: _searchChanged,
              );
              final filters = SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'OPEN',
                    label: Text('Cần chăm sóc'),
                    icon: Icon(Icons.schedule_rounded),
                  ),
                  ButtonSegment(
                    value: 'HIDDEN',
                    label: Text('Đã ẩn'),
                    icon: Icon(Icons.archive_outlined),
                  ),
                ],
                selected: {_status},
                onSelectionChanged: (value) {
                  setState(() => _status = value.first);
                  unawaited(_load(page: 0));
                },
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [search, const SizedBox(height: 12), filters],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  filters,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_loading && data == null)
            const AppStatePanel.loading(
              title: 'Đang tải khách hàng cần chăm sóc...',
            )
          else if (_error != null)
            AppStatePanel.error(
              title: 'Chưa tải được danh sách',
              message: _error,
              actionLabel: 'Thử lại',
              onAction: _load,
            )
          else if (data == null || data.items.isEmpty)
            AppStatePanel.empty(
              title: _status == 'OPEN'
                  ? 'Không có khách hàng cần chăm sóc'
                  : 'Chưa có hồ sơ đã ẩn',
              message:
                  'Màn hình chỉ hiển thị khách hàng có số điện thoại hoặc Zalo cá nhân.',
              actionLabel: 'Tải lại',
              onAction: _load,
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1120
                    ? 3
                    : constraints.maxWidth >= 720
                    ? 2
                    : 1;
                final gap = 14.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in data.items)
                      SizedBox(
                        width: width,
                        child: _FollowUpCard(
                          item: item,
                          showStore: data.managedScope,
                          onTap: () => _openCase(item),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            AppPaginationControls(
              pageIndex: data.page,
              totalItems: data.total,
              itemLabel: 'khách hàng',
              onPrevious: data.page > 0 && !_loading
                  ? () => _load(page: data.page - 1)
                  : null,
              onNext: data.hasMore && !_loading
                  ? () => _load(page: data.page + 1)
                  : null,
              onRefresh: _loading ? null : _load,
              isRefreshing: _loading,
            ),
          ],
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final int total;

  const _PageHeader({required this.total});

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    backgroundColor: AppColors.primary.withValues(alpha: 0.06),
    borderColor: AppColors.primary.withValues(alpha: 0.18),
    child: Row(
      children: [
        const Icon(Icons.person_search_rounded, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chăm sóc lại', style: AppTextStyles.headingM),
              Text(
                'Theo dõi và chăm sóc lại khách có thông tin liên hệ • $total hồ sơ',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FollowUpCard extends StatelessWidget {
  final SalesReportFollowUpCase item;
  final bool showStore;
  final VoidCallback onTap;

  const _FollowUpCard({
    required this.item,
    required this.showStore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _careColor(item.careAgeDays);
    final contact = _firstNonEmpty([
      item.customerPhone,
      item.customerZaloContact,
    ]);
    return AppSurfaceCard(
      onTap: onTap,
      borderColor: tone.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _text(item.customerName, 'Khách chưa cập nhật tên'),
                  style: AppTextStyles.titleEmphasis,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${item.careAgeDays} ngày',
                  style: AppTextStyles.labelS.copyWith(color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoLine(icon: Icons.call_outlined, text: contact),
          _InfoLine(
            icon: Icons.category_outlined,
            text: item.categoryNames.isEmpty
                ? 'Chưa có ngành hàng'
                : item.categoryNames.join(', '),
          ),
          if (showStore && (item.storeCode ?? '').trim().isNotEmpty)
            _InfoLine(
              icon: Icons.storefront_outlined,
              text: 'Mã SR: ${item.storeCode}',
            ),
          _InfoLine(
            icon: Icons.person_outline_rounded,
            text:
                'Tiếp xúc đầu: ${_person(item.firstContactByName, item.firstContactByEmail)} • ${_date(item.firstContactAt)}',
          ),
          _InfoLine(
            icon: Icons.history_rounded,
            text: item.lastFollowUpAt == null
                ? 'Chưa chăm sóc lại'
                : 'Lần gần nhất: ${_person(item.lastFollowUpByName, null)} • ${_date(item.lastFollowUpAt)}',
          ),
          if ((item.assigneeName ?? '').trim().isNotEmpty)
            _InfoLine(
              icon: Icons.assignment_ind_outlined,
              text: 'Phụ trách: ${item.assigneeName}',
            ),
        ],
      ),
    );
  }
}

class _FollowUpCaseDialog extends StatefulWidget {
  final SalesReportRepository repository;
  final SalesReportFollowUpCase initial;

  const _FollowUpCaseDialog({required this.repository, required this.initial});

  @override
  State<_FollowUpCaseDialog> createState() => _FollowUpCaseDialogState();
}

class _FollowUpCaseDialogState extends State<_FollowUpCaseDialog> {
  late SalesReportFollowUpCase _case;
  final _otherReasonController = TextEditingController();
  String _outcome = _outcomeNotPurchased;
  String? _reason;
  bool _loading = true;
  bool _saving = false;
  bool _purchaseMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _case = widget.initial;
    unawaited(_loadDetail());
  }

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await widget.repository.fetchFollowUpCase(_case.id);
      if (mounted) setState(() => _case = detail);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _error = 'Chưa tải được đầy đủ lịch sử chăm sóc.');
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up case detail load failed',
        error: error,
        stackTrace: stackTrace,
        context: {'caseId': _case.id},
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_outcome == _outcomeNotPurchased && _reason == null) {
      setState(() => _error = 'Vui lòng chọn lý do khách chưa mua hàng.');
      return;
    }
    if (_reason == 'OTHER' && _otherReasonController.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập lý do khác.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up entry submit started',
        context: {
          'caseId': _case.id,
          'outcome': _outcome,
          'sequenceNumber': _case.nextSequenceNumber,
        },
      );
      await widget.repository.createFollowUpEntry(
        _case.id,
        outcome: _outcome,
        reason: _reason,
        otherReason: _otherReasonController.text,
      );
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up entry submit succeeded',
        context: {'caseId': _case.id, 'outcome': _outcome},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () => _error = 'Chưa lưu được lần chăm sóc. Vui lòng thử lại.',
        );
      }
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up entry submit failed',
        error: error,
        stackTrace: stackTrace,
        context: {'caseId': _case.id, 'outcome': _outcome},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assign(String userId) async {
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.assignFollowUpCase(
        _case.id,
        userId,
      );
      if (mounted) setState(() => _case = updated);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer reassigned',
        context: {'caseId': _case.id, 'assigneeUserId': userId},
      );
    } catch (error, stackTrace) {
      if (mounted) setState(() => _error = 'Chưa phân công được nhân viên.');
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up customer reassign failed',
        error: error,
        stackTrace: stackTrace,
        context: {'caseId': _case.id, 'assigneeUserId': userId},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reopen() async {
    setState(() => _saving = true);
    try {
      await widget.repository.reopenFollowUpCase(_case.id);
      await AppLogger.instance.info(
        'SalesReportFollowUp',
        'Follow-up customer reopened',
        context: {'caseId': _case.id},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (mounted) setState(() => _error = 'Chưa mở lại được hồ sơ.');
      await AppLogger.instance.error(
        'SalesReportFollowUp',
        'Follow-up customer reopen failed',
        error: error,
        stackTrace: stackTrace,
        context: {'caseId': _case.id},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AppDirtyFormGuard(
      source: 'SalesReportFollowUp',
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width < 700 ? 8 : 24,
          vertical: size.height < 700 ? 8 : 24,
        ),
        child: SizedBox(
          width: 960,
          height: size.height * 0.9,
          child: Column(
            children: [
              _DialogHeader(
                item: _case,
                busy: _saving,
                onClose: () => Navigator.of(context).maybePop(),
                onAssign: _case.canReassign ? _assign : null,
                onContact: () => _contactCustomer(context, _case),
              ),
              const Divider(height: 1),
              if (_loading)
                const Expanded(
                  child: AppStatePanel.loading(
                    title: 'Đang tải lịch sử chăm sóc...',
                  ),
                )
              else if (_purchaseMode)
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AppLinkButton(
                            onPressed: () => setState(() {
                              _purchaseMode = false;
                              _outcome = _outcomeNotPurchased;
                            }),
                            icon: Icons.arrow_back_rounded,
                            label: 'Quay lại lịch sử chăm sóc',
                          ),
                        ),
                      ),
                      Expanded(
                        child: ChangeNotifierProvider(
                          create: (_) => SalesReportProvider(widget.repository),
                          child: SalesReportFormScreen.purchased(
                            entrySource: 'COMEBACK',
                            followUpCaseId: _case.id,
                            initialCustomerName: _case.customerName,
                            initialCustomerPhone: _case.customerPhone,
                            initialCustomerZaloContact:
                                _case.customerZaloContact,
                            closeOnSuccess: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error != null) ...[
                        AppStatePanel.error(
                          title: 'Chưa thực hiện được',
                          message: _error,
                          compact: true,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _FirstContactCard(item: _case),
                      const SizedBox(height: 12),
                      for (final entry in _case.entries) ...[
                        _HistoryCard(entry: entry),
                        const SizedBox(height: 10),
                      ],
                      if (_case.status == 'OPEN' && _case.canWrite)
                        _NewFollowUpCard(
                          sequenceNumber: _case.nextSequenceNumber,
                          outcome: _outcome,
                          reason: _reason,
                          otherReasonController: _otherReasonController,
                          saving: _saving,
                          onOutcomeChanged: (value) {
                            notifyAppFormChanged(context);
                            if (value == _outcomePurchased) {
                              setState(() {
                                _outcome = value;
                                _purchaseMode = true;
                              });
                            } else {
                              setState(() {
                                _outcome = value;
                                if (value != _outcomeNotPurchased) {
                                  _reason = null;
                                  _otherReasonController.clear();
                                }
                              });
                            }
                          },
                          onReasonChanged: (value) {
                            notifyAppFormChanged(context);
                            setState(() => _reason = value);
                          },
                          onSave: _save,
                        )
                      else if (_case.canReopen)
                        AppPrimaryButton(
                          onPressed: _saving ? null : _reopen,
                          icon: Icons.unarchive_outlined,
                          label: 'Mở lại để tiếp tục chăm sóc',
                          isLoading: _saving,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final SalesReportFollowUpCase item;
  final bool busy;
  final VoidCallback onClose;
  final ValueChanged<String>? onAssign;
  final VoidCallback onContact;

  const _DialogHeader({
    required this.item,
    required this.busy,
    required this.onClose,
    required this.onAssign,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _careColor(item.careAgeDays).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.person_search_rounded,
            color: _careColor(item.careAgeDays),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(item.customerName, 'Khách chưa cập nhật tên'),
                style: AppTextStyles.headingS,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Tooltip(
                message: 'Chạm để liên hệ',
                child: InkWell(
                  onTap: busy ? null : onContact,
                  child: Text(
                    '${_firstNonEmpty([item.customerPhone, item.customerZaloContact])} • ${item.categoryNames.join(', ')}',
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Liên hệ khách hàng',
          onPressed: busy ? null : onContact,
          icon: const Icon(Icons.call_outlined),
        ),
        if (onAssign != null && item.assignmentCandidates.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Phân công nhân viên',
            enabled: !busy,
            onSelected: onAssign,
            itemBuilder: (_) => [
              for (final assignee in item.assignmentCandidates)
                PopupMenuItem(
                  value: assignee.id,
                  child: Text(
                    assignee.personnelCode == null
                        ? assignee.name
                        : '${assignee.name} • ${assignee.personnelCode}',
                  ),
                ),
            ],
            icon: const Icon(Icons.assignment_ind_outlined),
          ),
        IconButton(
          tooltip: 'Đóng',
          onPressed: busy ? null : onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _FirstContactCard extends StatelessWidget {
  final SalesReportFollowUpCase item;

  const _FirstContactCard({required this.item});

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    backgroundColor: AppColors.warning.withValues(alpha: 0.06),
    borderColor: AppColors.warning.withValues(alpha: 0.24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tiếp xúc lần đầu', style: AppTextStyles.labelL),
        const SizedBox(height: 6),
        Text(
          '${_person(item.firstContactByName, item.firstContactByEmail)} • ${_date(item.firstContactAt)}',
        ),
        const SizedBox(height: 4),
        Text(
          'Lý do chưa mua: ${_text(item.firstReasonLabel, 'Chưa cập nhật')}${(item.firstOtherReason ?? '').trim().isEmpty ? '' : ' — ${item.firstOtherReason}'}',
        ),
        if ((item.assigneeName ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Đang phụ trách: ${item.assigneeName}'),
        ],
      ],
    ),
  );
}

class _HistoryCard extends StatelessWidget {
  final SalesReportFollowUpEntry entry;

  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lần chăm sóc ${entry.sequenceNumber} • ${entry.outcomeLabel}',
          style: AppTextStyles.labelL,
        ),
        const SizedBox(height: 5),
        Text(
          '${_person(entry.actorName, entry.actorEmail)} • ${_date(entry.contactedAt)}',
        ),
        if ((entry.reasonLabel ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Lý do: ${entry.reasonLabel}${(entry.otherReason ?? '').trim().isEmpty ? '' : ' — ${entry.otherReason}'}',
          ),
        ],
      ],
    ),
  );
}

class _NewFollowUpCard extends StatelessWidget {
  final int sequenceNumber;
  final String outcome;
  final String? reason;
  final TextEditingController otherReasonController;
  final bool saving;
  final ValueChanged<String> onOutcomeChanged;
  final ValueChanged<String?> onReasonChanged;
  final VoidCallback onSave;

  const _NewFollowUpCard({
    required this.sequenceNumber,
    required this.outcome,
    required this.reason,
    required this.otherReasonController,
    required this.saving,
    required this.onOutcomeChanged,
    required this.onReasonChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    borderColor: AppColors.primary.withValues(alpha: 0.32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Lần chăm sóc $sequenceNumber', style: AppTextStyles.headingS),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _OutcomeChip(
              value: _outcomePurchased,
              label: 'Mua hàng',
              icon: Icons.shopping_cart_checkout_rounded,
              selected: outcome == _outcomePurchased,
              onSelected: onOutcomeChanged,
            ),
            _OutcomeChip(
              value: _outcomeNotPurchased,
              label: 'Chưa mua',
              icon: Icons.schedule_rounded,
              selected: outcome == _outcomeNotPurchased,
              onSelected: onOutcomeChanged,
            ),
            _OutcomeChip(
              value: _outcomePurchasedElsewhere,
              label: 'Đã mua nơi khác',
              icon: Icons.store_mall_directory_outlined,
              selected: outcome == _outcomePurchasedElsewhere,
              onSelected: onOutcomeChanged,
            ),
            _OutcomeChip(
              value: _outcomeNoLongerInterested,
              label: 'Hết nhu cầu',
              icon: Icons.do_not_disturb_alt_outlined,
              selected: outcome == _outcomeNoLongerInterested,
              onSelected: onOutcomeChanged,
            ),
          ],
        ),
        if (outcome == _outcomeNotPurchased) ...[
          const SizedBox(height: 14),
          AppCombobox<String>.single(
            label: 'Lý do chưa mua hàng',
            icon: Icons.help_outline_rounded,
            value: reason,
            allowClear: false,
            enabled: !saving,
            options: [
              for (final entry in _reasonOptions.entries)
                AppComboboxOption(value: entry.key, label: entry.value),
            ],
            onChanged: onReasonChanged,
          ),
          if (reason == 'OTHER') ...[
            const SizedBox(height: 12),
            AppTextInput(
              controller: otherReasonController,
              label: 'Nhập lý do khác',
              icon: Icons.edit_note_rounded,
              maxLines: 3,
            ),
          ],
        ],
        const SizedBox(height: 16),
        AppPrimaryButton(
          onPressed: saving ? null : onSave,
          icon: Icons.save_outlined,
          label: 'Lưu lần chăm sóc',
          isLoading: saving,
          loadingLabel: 'Đang lưu...',
        ),
      ],
    ),
  );
}

class _OutcomeChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<String> onSelected;

  const _OutcomeChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onSelected: (_) => onSelected(value),
  );
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.neutral600),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyS,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

Future<void> _contactCustomer(
  BuildContext context,
  SalesReportFollowUpCase item,
) async {
  final phone = item.customerPhone?.trim() ?? '';
  final zalo = item.customerZaloContact?.trim() ?? '';
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  try {
    if (mobile && phone.isNotEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: const Text('Gọi điện thoại'),
                subtitle: Text(phone),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await launchUrl(Uri(scheme: 'tel', path: phone));
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: const Text('Mở Zalo bằng số điện thoại'),
                subtitle: Text(phone),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final normalized = phone.replaceAll(RegExp(r'\D'), '');
                  await launchUrl(
                    Uri.parse('https://zalo.me/$normalized'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ],
          ),
        ),
      );
    } else {
      final value = phone.isNotEmpty ? phone : zalo;
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Đã sao chép thông tin liên hệ.')),
        );
      }
    }
    await AppLogger.instance.info(
      'SalesReportFollowUp',
      'Follow-up customer contact action succeeded',
      context: {
        'caseId': item.id,
        'mobile': mobile,
        'hasPhone': phone.isNotEmpty,
        'hasZaloContact': zalo.isNotEmpty,
      },
    );
  } catch (error, stackTrace) {
    await AppLogger.instance.error(
      'SalesReportFollowUp',
      'Follow-up customer contact action failed',
      error: error,
      stackTrace: stackTrace,
      context: {'caseId': item.id, 'hasPhone': phone.isNotEmpty},
    );
    if (context.mounted) {
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Chưa mở được kênh liên hệ. Vui lòng thử lại.'),
        ),
      );
    }
  }
}

Color _careColor(int days) => switch (days) {
  <= 1 => AppColors.success,
  <= 3 => AppColors.warning,
  _ => AppColors.error,
};

String _date(DateTime? value) => value == null
    ? 'Chưa cập nhật'
    : DateFormat('HH:mm dd/MM/yyyy').format(value.toLocal());

String _text(String? value, String fallback) =>
    (value ?? '').trim().isEmpty ? fallback : value!.trim();

String _person(String? name, String? email) =>
    _firstNonEmpty([name, email], fallback: 'Chưa cập nhật');

String _firstNonEmpty(
  List<String?> values, {
  String fallback = 'Chưa cập nhật',
}) {
  for (final value in values) {
    if ((value ?? '').trim().isNotEmpty) return value!.trim();
  }
  return fallback;
}
