import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../data/repositories/warranty_repository.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/logging/app_logger.dart';

class WarrantyProvider extends ChangeNotifier {
  final WarrantyRepository _repository;

  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _receipts = [];
  Map<String, dynamic>? _currentDetails;

  WarrantyProvider(this._repository);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get receipts => _receipts;
  Map<String, dynamic>? get currentDetails => _currentDetails;

  Future<bool> saveWarranty({
    required String userEmail,
    required String receiptNumber,
    required List<File> images,
  }) async {
    await AppLogger.instance.info(
      'Warranty',
      'Warranty save started',
      context: {
        'userEmail': userEmail,
        'receiptNumber': receiptNumber,
        'imageCount': images.length,
      },
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _repository.saveWarranty(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
        images: images,
      );

      final bool success = response['status'] == 'success';
      await AppLogger.instance.info(
        'Warranty',
        'Warranty save completed',
        context: {
          'userEmail': userEmail,
          'receiptNumber': receiptNumber,
          'imageCount': images.length,
          'success': success,
        },
      );
      _isLoading = false;
      notifyListeners();
      return success;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty save failed',
        context: {'receiptNumber': receiptNumber, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Chưa lưu được biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> showAllWarranty(String userEmail) async {
    await AppLogger.instance.info(
      'Warranty',
      'Warranty list started',
      context: {'userEmail': userEmail},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _receipts = await _repository.showAllWarranty(userEmail);
      await AppLogger.instance.info(
        'Warranty',
        'Warranty list succeeded',
        context: {'userEmail': userEmail, 'count': _receipts.length},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty list failed',
        context: {'userEmail': userEmail, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Chưa tải được danh sách biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> searchWarranty({
    required String userEmail,
    required String receiptNumber,
  }) async {
    await AppLogger.instance.info(
      'Warranty',
      'Warranty search started',
      context: {'userEmail': userEmail, 'receiptNumber': receiptNumber},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _receipts = await _repository.searchWarranty(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      await AppLogger.instance.info(
        'Warranty',
        'Warranty search succeeded',
        context: {'receiptNumber': receiptNumber, 'count': _receipts.length},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty search failed',
        context: {'receiptNumber': receiptNumber, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Chưa tìm được biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> getWarrantyDetails({
    required String userEmail,
    required String receiptNumber,
  }) async {
    await AppLogger.instance.info(
      'Warranty',
      'Warranty detail started',
      context: {'userEmail': userEmail, 'receiptNumber': receiptNumber},
    );
    _isLoading = true;
    _errorMessage = null;
    _currentDetails = null;
    notifyListeners();

    try {
      _currentDetails = await _repository.getWarrantyDetails(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      await AppLogger.instance.info(
        'Warranty',
        'Warranty detail succeeded',
        context: {'receiptNumber': receiptNumber},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty detail failed',
        context: {'receiptNumber': receiptNumber, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Chưa mở được chi tiết biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearDetails() {
    _currentDetails = null;
    notifyListeners();
  }

  void clearReceipts() {
    _receipts = [];
    notifyListeners();
  }
}
