part of 'payment_monitor_provider.dart';

mixin PaymentMonitorProviderQueryState on ChangeNotifier {
  bool get _isActive;
  bool get _isLoading;
  String? get _errorMessage;
  DateTime? get _lastCheckedAt;
  String? get _storeOverride;
  set _storeOverride(String? value);
  Set<String> get _selectedStoreIds;
  DateTime get _rangeStartDate;
  set _rangeStartDate(DateTime value);
  DateTime get _rangeEndDate;
  set _rangeEndDate(DateTime value);
  int get _pageIndex;
  set _pageIndex(int value);
  int get _pageSize;
  set _pageSize(int value);
  int get _totalTransactions;
  PaymentSpeakerError? get _speakerError;
  bool get _canMonitorOnThisDevice;
  bool get _hasMonitorScope;
  bool get _canUseSpeakerOnThisDevice;
  User? get _user;
  bool get _canUsePaymentSpeaker;
  bool get _canReviewOrderTransfers;
  Map<String, PaymentMonitorRowMessage> get _rowMessages;
  Set<String> get _updatingOrderIds;
  Set<String> get _updatingOrderTrackingIds;
  List<String> get _effectiveListStoreIds;
  List<MapPaymentTransaction> get _latestTransactions;
  String? get _requestStoreId;
  void _restart({required String reason, required bool userInitiated});
  void _poll({
    required bool force,
    required bool bypassBackoff,
    required bool allowRateLimitCooldownBypass,
    required bool includeTotal,
    required String reason,
  });
  Future<void> _logPageChanged(String direction);

  bool get isActive => _isActive;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get storeOverride => _storeOverride;
  Set<String> get selectedStoreIds => Set.unmodifiable(_selectedStoreIds);
  DateTime get selectedDate => _rangeStartDate;
  DateTime get rangeStartDate => _rangeStartDate;
  DateTime get rangeEndDate => _rangeEndDate;
  int get pageIndex => _pageIndex;
  int get pageSize => _pageSize;
  int get totalTransactions => _totalTransactions;
  PaymentSpeakerError? get speakerError => _speakerError;
  bool get canGoPreviousPage => _pageIndex > 0;
  bool get canGoNextPage => (_pageIndex + 1) * _pageSize < _totalTransactions;
  bool get canMonitorOnThisDevice => _canMonitorOnThisDevice;
  bool get hasMonitorScope => _hasMonitorScope;
  bool get canConfigurePaymentSpeaker =>
      _canUseSpeakerOnThisDevice &&
      PaymentMonitorProvider._userCanUsePaymentSpeakerFeature(_user);
  bool get canUsePaymentSpeaker => _canUsePaymentSpeaker;
  bool get canReviewOrderTransfers => _canReviewOrderTransfers;
  Map<String, PaymentMonitorRowMessage> get rowMessages =>
      Map.unmodifiable(_rowMessages);
  bool isUpdatingOrders(String id) => _updatingOrderIds.contains(id);
  bool isUpdatingOrderTracking(String id) =>
      _updatingOrderTrackingIds.contains(id);
  bool get isViewingMultipleStores => _effectiveListStoreIds.length > 1;
  List<MapPaymentTransaction> get latestTransactions =>
      List.unmodifiable(_latestTransactions);

  void setStoreOverride(String value) {
    final normalized = value.trim().toUpperCase();
    if (_storeOverride == normalized) return;
    _storeOverride = normalized.isEmpty ? null : normalized;
    _selectedStoreIds
      ..clear()
      ..addAll([if (_storeOverride?.isNotEmpty == true) _storeOverride!]);
    _pageIndex = 0;
    _restart(reason: 'store_override', userInitiated: true);
  }

  void setSelectedStoreIds(Set<String> values) {
    final normalized = values
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (setEquals(_selectedStoreIds, normalized)) return;
    _selectedStoreIds
      ..clear()
      ..addAll(normalized);
    _storeOverride = normalized.length == 1 ? normalized.first : null;
    _pageIndex = 0;
    _restart(reason: 'store_selection', userInitiated: true);
  }

  void setSelectedDate(DateTime value) {
    setDateRange(value, value);
  }

  void setDateRange(DateTime start, DateTime end) {
    var normalizedStart = PaymentMonitorProvider._normalizeVietnamDate(start);
    var normalizedEnd = PaymentMonitorProvider._normalizeVietnamDate(end);
    if (normalizedEnd.isBefore(normalizedStart)) {
      final swap = normalizedStart;
      normalizedStart = normalizedEnd;
      normalizedEnd = swap;
    }
    if (PaymentMonitorProvider._isSameDate(_rangeStartDate, normalizedStart) &&
        PaymentMonitorProvider._isSameDate(_rangeEndDate, normalizedEnd)) {
      return;
    }
    _rangeStartDate = normalizedStart;
    _rangeEndDate = normalizedEnd;
    _pageIndex = 0;
    unawaited(
      AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor date range changed',
        context: {
          'storeId': _requestStoreId ?? _user?.storeId,
          'startDate': PaymentMonitorProvider._formatDateForApi(
            _rangeStartDate,
          ),
          'endDate': PaymentMonitorProvider._formatDateForApi(_rangeEndDate),
        },
      ),
    );
    _poll(
      force: true,
      bypassBackoff: true,
      allowRateLimitCooldownBypass: true,
      includeTotal: true,
      reason: 'date_range',
    );
  }

  void setPageSize(int value) {
    if (_pageSize == value) return;
    _pageSize = value;
    _pageIndex = 0;
    unawaited(
      AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor page size changed',
        context: {
          'storeId': _requestStoreId ?? _user?.storeId,
          'limit': _pageSize,
        },
      ),
    );
    _poll(
      force: true,
      bypassBackoff: true,
      allowRateLimitCooldownBypass: true,
      includeTotal: true,
      reason: 'page_size',
    );
  }

  void nextPage() {
    if (!canGoNextPage) return;
    _pageIndex += 1;
    unawaited(_logPageChanged('next'));
    _poll(
      force: true,
      bypassBackoff: true,
      allowRateLimitCooldownBypass: true,
      includeTotal: true,
      reason: 'next_page',
    );
  }

  void previousPage() {
    if (!canGoPreviousPage) return;
    _pageIndex -= 1;
    unawaited(_logPageChanged('previous'));
    _poll(
      force: true,
      bypassBackoff: true,
      allowRateLimitCooldownBypass: true,
      includeTotal: true,
      reason: 'previous_page',
    );
  }
}
