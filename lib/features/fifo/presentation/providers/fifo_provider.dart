import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/repositories/fifo_repository.dart';
import '../../domain/entities/fifo_check_result.dart';
import '../../domain/entities/fifo_inventory_item.dart';

class FifoProvider extends ChangeNotifier {
  final FifoRepository _repository;

  FifoProvider(this._repository);

  bool _isLoading = false;
  bool _includeExported = false;
  String? _error;
  String? _lastQuery;
  FifoCheckResult? _result;
  final Set<String> _exportingIds = {};

  bool get isLoading => _isLoading;
  bool get includeExported => _includeExported;
  String? get error => _error;
  FifoCheckResult? get result => _result;
  Set<String> get exportingIds => Set.unmodifiable(_exportingIds);

  Future<void> setIncludeExported(bool value) async {
    if (_includeExported == value) return;
    _includeExported = value;
    notifyListeners();
    final query = _lastQuery;
    if (query != null && query.isNotEmpty) {
      await check(query);
    }
  }

  Future<void> check(String rawQuery) async {
    final query = rawQuery.trim().toUpperCase();
    if (query.isEmpty) return;

    _isLoading = true;
    _error = null;
    _lastQuery = query;
    notifyListeners();

    await AppLogger.instance.info(
      'FIFO',
      'FIFO check started',
      context: {
        'queryLength': query.length,
        'includeExported': _includeExported,
      },
    );

    try {
      final nextResult = await _repository.check(
        text: query,
        includeExported: _includeExported,
      );
      _result = nextResult;
      await AppLogger.instance.info(
        'FIFO',
        'FIFO check succeeded',
        context: {
          'mode': nextResult.mode,
          'srCode': nextResult.srCode,
          'itemCount': nextResult.items.length,
          'status': nextResult.status,
        },
      );
    } on ApiException catch (error) {
      _error = error.message;
      await AppLogger.instance.warn(
        'FIFO',
        'FIFO check failed',
        context: {'message': error.message, 'statusCode': error.statusCode},
      );
    } catch (error, stackTrace) {
      _error = 'Lỗi không xác định: $error';
      await AppLogger.instance.error(
        'FIFO',
        'FIFO check crashed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setExported(FifoInventoryItem item, bool exported) async {
    if (item.id.isEmpty) return;
    _exportingIds.add(item.id);
    _error = null;
    notifyListeners();

    await AppLogger.instance.info(
      'FIFO',
      'FIFO export update started',
      context: {
        'inventoryId': item.id,
        'sku': item.sku,
        'serialNumber': item.serialNumber,
        'exported': exported,
      },
    );

    try {
      await _repository.setExported(inventoryId: item.id, exported: exported);
      await AppLogger.instance.info(
        'FIFO',
        'FIFO export update succeeded',
        context: {'inventoryId': item.id, 'exported': exported},
      );
      final query = _lastQuery;
      if (query != null && query.isNotEmpty) {
        await check(query);
      }
    } on ApiException catch (error) {
      _error = error.message;
      await AppLogger.instance.warn(
        'FIFO',
        'FIFO export update failed',
        context: {'message': error.message, 'statusCode': error.statusCode},
      );
    } catch (error, stackTrace) {
      _error = 'Lỗi không xác định: $error';
      await AppLogger.instance.error(
        'FIFO',
        'FIFO export update crashed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
    } finally {
      _exportingIds.remove(item.id);
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
