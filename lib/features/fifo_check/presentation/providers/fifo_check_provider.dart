import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/storage/app_storage_keys.dart';
import '../../../../core/utils/validators.dart';
import '../../data/repositories/fifo_check_repository.dart';
import '../../domain/entities/fifo_check_entry.dart';

class FifoCheckProvider extends ChangeNotifier {
  final FifoCheckRepository _repository;
  final _uuid = const Uuid();

  static const _storageKey = 'fifo_check_history';
  static const _maxEntries = 20;
  static String get _historyStorageKey => AppStorageKeys.shared(_storageKey);

  final List<FifoCheckEntry> _entries = [];
  bool _isLoading = false;
  bool _historyLoaded = false;
  String? _error;

  FifoCheckProvider(this._repository);

  List<FifoCheckEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadHistory() async {
    if (_historyLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_historyStorageKey);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        final loaded = jsonList
            .map((j) => FifoCheckEntry.fromJson(j as Map<String, dynamic>))
            .toList();
        _entries.addAll(loaded);
        await AppLogger.instance.info(
          'FIFO',
          'FIFO check history loaded',
          context: {'entryCount': loaded.length},
        );
      }
    } catch (error) {
      await AppLogger.instance.error(
        'FIFO',
        'FIFO check history load failed',
        error: error,
      );
    }

    _historyLoaded = true;
    notifyListeners();
  }

  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _entries.length > _maxEntries
          ? _entries.sublist(_entries.length - _maxEntries)
          : _entries;
      final jsonStr = jsonEncode(toSave.map((m) => m.toJson()).toList());
      await prefs.setString(_historyStorageKey, jsonStr);
      await AppLogger.instance.info(
        'FIFO',
        'FIFO check history saved',
        context: {'entryCount': toSave.length},
      );
    } catch (error) {
      await AppLogger.instance.error(
        'FIFO',
        'FIFO check history save failed',
        error: error,
      );
    }
  }

  Future<void> runCheck(String input, String userEmail) async {
    try {
      final parsed = Validators.parseFifoCheckInput(input);
      final sku = parsed['sku']!;
      final qty = parsed['qty']!;
      await AppLogger.instance.info(
        'FIFO',
        'FIFO check started',
        context: {'userEmail': userEmail, 'sku': sku, 'qty': qty},
      );

      final inputEntry = FifoCheckEntry(
        id: _uuid.v4(),
        content: input.trim(),
        isUserInput: true,
        timestamp: DateTime.now(),
      );
      _entries.add(inputEntry);
      notifyListeners();

      _isLoading = true;
      _error = null;
      notifyListeners();

      final resultEntry = await _repository.sendCheck(sku, qty, userEmail);
      _entries.add(resultEntry);
      _error = null;
      await AppLogger.instance.info(
        'FIFO',
        'FIFO check succeeded',
        context: {
          'userEmail': userEmail,
          'sku': sku,
          'qty': qty,
          'skuItemCount': resultEntry.skuItems?.length ?? 0,
          'suggestedItemCount': resultEntry.suggestedItems?.length ?? 0,
        },
      );

      await _saveToLocal();
    } on FormatException catch (error) {
      _error = error.message;
      await AppLogger.instance.warn(
        'FIFO',
        'FIFO check input rejected',
        context: {'inputLength': input.length, 'message': error.message},
      );
      if (_entries.isNotEmpty && _entries.last.isUserInput) {
        _entries.removeLast();
      }
    } on ApiException catch (error) {
      _error = error.message;
      await AppLogger.instance.warn(
        'FIFO',
        'FIFO check failed',
        context: {'userEmail': userEmail, 'message': error.message},
      );
    } catch (error, stackTrace) {
      _error = 'Chưa kiểm tra được FIFO. Vui lòng thử lại.';
      await AppLogger.instance.error(
        'FIFO',
        'FIFO check crashed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'userEmail': userEmail},
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearEntries() {
    unawaited(
      AppLogger.instance.info(
        'FIFO',
        'FIFO check history cleared',
        context: {'entryCount': _entries.length},
      ),
    );
    _entries.clear();
    _historyLoaded = false;
    unawaited(_saveToLocal());
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
