import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../data/repositories/warranty_repository.dart';
import '../../../../core/network/api_exception.dart';

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
      _isLoading = false;
      notifyListeners();
      return success;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi không xác định: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> showAllWarranty(String userEmail) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _receipts = await _repository.showAllWarranty(userEmail);
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi không xác định: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> searchWarranty({
    required String userEmail,
    required String receiptNumber,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _receipts = await _repository.searchWarranty(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi không xác định: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> getWarrantyDetails({
    required String userEmail,
    required String receiptNumber,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _currentDetails = null;
    notifyListeners();

    try {
      _currentDetails = await _repository.getWarrantyDetails(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi không xác định: $e';
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
