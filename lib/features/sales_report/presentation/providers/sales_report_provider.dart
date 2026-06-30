import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/sales_report_repository.dart';
import '../../domain/sales_report.dart';

class SalesReportProvider extends ChangeNotifier {
  final SalesReportRepository _repository;
  final DateTime Function() _now;

  final List<SalesReportCategoryGroup> _categories = [];
  final List<Map<String, dynamic>> _adminItems = [];
  SalesReportOrderCheck? _checkedOrder;
  bool _isLoadingCategories = false;
  bool _isCheckingOrder = false;
  bool _isSubmitting = false;
  bool _isLoadingAdminList = false;
  bool _isExporting = false;
  String? _errorMessage;
  String? _successMessage;
  int _adminTotal = 0;
  int _adminPage = 0;
  int _adminLimit = 20;

  SalesReportProvider(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  List<SalesReportCategoryGroup> get categories =>
      List.unmodifiable(_categories);
  List<Map<String, dynamic>> get adminItems => List.unmodifiable(_adminItems);
  SalesReportOrderCheck? get checkedOrder => _checkedOrder;
  bool get isLoadingCategories => _isLoadingCategories;
  bool get isCheckingOrder => _isCheckingOrder;
  bool get isSubmitting => _isSubmitting;
  bool get isLoadingAdminList => _isLoadingAdminList;
  bool get isExporting => _isExporting;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  int get adminTotal => _adminTotal;
  int get adminPage => _adminPage;
  int get adminLimit => _adminLimit;
  bool get canGoPrevious => _adminPage > 0;
  bool get canGoNext => (_adminPage + 1) * _adminLimit < _adminTotal;

  Future<void> initialize(User? user, {bool admin = false}) async {
    await AppLogger.instance.info(
      'SalesReport',
      admin ? 'Sales report admin screen opened' : 'Sales report screen opened',
      context: {
        'admin': admin,
        'userId': user?.id,
        'storeId': user?.storeId,
        'hasSalesReport': user?.canUseFeature('SALES_REPORT') == true,
        'hasAdminSalesReports':
            user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
      },
    );
    await loadCategories(admin: admin);
    if (admin) await loadAdminList();
  }

  Future<void> loadCategories({bool admin = false}) async {
    if (_isLoadingCategories) return;
    _isLoadingCategories = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report categories load started',
        context: {'admin': admin},
      );
      final categories = await _repository.fetchCategories(admin: admin);
      _categories
        ..clear()
        ..addAll(categories);
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report categories load succeeded',
        context: {'admin': admin, 'count': categories.length},
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa tải được danh sách ngành hàng.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report categories load failed',
        error: error,
        context: {'admin': admin},
      );
    } finally {
      _isLoadingCategories = false;
      notifyListeners();
    }
  }

  Future<SalesReportOrderCheck?> checkOrder(String orderCode) async {
    if (_isCheckingOrder) return null;
    _isCheckingOrder = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order check started',
        context: {'orderLength': orderCode.trim().length},
      );
      final result = await _repository.checkOrder(orderCode);
      _checkedOrder = result;
      _successMessage = 'Đã kiểm tra đơn hàng.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report order check succeeded',
        context: {
          'orderLength': result.orderCode.length,
          'hasCategory': result.categoryGroup != null,
          'categoryCount': result.categoryGroups.length,
          'itemCount': result.items.length,
          'paymentCount': result.payments.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return result;
    } catch (error) {
      _checkedOrder = null;
      _errorMessage = _messageFor(error, 'Chưa kiểm tra được mã đơn hàng.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report order check failed',
        error: error,
        context: {
          'orderLength': orderCode.trim().length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return null;
    } finally {
      _isCheckingOrder = false;
      notifyListeners();
    }
  }

  Future<bool> submit(SalesReportInput input, User? user) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report submit started',
        context: {
          'type': input.reportType,
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'hasOrder': (input.orderCode ?? '').trim().isNotEmpty,
          'orderLength': (input.orderCode ?? '').trim().length,
          'hasPhone': (input.customerPhone ?? '').trim().isNotEmpty,
          'customerType': input.customerType,
          'customerIsStudent': input.customerIsStudent,
          'promotionCount': input.promotionCodes.length,
          'installmentSelected': input.installmentNeed,
          'installmentApproved': input.installmentApproved,
          'installmentPartnerCount': input.installmentPartnerCodes.length,
          'userId': user?.id,
          'storeId': user?.storeId,
        },
      );
      await _repository.create(input);
      _successMessage = 'Đã gửi báo cáo.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report submit succeeded',
        context: {
          'type': input.reportType,
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'customerType': input.customerType,
          'customerIsStudent': input.customerIsStudent,
          'promotionCount': input.promotionCodes.length,
          'installmentSelected': input.installmentNeed,
          'installmentApproved': input.installmentApproved,
          'installmentPartnerCount': input.installmentPartnerCodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa gửi được báo cáo.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report submit failed',
        error: error,
        context: {
          'type': input.reportType,
          'categoryGroupId': input.categoryGroupId,
          'categoryGroupCount': input.categoryGroupIds.length,
          'customerType': input.customerType,
          'promotionCount': input.promotionCodes.length,
          'installmentSelected': input.installmentNeed,
          'installmentApproved': input.installmentApproved,
          'installmentPartnerCount': input.installmentPartnerCodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clearCheckedOrder() {
    _checkedOrder = null;
    _successMessage = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> loadAdminList({int? page, SalesReportQuery? query}) async {
    if (_isLoadingAdminList) return;
    _isLoadingAdminList = true;
    _errorMessage = null;
    if (page != null) _adminPage = page;
    notifyListeners();
    final effectiveQuery =
        query ?? SalesReportQuery(page: _adminPage, limit: _adminLimit);
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report admin list started',
        context: {'page': effectiveQuery.page, 'limit': effectiveQuery.limit},
      );
      final data = await _repository.fetchList(effectiveQuery);
      final rows = data['items'] is List ? data['items'] as List : const [];
      _adminItems
        ..clear()
        ..addAll(
          rows.whereType<Map>().map(
            (row) => row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      _adminPage =
          int.tryParse(data['page']?.toString() ?? '') ?? effectiveQuery.page;
      _adminLimit =
          int.tryParse(data['limit']?.toString() ?? '') ?? effectiveQuery.limit;
      _adminTotal =
          int.tryParse(data['total']?.toString() ?? '') ?? _adminItems.length;
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report admin list succeeded',
        context: {'count': _adminItems.length, 'total': _adminTotal},
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Chưa tải được danh sách báo cáo.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report admin list failed',
        error: error,
      );
    } finally {
      _isLoadingAdminList = false;
      notifyListeners();
    }
  }

  Future<void> exportCsv({
    SalesReportQuery query = const SalesReportQuery(),
  }) async {
    if (_isExporting) return;
    _isExporting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    try {
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report export started',
        context: {'type': query.reportType},
      );
      final csvBytes = await _repository.exportCsv(query);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Lưu file báo cáo sale',
        fileName: 'opshub_bao_cao_sale_${_timestampForFile()}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: _ensureUtf8BomForCsv(csvBytes),
        lockParentWindow: true,
      );
      _successMessage = path == null ? 'Đã hủy lưu file.' : 'Đã xuất file.';
      await AppLogger.instance.info(
        'SalesReport',
        'Sales report export succeeded',
        context: {'saved': path != null, 'bytes': csvBytes.length},
      );
    } catch (error) {
      _errorMessage = _messageFor(error, 'Xuất file thất bại.');
      await AppLogger.instance.error(
        'SalesReport',
        'Sales report export failed',
        error: error,
      );
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<void> nextPage() async {
    if (canGoNext) await loadAdminList(page: _adminPage + 1);
  }

  Future<void> previousPage() async {
    if (canGoPrevious) await loadAdminList(page: _adminPage - 1);
  }

  String _messageFor(Object error, String fallback) {
    if (error is ApiException) return error.message;
    return fallback;
  }

  String _timestampForFile() {
    final now = _now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

Uint8List _ensureUtf8BomForCsv(Uint8List bytes) {
  const bom = [0xef, 0xbb, 0xbf];
  if (bytes.length >= bom.length &&
      bytes[0] == bom[0] &&
      bytes[1] == bom[1] &&
      bytes[2] == bom[2]) {
    return bytes;
  }
  return Uint8List.fromList([...bom, ...bytes]);
}
