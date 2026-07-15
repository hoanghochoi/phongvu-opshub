import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/info_row.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../fifo_check/presentation/widgets/barcode_scanner_screen.dart';
import '../../data/repositories/vietqr_repository.dart';
import '../../domain/entities/vietqr_transfer.dart';
import '../widgets/qr_with_logo.dart';
import '../widgets/payment_waiting_card.dart';
import '../widgets/payment_success_panel.dart';
import '../widgets/payment_confirmation_card.dart';
import '../services/vietqr_history_store.dart';
import '../services/vietqr_image_saver.dart';
import 'package:go_router/go_router.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

class VietQrScreen extends StatefulWidget {
  final AuthRepository? authRepository;
  final VietQrRepository? repository;
  final RealtimeClient? realtimeClient;
  final Duration realtimeDebounce;
  final Duration realtimeMaxWait;

  const VietQrScreen({
    super.key,
    this.authRepository,
    this.repository,
    this.realtimeClient,
    this.realtimeDebounce = const Duration(seconds: 2),
    this.realtimeMaxWait = const Duration(seconds: 5),
  });

  @override
  State<VietQrScreen> createState() => _VietQrScreenState();
}

class _VietQrScreenState extends State<VietQrScreen>
    with WidgetsBindingObserver {
  static const String _realtimeTopic = 'payment.transactions';
  static const String _realtimeKind = 'PAYMENT_NOTIFICATION';

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _orderCodeController = TextEditingController();
  final _storeCodeController = TextEditingController();
  final _previewContentController = TextEditingController();
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');
  final _imageSaver = VietQrImageSaver();
  final _historyStore = VietQrHistoryStore();
  late final AuthRepository _authRepository;
  late final VietQrRepository _repository;
  late final RealtimeClient _realtimeClient;
  VietQrTransfer? _transfer;
  VietQrPaymentConfirmation? _paymentConfirmation;
  List<VietQrHistoryEntry> _historyEntries = [];
  List<StoreBranch> _accessibleStoreOptions = [];
  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  final Map<String, RealtimeEnvelope> _pendingRealtimePayments = {};
  Timer? _realtimeDebounceTimer;
  Timer? _realtimeMaxWaitTimer;
  Timer? _historyRefreshTimer;
  String? _storeScopeSignature;
  String? _storeOptionsSignature;
  String? _historyUserId;
  bool _isHistoryLoading = false;
  String? _historyErrorMessage;
  bool _isStoreOptionsLoading = false;
  String? _storeOptionsErrorMessage;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isCheckingPayment = false;
  bool _isForeground = true;
  bool _isFlushingRealtimePayments = false;
  int _paymentPollAttempts = 0;
  bool _hasShownPaymentReceived = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository(ApiClient());
    _repository = widget.repository ?? VietQrRepository(ApiClient());
    _realtimeClient =
        widget.realtimeClient ?? RealtimeConnectionManager.instance;
    _realtimeEventSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
    WidgetsBinding.instance.addObserver(this);
    _orderCodeController.addListener(_updatePreviewContent);
    _storeCodeController.addListener(_updatePreviewContent);
    _historyRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted && _isForeground) _refreshHistoryClock('fallback');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AuthProvider>().user;
    _syncStoreSelection(user);
    _syncAccessibleStoreOptions(user);
    _syncHistoryScope(user);
  }

  @override
  void dispose() {
    _stopPaymentPolling();
    WidgetsBinding.instance.removeObserver(this);
    _cancelRealtimePaymentTimers();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    _historyRefreshTimer?.cancel();
    _amountController.dispose();
    _orderCodeController.dispose();
    _storeCodeController.dispose();
    _previewContentController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForeground;
    _isForeground = state == AppLifecycleState.resumed;
    if (!wasForeground && _isForeground && mounted) {
      _refreshHistoryClock('app_resumed');
    }
  }

  void _refreshHistoryClock(String reason) {
    if (!mounted || !_isForeground) return;
    final transfer = _transfer;
    if (transfer != null &&
        !_hasConfirmedPayment &&
        _isTransferExpired(transfer, DateTime.now())) {
      _stopPaymentPolling();
    }
    if (transfer == null && _historyEntries.isEmpty) return;
    setState(() {});
    unawaited(
      AppLogger.instance.info(
        'VietQR',
        'VietQR history clock refreshed',
        context: {
          'reason': reason,
          'historyCount': _historyEntries.length,
          'hasActiveTransfer': transfer != null,
        },
      ),
    );
  }

  void _updatePreviewContent() {
    final nextValue = _previewContent();
    if (_previewContentController.text == nextValue) return;
    _previewContentController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  void _syncStoreSelection(User? user) {
    final stores = _currentStoreOptions(user);
    final signature = [
      user?.id ?? '',
      user?.storeId ?? '',
      ...stores.map((store) => '${store.storeId}:${store.storeName}'),
    ].join('|');
    if (_storeScopeSignature == signature) return;
    _storeScopeSignature = signature;

    final allowedStoreIds = stores
        .map((store) => store.storeId.trim().toUpperCase())
        .where((storeId) => storeId.isNotEmpty)
        .toSet();
    final current = _storeCodeController.text.trim().toUpperCase();
    final nextStoreCode = allowedStoreIds.contains(current)
        ? current
        : (stores.isNotEmpty ? stores.first.storeId.trim().toUpperCase() : '');

    if (_storeCodeController.text.trim().toUpperCase() != nextStoreCode) {
      _storeCodeController.value = TextEditingValue(
        text: nextStoreCode,
        selection: TextSelection.collapsed(offset: nextStoreCode.length),
      );
    }

    unawaited(
      AppLogger.instance.info(
        'VietQR',
        'Store scope resolved',
        context: {
          'assignedStoreCount': stores.length,
          'selectedStoreCode': nextStoreCode,
          'selectionMode': stores.length > 1 ? 'dropdown' : 'locked',
        },
      ),
    );
  }

  List<StoreBranch> _currentStoreOptions(User? user) {
    final assignedStores = _assignedStoreOptions(user);
    if (user?.isSuperAdmin != true) return assignedStores;
    if (_accessibleStoreOptions.isNotEmpty) return _accessibleStoreOptions;
    return assignedStores;
  }

  Future<void> _syncAccessibleStoreOptions(User? user) async {
    final userId = user?.id?.trim() ?? '';
    final assignedStores = _assignedStoreOptions(user);
    final signature = [
      userId,
      user?.role ?? '',
      user?.isSuperAdmin == true ? 'ALL_STORES' : 'ASSIGNED_STORE',
      user?.storeId?.trim() ?? '',
      ...assignedStores.map((store) => store.storeId.trim().toUpperCase()),
    ].join('|');
    if (_storeOptionsSignature == signature) return;
    _storeOptionsSignature = signature;

    if (!mounted) return;
    if (user == null) {
      setState(() {
        _accessibleStoreOptions = const [];
        _isStoreOptionsLoading = false;
        _storeOptionsErrorMessage = null;
      });
      return;
    }

    if (user.isSuperAdmin) {
      unawaited(_loadAccessibleStoreOptions(user, signature));
      return;
    }

    setState(() {
      _accessibleStoreOptions = assignedStores;
      _isStoreOptionsLoading = false;
      _storeOptionsErrorMessage = null;
    });
    _syncStoreSelection(user);
  }

  Future<void> _loadAccessibleStoreOptions(User user, String signature) async {
    final startedAt = DateTime.now();
    try {
      if (mounted) {
        setState(() {
          _isStoreOptionsLoading = true;
          _storeOptionsErrorMessage = null;
        });
      }
      await AppLogger.instance.info(
        'VietQR',
        'Accessible store load started',
        context: {
          'scopeMode': 'ALL_STORES',
          'userId': user.id,
          'assignedStoreCount': user.assignedStores.length,
        },
      );

      final stores = await _authRepository.getStores();
      final merged = _mergeStoreOptions([...user.assignedStores, ...stores]);
      if (!mounted || _storeOptionsSignature != signature) return;

      setState(() {
        _accessibleStoreOptions = merged;
        _isStoreOptionsLoading = false;
        _storeOptionsErrorMessage = null;
      });
      _syncStoreSelection(user);

      await AppLogger.instance.info(
        'VietQR',
        'Accessible store load succeeded',
        context: {
          'scopeMode': 'ALL_STORES',
          'userId': user.id,
          'availableCount': stores.length,
          'visibleCount': merged.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'VietQR',
        'Accessible store load failed',
        error: error,
        stackTrace: stackTrace,
        upload: false,
        context: {
          'scopeMode': 'ALL_STORES',
          'userId': user.id,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted || _storeOptionsSignature != signature) return;

      final fallbackStores = _assignedStoreOptions(user);
      setState(() {
        _accessibleStoreOptions = fallbackStores;
        _isStoreOptionsLoading = false;
        _storeOptionsErrorMessage = fallbackStores.isEmpty
            ? 'Chưa tải được danh sách showroom. Vui lòng thử lại.'
            : null;
      });
      _syncStoreSelection(user);
    }
  }

  List<StoreBranch> _mergeStoreOptions(Iterable<StoreBranch> stores) {
    final storesByCode = <String, StoreBranch>{};
    void pushStore(StoreBranch store) {
      final storeCode = store.storeId.trim().toUpperCase();
      if (storeCode.isEmpty || storesByCode.containsKey(storeCode)) return;
      storesByCode[storeCode] = StoreBranch(
        id: store.id,
        storeId: storeCode,
        storeName: store.storeName.trim(),
        areaCode: store.areaCode,
        areaName: store.areaName,
        areaAbbreviation: store.areaAbbreviation,
        regionCode: store.regionCode,
        regionName: store.regionName,
        regionAbbreviation: store.regionAbbreviation,
        transferAccountNumber: store.transferAccountNumber,
        transferAccountName: store.transferAccountName,
        transferBankName: store.transferBankName,
        transferBankBin: store.transferBankBin,
        mapVietinUsername: store.mapVietinUsername,
        hasMapVietinPassword: store.hasMapVietinPassword,
        userCount: store.userCount,
      );
    }

    for (final store in stores) {
      pushStore(store);
    }
    final merged = storesByCode.values.toList(growable: false);
    merged.sort(
      (a, b) => a.storeId.toUpperCase().compareTo(b.storeId.toUpperCase()),
    );
    return merged;
  }

  List<StoreBranch> _assignedStoreOptions(User? user) {
    final storesByCode = <String, StoreBranch>{};
    void pushStore(StoreBranch store) {
      final storeCode = store.storeId.trim().toUpperCase();
      if (storeCode.isEmpty || storesByCode.containsKey(storeCode)) return;
      storesByCode[storeCode] = StoreBranch(
        id: store.id,
        storeId: storeCode,
        storeName: store.storeName.trim(),
        areaCode: store.areaCode,
        areaName: store.areaName,
        areaAbbreviation: store.areaAbbreviation,
        regionCode: store.regionCode,
        regionName: store.regionName,
        regionAbbreviation: store.regionAbbreviation,
        transferAccountNumber: store.transferAccountNumber,
        transferAccountName: store.transferAccountName,
        transferBankName: store.transferBankName,
        transferBankBin: store.transferBankBin,
        mapVietinUsername: store.mapVietinUsername,
        hasMapVietinPassword: store.hasMapVietinPassword,
        userCount: store.userCount,
      );
    }

    for (final store in user?.assignedStores ?? const <StoreBranch>[]) {
      pushStore(store);
    }
    final fallbackStoreId = user?.storeId?.trim();
    if (storesByCode.isEmpty &&
        fallbackStoreId != null &&
        fallbackStoreId.isNotEmpty) {
      pushStore(
        StoreBranch(
          id: '',
          storeId: fallbackStoreId,
          storeName: user?.storeName?.trim() ?? '',
        ),
      );
    }
    return storesByCode.values.toList(growable: false);
  }

  String _storeOptionLabel(StoreBranch store) {
    final storeId = store.storeId.trim().toUpperCase();
    final storeName = store.storeName.trim();
    if (storeName.isEmpty || storeName.toUpperCase() == storeId) {
      return storeId;
    }
    return '$storeId - $storeName';
  }

  void _selectStoreCode(String? value) {
    final storeCode = value?.trim().toUpperCase() ?? '';
    if (storeCode.isEmpty) return;
    _storeCodeController.value = TextEditingValue(
      text: storeCode,
      selection: TextSelection.collapsed(offset: storeCode.length),
    );
    unawaited(
      AppLogger.instance.info(
        'VietQR',
        'Store selection changed',
        context: {'storeCode': storeCode},
      ),
    );
  }

  Future<void> _createQr() async {
    if (!_formKey.currentState!.validate()) return;

    _stopPaymentPolling();
    setState(() {
      _isLoading = true;
      _transfer = null;
      _paymentConfirmation = null;
      _paymentPollAttempts = 0;
      _hasShownPaymentReceived = false;
    });

    try {
      await AppLogger.instance.info(
        'VietQR',
        'Create QR started',
        context: {
          'storeCode': _storeCodeController.text.trim(),
          'hasAmount': _amountValue != null,
          'hasOrderCode': _orderCodeController.text.trim().isNotEmpty,
        },
      );
      final transfer = await _repository.createTransferQr(
        amount: _amountValue,
        orderCode: _orderCodeController.text.trim(),
        storeCode: _storeCodeController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _transfer = transfer;
          _paymentConfirmation = null;
          _paymentPollAttempts = 0;
          _hasShownPaymentReceived = false;
        });
        await _storeActiveHistoryEntry(
          transfer: transfer,
          confirmation: null,
          insertAtTop: true,
        );
        await AppLogger.instance.info(
          'VietQR',
          'Create QR succeeded',
          context: {
            'paymentId': transfer.id,
            'storeCode': _storeCodeController.text.trim(),
            'brandKey': transfer.qrBrand.key,
            'brandTitle': transfer.qrBrand.title,
            'amount': transfer.amount,
            'hasTransferContent': transfer.transferContent.trim().isNotEmpty,
          },
        );
        await AppLogger.instance.info(
          'VietQRRealtime',
          'Realtime payment confirmation armed',
          context: {
            'paymentId': transfer.id,
            'storeCode': _storeCodeController.text.trim().toUpperCase(),
            'amount': transfer.amount,
            'hasTransferContent': transfer.transferContent.trim().isNotEmpty,
          },
        );
      }
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'Create QR failed',
        error: e,
        upload: true,
        context: {'storeCode': _storeCodeController.text.trim()},
      );
      if (mounted) {
        AppToast.show(
          context,
          SnackBar(
            content: Text('Chưa tạo được mã QR. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int? get _amountValue {
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  String _amountLabel(int? amount) {
    if (amount == null) return 'Người chuyển nhập';
    return '${_currencyFormatter.format(amount)} VND';
  }

  String _contentLabel(String transferContent) {
    if (transferContent.isEmpty) return 'Người chuyển nhập';
    return transferContent;
  }

  void _formatAmount(String value) {
    final amount = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null) {
      _amountController.clear();
      return;
    }

    final formatted = _currencyFormatter.format(amount);
    _amountController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _previewContent() {
    final storeCode = _storeCodeController.text.trim();
    final orderCode = _orderCodeController.text.trim();
    if (orderCode.isEmpty) return '';
    if (storeCode.isEmpty) return orderCode.toUpperCase();
    return '$orderCode $storeCode BOT'.toUpperCase();
  }

  void _createNewQr() {
    _stopPaymentPolling();
    setState(() {
      _transfer = null;
      _paymentConfirmation = null;
      _amountController.clear();
      _orderCodeController.clear();
      _paymentPollAttempts = 0;
      _hasShownPaymentReceived = false;
    });
  }

  Future<void> _confirmPayment() async {
    await _checkPayment(showFeedback: true);
  }

  Future<void> _storeActiveHistoryEntry({
    required VietQrTransfer transfer,
    required VietQrPaymentConfirmation? confirmation,
    bool insertAtTop = false,
  }) async {
    final historyEntry = VietQrHistoryEntry(
      storeCode: _storeCodeController.text.trim().toUpperCase(),
      transfer: transfer,
      confirmation: confirmation,
    );
    final existingIndex = _historyEntries.indexWhere(
      (entry) => entry.paymentId == historyEntry.paymentId,
    );
    final nextEntries = List<VietQrHistoryEntry>.from(_historyEntries);
    if (existingIndex >= 0) {
      nextEntries[existingIndex] = historyEntry;
    } else if (insertAtTop) {
      nextEntries.insert(0, historyEntry);
    } else {
      nextEntries.add(historyEntry);
    }
    if (nextEntries.length > 20) {
      nextEntries.removeRange(20, nextEntries.length);
    }
    if (!mounted) return;

    setState(() {
      _historyEntries = nextEntries;
      _historyErrorMessage = null;
    });

    await _saveHistoryEntries(
      trigger: insertAtTop ? 'create' : 'update',
      entryCount: nextEntries.length,
    );
  }

  void _selectHistoryEntry(VietQrHistoryEntry entry) {
    final now = DateTime.now();
    if (!entry.canOpenQr(now)) {
      return;
    }

    final storeCode = entry.storeCode.trim().toUpperCase();
    if (storeCode.isNotEmpty &&
        _storeCodeController.text.trim().toUpperCase() != storeCode) {
      _storeCodeController.value = TextEditingValue(
        text: storeCode,
        selection: TextSelection.collapsed(offset: storeCode.length),
      );
    }

    _stopPaymentPolling();
    setState(() {
      _transfer = entry.transfer;
      _paymentConfirmation = entry.confirmation;
      _paymentPollAttempts = 0;
      _hasShownPaymentReceived = entry.isConfirmed;
      _isCheckingPayment = false;
    });

    unawaited(
      AppLogger.instance.info(
        'VietQR',
        'History entry selected',
        context: {
          'paymentId': entry.paymentId,
          'storeCode': storeCode,
          'status': entry.statusCode(now),
          'canOpenQr': true,
        },
      ),
    );
  }

  Future<void> _saveHistoryEntries({
    required String trigger,
    required int entryCount,
  }) async {
    final userId = _historyUserId;
    if (userId == null || userId.trim().isEmpty) return;

    try {
      await _historyStore.save(userId, _historyEntries);
      await AppLogger.instance.info(
        'VietQR',
        'History entries saved',
        context: {
          'trigger': trigger,
          'entryCount': entryCount,
          'historyScope': userId,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'VietQR',
        'History entries save failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'trigger': trigger,
          'entryCount': entryCount,
          'historyScope': userId,
        },
      );
    }
  }

  void _syncHistoryScope(User? user) {
    final userId = _historyScopeForUser(user);
    if (_historyUserId == userId) return;

    _historyUserId = userId;
    _historyErrorMessage = null;
    _historyEntries = [];

    _stopPaymentPolling();
    _transfer = null;
    _paymentConfirmation = null;
    _paymentPollAttempts = 0;
    _hasShownPaymentReceived = false;

    if (userId.isEmpty) {
      return;
    }

    unawaited(_loadHistory(userId));
  }

  String _historyScopeForUser(User? user) {
    final userId = user?.id?.trim() ?? '';
    if (userId.isNotEmpty) return userId;
    final email = user?.email.trim().toLowerCase() ?? '';
    return email;
  }

  Future<void> _loadHistory(String userId) async {
    if (_isHistoryLoading) return;

    final startedAt = DateTime.now();
    try {
      setState(() {
        _isHistoryLoading = true;
        _historyErrorMessage = null;
      });
      await AppLogger.instance.info(
        'VietQR',
        'History entries load started',
        context: {'historyScope': userId},
      );

      final entries = await _historyStore.load(userId);
      if (!mounted) return;

      setState(() {
        _historyEntries = entries;
      });
      await AppLogger.instance.info(
        'VietQR',
        'History entries load succeeded',
        context: {
          'historyScope': userId,
          'entryCount': entries.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'VietQR',
        'History entries load failed',
        error: error,
        stackTrace: stackTrace,
        upload: false,
        context: {
          'historyScope': userId,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        setState(() {
          _historyErrorMessage =
              'Chưa tải được lịch sử tạo QR. Vui lòng thử lại.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isHistoryLoading = false);
      }
    }
  }

  Future<void> _refreshScreen() async {
    final user = context.read<AuthProvider>().user;
    final tasks = <Future<void>>[];
    final historyScope = _historyScopeForUser(user);
    if (historyScope.isNotEmpty) {
      tasks.add(_loadHistory(historyScope));
    }
    final storeSignature = _storeOptionsSignature;
    if (user?.isSuperAdmin == true && storeSignature != null) {
      tasks.add(_loadAccessibleStoreOptions(user!, storeSignature));
    }
    if (_transfer != null && !_hasConfirmedPayment) {
      tasks.add(_checkPayment(showFeedback: true));
    }
    if (tasks.isEmpty) return;
    await Future.wait(tasks);
  }

  void _stopPaymentPolling() {
    _isCheckingPayment = false;
  }

  bool _canAutoConfirm(VietQrTransfer transfer) {
    return transfer.id.isNotEmpty &&
        transfer.amount != null &&
        transfer.transferContent.trim().isNotEmpty;
  }

  bool get _hasConfirmedPayment => _paymentConfirmation?.confirmed == true;

  bool _shouldStopAutoCheck(VietQrPaymentConfirmation confirmation) {
    return confirmation.confirmed ||
        confirmation.reason == 'MISSING_MATCH_FIELDS' ||
        confirmation.reason == 'MULTIPLE_MATCHES' ||
        confirmation.reason == 'EXPIRED_VIETNAM_15M' ||
        confirmation.reason == 'EXPIRED_VIETNAM_DAY';
  }

  Future<void> _checkPayment({bool showFeedback = false}) async {
    final transfer = _transfer;
    if (transfer == null ||
        transfer.id.isEmpty ||
        _isCheckingPayment ||
        _hasConfirmedPayment) {
      return;
    }
    setState(() {
      _isCheckingPayment = true;
      _paymentPollAttempts += 1;
    });
    try {
      final confirmation = await _repository.confirmPayment(transfer.id);
      if (!mounted) return;
      setState(() => _paymentConfirmation = confirmation);
      await _storeActiveHistoryEntry(
        transfer: transfer,
        confirmation: confirmation,
      );
      await AppLogger.instance.info(
        'VietQR',
        'Payment confirmation checked',
        context: {
          'paymentId': transfer.id,
          'attempt': _paymentPollAttempts,
          'confirmed': confirmation.confirmed,
          'reason': confirmation.reason,
          'matchedAmount': confirmation.matchedAmount,
        },
      );
      if (_shouldStopAutoCheck(confirmation)) {
        _stopPaymentPolling();
      }
      if (!mounted) return;
      if (confirmation.confirmed && !_hasShownPaymentReceived) {
        _hasShownPaymentReceived = true;
        AppToast.show(
          context,
          const SnackBar(
            content: Text('Đã nhận thanh toán'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (showFeedback) {
        AppToast.show(
          context,
          SnackBar(content: Text(_confirmationMessage(confirmation))),
        );
      }
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'Payment confirmation check failed',
        error: e,
        upload: showFeedback,
        context: {'paymentId': transfer.id, 'attempt': _paymentPollAttempts},
      );
      if (mounted) {
        if (showFeedback) {
          AppToast.show(
            context,
            SnackBar(
              content: Text('Chưa kiểm tra được thanh toán. Vui lòng thử lại.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isCheckingPayment = false);
    }
  }

  void _handleRealtimeEnvelope(RealtimeEnvelope envelope) {
    if (!mounted ||
        envelope.topic != _realtimeTopic ||
        envelope.kind != _realtimeKind) {
      return;
    }
    _pendingRealtimePayments[envelope.id] = envelope;
    _scheduleRealtimePaymentFlush();
    unawaited(
      AppLogger.instance.info(
        'VietQRRealtime',
        'VietQR realtime payment event queued',
        context: {
          'eventId': envelope.id,
          'sequence': envelope.sequence,
          'storeCode': envelope.data['storeCode']?.toString(),
          'pendingCount': _pendingRealtimePayments.length,
        },
      ),
    );
  }

  void _scheduleRealtimePaymentFlush() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(
      widget.realtimeDebounce,
      () => unawaited(_flushRealtimePayments()),
    );
    _realtimeMaxWaitTimer ??= Timer(
      widget.realtimeMaxWait,
      () => unawaited(_flushRealtimePayments()),
    );
  }

  Future<void> _flushRealtimePayments() async {
    _cancelRealtimePaymentTimers();
    if (!mounted || _pendingRealtimePayments.isEmpty) return;
    if (_isFlushingRealtimePayments) return;
    _isFlushingRealtimePayments = true;
    final pending = _pendingRealtimePayments.values.toList(growable: false);
    _pendingRealtimePayments.clear();
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'VietQRRealtime',
      'VietQR realtime payment batch started',
      context: {'eventCount': pending.length},
    );
    try {
      for (final envelope in pending) {
        if (!mounted) break;
        await _applyRealtimePaymentEvent(envelope.kind, envelope.data);
      }
      await AppLogger.instance.info(
        'VietQRRealtime',
        'VietQR realtime payment batch completed',
        context: {
          'eventCount': pending.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'VietQRRealtime',
        'VietQR realtime payment batch failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'eventCount': pending.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } finally {
      _isFlushingRealtimePayments = false;
      if (mounted && _pendingRealtimePayments.isNotEmpty) {
        _scheduleRealtimePaymentFlush();
      }
    }
  }

  void _cancelRealtimePaymentTimers() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    _realtimeMaxWaitTimer?.cancel();
    _realtimeMaxWaitTimer = null;
  }

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (!mounted || _transfer == null || _hasConfirmedPayment) return;
    unawaited(_refreshPaymentAfterRealtimeSync(reason));
  }

  Future<void> _refreshPaymentAfterRealtimeSync(
    RealtimeSyncReason reason,
  ) async {
    final transfer = _transfer;
    if (!mounted || transfer == null || _isCheckingPayment) return;
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'VietQRRealtime',
      'VietQR payment sync refresh started',
      context: {'reason': reason.name, 'paymentId': transfer.id},
    );
    await _checkPayment();
    await AppLogger.instance.info(
      'VietQRRealtime',
      'VietQR payment sync refresh completed',
      context: {
        'reason': reason.name,
        'paymentId': transfer.id,
        'confirmed': _hasConfirmedPayment,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
  }

  Future<void> _applyRealtimePaymentEvent(
    String eventType,
    Map<String, dynamic> payload,
  ) async {
    final amount = _readRealtimeAmount(payload['amount']);
    final transactionContent = _firstRealtimeText(payload, const [
      'transactionContent',
      'transferContent',
      'content',
      'description',
    ]);
    final eventStoreCode = _firstRealtimeText(payload, const [
      'storeCode',
      'storeId',
    ]).toUpperCase();
    if (amount == null || transactionContent.isEmpty) {
      await AppLogger.instance.info(
        'VietQRRealtime',
        'VietQR realtime event skipped because match fields are missing',
        context: {
          'eventType': eventType,
          'storeCode': eventStoreCode,
          'hasAmount': amount != null,
          'hasTransactionContent': transactionContent.isNotEmpty,
        },
      );
      return;
    }

    final now = DateTime.now();
    final matches = <int>[];
    for (var index = 0; index < _historyEntries.length; index += 1) {
      final entry = _historyEntries[index];
      if (_historyEntryMatchesRealtime(
        entry,
        now,
        eventStoreCode,
        amount,
        transactionContent,
      )) {
        matches.add(index);
      }
    }

    if (matches.isEmpty) {
      await AppLogger.instance.info(
        'VietQRRealtime',
        'VietQR realtime event did not match pending QR history',
        context: {
          'eventType': eventType,
          'storeCode': eventStoreCode,
          'amount': amount,
          'pendingCount': _historyEntries
              .where((entry) => !entry.isConfirmed && entry.canOpenQr(now))
              .length,
        },
      );
      return;
    }

    final matchedIndex = matches.first;
    final entry = _historyEntries[matchedIndex];
    final confirmation = VietQrPaymentConfirmation(
      id: entry.paymentId,
      status: 'PAID',
      confirmed: true,
      reason: 'REALTIME_PAYMENT_EVENT',
      matchedTransactionNumber: _firstRealtimeText(payload, const [
        'transactionNumber',
        'transactionReference',
        'txnReference',
        'statementNumber',
        'transactionId',
      ]),
      matchedAmount: amount,
      matchedTranTime:
          _readRealtimeDate(payload['paidAt']) ??
          _readRealtimeDate(payload['createdAt']),
      matchedPayerName: _nullableRealtimeText(payload, 'payerName'),
      matchedPayerAccount: _nullableRealtimeText(payload, 'payerAccount'),
      matchedTransactionContent: transactionContent,
      confirmedAt: DateTime.now(),
    );
    final nextEntries = List<VietQrHistoryEntry>.from(_historyEntries);
    nextEntries[matchedIndex] = entry.copyWith(confirmation: confirmation);
    final isCurrentTransfer = _transfer?.id == entry.paymentId;
    final shouldShowSnack = isCurrentTransfer && !_hasShownPaymentReceived;

    if (!mounted) return;
    setState(() {
      _historyEntries = nextEntries;
      if (isCurrentTransfer) {
        _paymentConfirmation = confirmation;
        _isCheckingPayment = false;
        _hasShownPaymentReceived = true;
      }
      _historyErrorMessage = null;
    });
    await _saveHistoryEntries(
      trigger: 'realtime_match',
      entryCount: nextEntries.length,
    );
    await AppLogger.instance.info(
      'VietQRRealtime',
      'VietQR realtime payment matched pending QR',
      context: {
        'eventType': eventType,
        'paymentId': entry.paymentId,
        'storeCode': entry.storeCode,
        'amount': amount,
        'matchCount': matches.length,
        'transactionId': payload['transactionId']?.toString(),
      },
    );
    if (shouldShowSnack && mounted) {
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Đã nhận thanh toán'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  bool _historyEntryMatchesRealtime(
    VietQrHistoryEntry entry,
    DateTime now,
    String eventStoreCode,
    int amount,
    String transactionContent,
  ) {
    if (entry.isConfirmed || !entry.canOpenQr(now)) return false;
    final transfer = entry.transfer;
    if (transfer.amount == null || transfer.amount != amount) return false;
    final entryStoreCode = entry.storeCode.trim().toUpperCase();
    if (eventStoreCode.isNotEmpty &&
        entryStoreCode.isNotEmpty &&
        eventStoreCode != entryStoreCode) {
      return false;
    }
    final expectedContent = _normalizeMatchText(transfer.transferContent);
    final actualContent = _normalizeMatchText(transactionContent);
    return expectedContent.isNotEmpty &&
        actualContent.contains(expectedContent);
  }

  int? _readRealtimeAmount(Object? value) {
    if (value is num) return value.toInt();
    final normalized = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized == null || normalized.isEmpty) return null;
    return int.tryParse(normalized);
  }

  String _firstRealtimeText(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String? _nullableRealtimeText(Map<String, dynamic> payload, String key) {
    final value = payload[key]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  DateTime? _readRealtimeDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _normalizeMatchText(String value) {
    const accentMap = {
      'À': 'A',
      'Á': 'A',
      'Ả': 'A',
      'Ã': 'A',
      'Ạ': 'A',
      'Ă': 'A',
      'Ằ': 'A',
      'Ắ': 'A',
      'Ẳ': 'A',
      'Ẵ': 'A',
      'Ặ': 'A',
      'Â': 'A',
      'Ầ': 'A',
      'Ấ': 'A',
      'Ẩ': 'A',
      'Ẫ': 'A',
      'Ậ': 'A',
      'Đ': 'D',
      'È': 'E',
      'É': 'E',
      'Ẻ': 'E',
      'Ẽ': 'E',
      'Ẹ': 'E',
      'Ê': 'E',
      'Ề': 'E',
      'Ế': 'E',
      'Ể': 'E',
      'Ễ': 'E',
      'Ệ': 'E',
      'Ì': 'I',
      'Í': 'I',
      'Ỉ': 'I',
      'Ĩ': 'I',
      'Ị': 'I',
      'Ò': 'O',
      'Ó': 'O',
      'Ỏ': 'O',
      'Õ': 'O',
      'Ọ': 'O',
      'Ô': 'O',
      'Ồ': 'O',
      'Ố': 'O',
      'Ổ': 'O',
      'Ỗ': 'O',
      'Ộ': 'O',
      'Ơ': 'O',
      'Ờ': 'O',
      'Ớ': 'O',
      'Ở': 'O',
      'Ỡ': 'O',
      'Ợ': 'O',
      'Ù': 'U',
      'Ú': 'U',
      'Ủ': 'U',
      'Ũ': 'U',
      'Ụ': 'U',
      'Ư': 'U',
      'Ừ': 'U',
      'Ứ': 'U',
      'Ử': 'U',
      'Ữ': 'U',
      'Ự': 'U',
      'Ỳ': 'Y',
      'Ý': 'Y',
      'Ỷ': 'Y',
      'Ỹ': 'Y',
      'Ỵ': 'Y',
    };
    final upper = value.toUpperCase();
    final buffer = StringBuffer();
    for (final rune in upper.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(accentMap[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^A-Z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _scanOrderCode() async {
    FocusScope.of(context).unfocus();
    try {
      final result = await showBarcodeScanner(
        context,
        title: 'Quét mã đơn',
        instruction: 'Đưa barcode mã đơn vào khung hình để quét',
        helperText: 'Kết quả quét sẽ điền vào ô mã đơn',
        parsePhongVuSku: false,
      );
      if (result == null || !mounted) return;

      final scannedCode = result.trim().toUpperCase();
      _orderCodeController.value = TextEditingValue(
        text: scannedCode,
        selection: TextSelection.collapsed(offset: scannedCode.length),
      );
      await AppLogger.instance.info(
        'VietQR',
        'Order code scanned',
        context: {'codeLength': scannedCode.length},
      );
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'Order code scan failed',
        error: e,
      );
      if (mounted) {
        AppToast.show(
          context,
          SnackBar(
            content: Text('Chưa quét được mã đơn. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveQrImage() async {
    final transfer = _transfer;
    if (transfer == null || _isSaving) return;

    setState(() => _isSaving = true);
    final startedAt = DateTime.now();
    try {
      final fileName = buildVietQrImageFileName(
        transfer.transferContent,
        DateTime.now(),
      );
      await AppLogger.instance.info(
        'VietQR',
        'QR image save started',
        context: {
          'paymentId': transfer.id,
          'brandKey': transfer.qrBrand.key,
          'brandTitle': transfer.qrBrand.title,
          'fileName': fileName,
        },
      );

      final bytes = await _buildExportPng(transfer);
      final result = await _imageSaver.savePng(
        bytes: bytes,
        fileName: fileName,
      );
      if (result.usedFallback) {
        await AppLogger.instance.warn(
          'VietQR',
          'QR image save used fallback',
          context: {
            'paymentId': transfer.id,
            'method': result.method,
            'destination': result.destination,
            'fallbackReason': result.fallbackReason,
          },
        );
      }
      await AppLogger.instance.info(
        'VietQR',
        'QR image saved',
        context: {
          'paymentId': transfer.id,
          'brandKey': transfer.qrBrand.key,
          'brandTitle': transfer.qrBrand.title,
          'fileName': result.fileName,
          'method': result.method,
          'destination': result.destination,
          'byteCount': bytes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        AppToast.show(context, SnackBar(content: Text(result.userMessage)));
      }
    } catch (e) {
      await AppLogger.instance.error(
        'VietQR',
        'QR image save failed',
        error: e,
        context: {
          'paymentId': transfer.id,
          'brandKey': transfer.qrBrand.key,
          'brandTitle': transfer.qrBrand.title,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        AppToast.show(
          context,
          SnackBar(
            content: Text('Chưa lưu được ảnh QR. Vui lòng thử lại.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildStoreField(User? user, List<StoreBranch> storeOptions) {
    String? selectedStoreCode = _storeCodeController.text.trim().toUpperCase();
    final allowedStoreIds = storeOptions
        .map((store) => store.storeId.trim().toUpperCase())
        .where((storeId) => storeId.isNotEmpty)
        .toSet();
    if (!allowedStoreIds.contains(selectedStoreCode)) {
      selectedStoreCode = null;
    }

    if (_isStoreOptionsLoading &&
        user?.isSuperAdmin == true &&
        storeOptions.isEmpty) {
      return const AppStatePanel.loading(
        title: 'Đang tải danh sách showroom',
        message: 'Đang lấy danh sách showroom để chọn nơi tạo QR.',
        compact: true,
      );
    }

    if (_storeOptionsErrorMessage != null && storeOptions.isEmpty) {
      return AppStatePanel.error(
        title: 'Chưa tải được danh sách showroom',
        message: _storeOptionsErrorMessage!,
        actionLabel: 'Thử lại',
        actionIcon: Icons.refresh_rounded,
        onAction: () => unawaited(_syncAccessibleStoreOptions(user)),
        compact: true,
      );
    }

    if (storeOptions.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Chưa có showroom khả dụng',
        message: 'Tài khoản này chưa được gán showroom để tạo QR.',
        compact: true,
      );
    }

    if (storeOptions.length > 1) {
      return AppCombobox<String>.single(
        key: ValueKey(
          'vietqr-store-${allowedStoreIds.join(',')}-$selectedStoreCode',
        ),
        label: 'Mã showroom',
        value: selectedStoreCode,
        hintText: 'Chọn showroom tạo QR',
        icon: Icons.store_outlined,
        options: storeOptions
            .map(
              (store) => AppComboboxOption<String>(
                value: store.storeId.trim().toUpperCase(),
                label: _storeOptionLabel(store),
                searchKeywords: [store.storeId, store.storeName],
              ),
            )
            .toList(growable: false),
        allowClear: false,
        textCapitalization: TextCapitalization.characters,
        onChanged: _isLoading ? null : _selectStoreCode,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Vui lòng chọn showroom để tạo QR';
          }
          return null;
        },
      );
    }

    return AppFormTextInput(
      controller: _storeCodeController,
      label: 'Mã showroom',
      icon: Icons.store_outlined,
      readOnly: true,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Tài khoản chưa có showroom để tạo QR';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final transfer = _transfer;
    final user = context.watch<AuthProvider>().user;
    final storeOptions = _currentStoreOptions(user);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop =
            constraints.maxWidth >= AppLayoutTokens.desktopBreakpoint;
        final currentPanel = transfer == null
            ? Form(key: _formKey, child: _buildInputCard(user, storeOptions))
            : _buildResultView(transfer);
        final historyPanel = _buildHistoryPanel();

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AppResponsiveScrollView(
            maxWidth: AppLayoutTokens.pageMaxWidth,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            onRefresh: _refreshScreen,
            refreshLogSource: 'VietQR',
            refreshLogContext: () => {
              'hasTransfer': _transfer != null,
              'hasConfirmedPayment': _hasConfirmedPayment,
              'historyCount': _historyEntries.length,
              'storeOptionCount': storeOptions.length,
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: currentPanel),
                      const SizedBox(width: AppLayoutTokens.sectionGap),
                      SizedBox(width: 380, child: historyPanel),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      currentPanel,
                      const SizedBox(height: AppLayoutTokens.sectionGap),
                      historyPanel,
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputCard(User? user, List<StoreBranch> storeOptions) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Thông tin chuyển khoản', style: AppTextStyles.headingS),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          AppFormTextInput(
            controller: _amountController,
            label: 'Số tiền',
            hintText: 'Để trống nếu người chuyển tự nhập',
            icon: Icons.payments_outlined,
            suffixText: 'VND',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: _formatAmount,
            validator: (_) {
              final amount = _amountValue;
              if (_amountController.text.trim().isEmpty) {
                return null;
              }
              if (amount == null || amount <= 0) {
                return 'Số tiền phải lớn hơn 0 hoặc để trống';
              }
              return null;
            },
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          AppFormTextInput(
            controller: _orderCodeController,
            label: 'Mã đơn / nội dung',
            hintText: 'Có thể để trống để người chuyển tự nhập',
            icon: Icons.receipt_long_outlined,
            suffixIcon: AppIconAction(
              tooltip: 'Quét mã đơn',
              onPressed: _isLoading ? null : _scanOrderCode,
              icon: Icons.qr_code_scanner_rounded,
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          _buildStoreField(user, storeOptions),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          AppFormTextInput(
            controller: _previewContentController,
            label: 'Nội dung chuyển khoản',
            hintText: 'Người chuyển tự nhập nếu ô này trống',
            icon: Icons.lock_outline,
            readOnly: true,
          ),
          const SizedBox(height: AppLayoutTokens.formSectionGap),
          AppPrimaryButton(
            onPressed: _createQr,
            icon: Icons.qr_code_2_rounded,
            label: 'Tạo mã QR',
            isLoading: _isLoading,
            loadingLabel: 'Đang tạo...',
          ),
        ],
      ),
    );
  }

  Widget _buildResultView(VietQrTransfer transfer) {
    final now = DateTime.now();
    final confirmed = _hasConfirmedPayment;
    final expired = _isTransferExpired(transfer, now);
    final hasConfirmation = _paymentConfirmation != null;
    final canAutoConfirm = _canAutoConfirm(transfer) && !expired;
    final expiryLabel = DateFormat(
      'HH:mm dd/MM',
    ).format(transfer.expiresAt.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (confirmed && _paymentConfirmation != null)
          PaymentSuccessPanel(
            confirmation: _paymentConfirmation!,
            amountFormatter: _currencyFormatter,
          )
        else if (expired)
          AppStatusBanner(
            icon: Icons.schedule_rounded,
            title: 'QR đã hết hạn 15 phút',
            message: 'Hãy tạo mã mới để tiếp tục.',
            tone: AppStateTone.warning,
          )
        else
          AppStatusBanner(
            icon: Icons.timelapse_rounded,
            title: 'QR còn hạn đến $expiryLabel',
            message:
                'Mã này vẫn xem lại được từ lịch sử trong thời gian còn hạn.',
            tone: AppStateTone.info,
          ),
        if (!expired && !confirmed) ...[
          const SizedBox(height: 16),
          _buildTransferCard(transfer),
        ],
        if (hasConfirmation && !confirmed) ...[
          const SizedBox(height: 16),
          PaymentConfirmationCard(
            confirmation: _paymentConfirmation!,
            amountFormatter: _currencyFormatter,
          ),
        ] else if (!confirmed && canAutoConfirm) ...[
          const SizedBox(height: 16),
          PaymentWaitingCard(isChecking: _isCheckingPayment),
        ],
        if (!expired && !confirmed) ...[
          const SizedBox(height: 16),
          AppPrimaryButton(
            onPressed: _confirmPayment,
            icon: Icons.sync_rounded,
            label: 'Kiểm tra ngay',
            isLoading: _isCheckingPayment,
            loadingLabel: 'Đang kiểm tra...',
          ),
          const SizedBox(height: 10),
          AppPrimaryButton(
            onPressed: _saveQrImage,
            icon: Icons.download_rounded,
            label: 'Tải ảnh QR',
            isLoading: _isSaving,
            loadingLabel: 'Đang lưu...',
          ),
          const SizedBox(height: 10),
        ],
        AppSecondaryButton(
          onPressed: _createNewQr,
          icon: Icons.add_rounded,
          label: 'Tạo mã mới',
        ),
        const SizedBox(height: 10),
        AppSecondaryButton(
          onPressed: () => context.pop(),
          icon: Icons.arrow_back_rounded,
          label: 'Quay lại',
        ),
      ],
    );
  }

  Widget _buildTransferCard(VietQrTransfer transfer) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QrWithLogo(size: 280, transfer: transfer),
          const SizedBox(height: 20),
          AppInfoRow(
            label: 'Ngân hàng',
            value: transfer.bankName,
            labelWidth: 118,
          ),
          AppInfoRow(
            label: 'Số tài khoản',
            value: transfer.accountNumber,
            labelWidth: 118,
          ),
          AppInfoRow(
            label: 'Chủ tài khoản',
            value: transfer.accountName,
            labelWidth: 118,
          ),
          AppInfoRow(
            label: 'Số tiền',
            value: _amountLabel(transfer.amount),
            labelWidth: 118,
          ),
          AppInfoRow(
            label: 'Nội dung',
            value: _contentLabel(transfer.transferContent),
            labelWidth: 118,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryPanel() {
    final now = DateTime.now();
    final historyCount = _historyEntries.length;
    final historyScope = _historyUserId ?? '';

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('Lịch sử tạo QR', style: AppTextStyles.headingS),
              ),
              if (historyCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary500.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '$historyCount',
                    style: AppTextStyles.labelM.copyWith(
                      color: AppColors.primary500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Chạm vào mã còn hạn để xem lại QR. Mã hết hạn vẫn hiển thị trạng thái để đối chiếu.',
            style: AppTextStyles.bodyM.copyWith(color: AppColors.neutral500),
          ),
          const SizedBox(height: 16),
          if (_isHistoryLoading)
            const AppStatePanel.loading(
              title: 'Đang tải lịch sử',
              message: 'Đang đọc các mã QR đã tạo trước đó.',
              compact: true,
            )
          else if (_historyErrorMessage != null)
            AppStatePanel.error(
              title: 'Chưa tải được lịch sử',
              message: _historyErrorMessage!,
              actionLabel: 'Thử lại',
              actionIcon: Icons.refresh_rounded,
              onAction: historyScope.isEmpty
                  ? null
                  : () => unawaited(_loadHistory(historyScope)),
              compact: true,
            )
          else if (_historyEntries.isEmpty)
            const AppStatePanel.empty(
              title: 'Chưa có lịch sử tạo QR',
              message: 'Các mã QR mới tạo sẽ xuất hiện ở đây.',
              compact: true,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var index = 0;
                  index < _historyEntries.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(height: 12),
                  _buildHistoryEntryTile(_historyEntries[index], now),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryEntryTile(VietQrHistoryEntry entry, DateTime now) {
    final canOpen = entry.canOpenQr(now);
    final statusLabel = _historyStatusLabel(entry, now);
    final statusTone = _historyStatusTone(entry, now);
    final statusIcon = _historyStatusIcon(entry, now);
    final title = entry.storeCode.isEmpty
        ? 'Mã ${entry.paymentId}'
        : 'Showroom ${entry.storeCode}';
    final createdLabel = DateFormat(
      'HH:mm dd/MM',
    ).format(entry.createdAt.toLocal());
    final expiryLabel = DateFormat(
      'HH:mm dd/MM',
    ).format(entry.expiresAt.toLocal());
    final content = entry.transfer.transferContent.trim().isEmpty
        ? 'Người chuyển tự nhập nội dung'
        : entry.transfer.transferContent.trim();
    final amountLabel = _amountLabel(entry.transfer.amount);

    return AppSurfaceCard(
      onTap: canOpen ? () => _selectHistoryEntry(entry) : null,
      backgroundColor: canOpen
          ? AppColors.primary500.withValues(alpha: 0.06)
          : null,
      borderColor: canOpen
          ? AppColors.primary500.withValues(alpha: 0.18)
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelM),
                const SizedBox(height: 4),
                Text(
                  content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyM,
                ),
                const SizedBox(height: 6),
                Text(
                  '$createdLabel • ${canOpen ? 'Còn hạn đến $expiryLabel' : 'Hết hạn lúc $expiryLabel'}',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Số tiền: $amountLabel',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
              ],
            ),
          );
          final summary = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusTone.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(statusIcon, color: statusTone.color, size: 22),
              ),
              const SizedBox(width: 12),
              details,
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatusChip(
                        statusLabel,
                        statusTone,
                        fill: true,
                      ),
                    ),
                    if (canOpen) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.primary500,
                      ),
                    ],
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: summary),
              const SizedBox(width: 12),
              _buildStatusChip(statusLabel, statusTone),
              if (canOpen) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primary500,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(
    String label,
    AppStateTone tone, {
    bool fill = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(
            tone == AppStateTone.success
                ? Icons.check_circle_rounded
                : tone == AppStateTone.warning
                ? Icons.schedule_rounded
                : tone == AppStateTone.error
                ? Icons.error_outline_rounded
                : Icons.timelapse_rounded,
            size: 14,
            color: tone.color,
          ),
          const SizedBox(width: 4),
          if (fill)
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelM.copyWith(color: tone.color),
              ),
            )
          else
            Text(
              label,
              style: AppTextStyles.labelM.copyWith(color: tone.color),
            ),
        ],
      ),
    );
  }

  String _historyStatusLabel(VietQrHistoryEntry entry, DateTime now) {
    if (entry.isConfirmed) return 'Đã nhận thanh toán';
    final statusCode = entry.statusCode(now);
    final reason = entry.statusReason(now);
    return switch (statusCode) {
      'EXPIRED' => 'Đã hết hạn',
      'AMBIGUOUS' => 'Nhiều giao dịch',
      'NOT_FOUND' => 'Chưa thấy giao dịch',
      'MANUAL_REVIEW' => switch (reason) {
        'MISSING_MATCH_FIELDS' => 'Thiếu dữ liệu',
        _ => 'Cần kiểm tra thủ công',
      },
      'FAILED' => switch (reason) {
        'MISSING_MATCH_FIELDS' => 'Thiếu dữ liệu',
        'MULTIPLE_MATCHES' => 'Nhiều giao dịch',
        'EXPIRED_VIETNAM_15M' || 'EXPIRED_VIETNAM_DAY' => 'Đã hết hạn',
        _ => 'Chưa xác nhận',
      },
      'PENDING' => 'Còn hạn',
      _ => 'Còn hạn',
    };
  }

  AppStateTone _historyStatusTone(VietQrHistoryEntry entry, DateTime now) {
    if (entry.isConfirmed) return AppStateTone.success;
    final statusCode = entry.statusCode(now);
    return switch (statusCode) {
      'EXPIRED' => AppStateTone.warning,
      'AMBIGUOUS' => AppStateTone.warning,
      'NOT_FOUND' => AppStateTone.warning,
      'MANUAL_REVIEW' => AppStateTone.warning,
      'FAILED' => AppStateTone.error,
      'PENDING' => AppStateTone.info,
      _ => AppStateTone.info,
    };
  }

  IconData _historyStatusIcon(VietQrHistoryEntry entry, DateTime now) {
    if (entry.isConfirmed) return Icons.check_circle_rounded;
    final statusCode = entry.statusCode(now);
    return switch (statusCode) {
      'EXPIRED' => Icons.schedule_rounded,
      'AMBIGUOUS' => Icons.warning_amber_rounded,
      'NOT_FOUND' => Icons.search_off_rounded,
      'MANUAL_REVIEW' => Icons.info_outline_rounded,
      'FAILED' => Icons.error_outline_rounded,
      'PENDING' => Icons.timelapse_rounded,
      _ => Icons.timelapse_rounded,
    };
  }

  bool _isTransferExpired(VietQrTransfer transfer, [DateTime? now]) {
    final current = now ?? DateTime.now();
    return !current.isBefore(transfer.expiresAt);
  }

  String _confirmationMessage(VietQrPaymentConfirmation confirmation) {
    switch (confirmation.reason) {
      case 'NO_MATCH':
        return 'Chưa thấy giao dịch khớp';
      case 'MULTIPLE_MATCHES':
        return 'Có nhiều giao dịch khớp, cần kiểm tra thủ công';
      case 'MISSING_MATCH_FIELDS':
        return 'QR thiếu số tiền hoặc nội dung, cần kiểm tra thủ công';
      case 'EXPIRED_VIETNAM_15M':
        return 'QR đã hết hạn 15 phút. Vui lòng tạo mã mới.';
      case 'EXPIRED_VIETNAM_DAY':
        return 'QR đã hết hạn. Vui lòng tạo mã mới.';
      default:
        return 'Chưa xác nhận được thanh toán';
    }
  }

  Future<Uint8List> _buildExportPng(VietQrTransfer transfer) async {
    const width = 1080.0;
    const height = 1560.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = AppColors.surface;
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), paint);

    final titleStyle = AppTextStyles.headingXL.copyWith(
      color: AppColors.primary500,
      fontSize: 58,
      fontWeight: FontWeight.w700,
    );
    final labelStyle = AppTextStyles.headingS.copyWith(
      color: AppColors.neutral700,
      fontSize: 32,
    );
    final valueStyle = AppTextStyles.headingXL.copyWith(
      color: AppColors.neutral800,
      fontSize: 38,
      fontWeight: FontWeight.w700,
    );

    _drawText(canvas, transfer.qrBrand.title, 72, 64, titleStyle);
    _drawText(canvas, 'Mã chuyển khoản VietQR', 72, 136, labelStyle);

    const qrSize = 690.0;
    const qrLeft = (width - qrSize) / 2;
    const qrTop = 230.0;
    final qrPainter = QrPainter(
      data: transfer.qrPayload,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: AppColors.neutral900,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: AppColors.neutral900,
      ),
    );
    canvas.translate(qrLeft, qrTop);
    qrPainter.paint(canvas, const Size(qrSize, qrSize));
    canvas.translate(-qrLeft, -qrTop);

    final logo = await _loadUiImage(transfer.qrBrand.logoAsset);
    const logoSize = 150.0;
    final logoRect = Rect.fromCenter(
      center: const Offset(width / 2, qrTop + qrSize / 2),
      width: logoSize,
      height: logoSize,
    );
    final logoBg = RRect.fromRectAndRadius(
      logoRect.inflate(18),
      const Radius.circular(AppRadius.xxl),
    );
    canvas.drawRRect(logoBg, Paint()..color = AppColors.surface);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(logoRect, const Radius.circular(AppRadius.xl)),
    );
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      logoRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    var y = 990.0;
    y = _drawInfo(
      canvas,
      'Ngân hàng',
      transfer.bankName,
      y,
      labelStyle,
      valueStyle,
    );
    y = _drawInfo(
      canvas,
      'Số tài khoản',
      transfer.accountNumber,
      y,
      labelStyle,
      valueStyle,
    );
    y = _drawInfo(
      canvas,
      'Chủ tài khoản',
      transfer.accountName,
      y,
      labelStyle,
      valueStyle,
    );
    y = _drawInfo(
      canvas,
      'Số tiền',
      _amountLabel(transfer.amount),
      y,
      labelStyle,
      valueStyle,
    );
    _drawInfo(
      canvas,
      'Nội dung',
      _contentLabel(transfer.transferContent),
      y,
      labelStyle,
      valueStyle,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<ui.Image> _loadUiImage(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  double _drawInfo(
    Canvas canvas,
    String label,
    String value,
    double y,
    TextStyle labelStyle,
    TextStyle valueStyle,
  ) {
    _drawText(canvas, label, 72, y, labelStyle);
    _drawText(canvas, value, 360, y - 4, valueStyle, maxWidth: 640);
    return y + 96;
  }

  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    TextStyle style, {
    double maxWidth = 940,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(x, y));
  }
}
