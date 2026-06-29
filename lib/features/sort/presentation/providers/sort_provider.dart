import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../data/repositories/sort_repository.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../fifo_check/domain/entities/sku_item.dart';
import '../../../fifo_check/domain/entities/sku_group.dart';

class SortProvider extends ChangeNotifier {
  final SortRepository _repository;
  final _uuid = const Uuid();

  bool _isLoading = false;
  String? _error;
  String? _response;
  List<SKUItem>? _skuItems;
  List<SKUGroup>? _skuGroups;
  String? _currentUser;

  SortProvider(this._repository);

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get response => _response;
  List<SKUItem>? get skuItems => _skuItems;
  List<SKUGroup>? get skuGroups => _skuGroups;

  List<SKUItem> _parseSKUItems(String text) {
    final skuItems = <SKUItem>[];
    final blocks = text.split('\n\n');

    for (var block in blocks) {
      if (block.trim().isEmpty) continue;
      if (!block.contains('SKU:')) continue;

      final lines = block.split('\n');
      String sku = '', name = '', serial = '', bin = '', zone = '', date = '';

      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('SKU:')) {
          sku = line.replaceFirst('SKU:', '').trim();
        } else if (line.startsWith('Tên:')) {
          name = line.replaceFirst('Tên:', '').trim();
        } else if (line.startsWith('Serial:')) {
          serial = line.replaceFirst('Serial:', '').trim();
        } else if (line.startsWith('Mã BIN:')) {
          bin = line.replaceFirst('Mã BIN:', '').trim();
        } else if (line.startsWith('Zone:')) {
          zone = line.replaceFirst('Zone:', '').trim();
        } else if (line.startsWith('Ngày nhập:')) {
          date = line.replaceFirst('Ngày nhập:', '').trim();
        }
      }

      if (sku.isNotEmpty && serial.isNotEmpty) {
        skuItems.add(
          SKUItem(
            id: _uuid.v4(),
            sku: sku,
            name: name,
            serial: serial,
            bin: bin,
            zone: zone,
            date: date,
          ),
        );
      }
    }

    return skuItems;
  }

  List<SKUGroup> _groupSKUItems(List<SKUItem> items) {
    final Map<String, List<SKUItem>> grouped = {};

    for (var item in items) {
      if (!grouped.containsKey(item.sku)) {
        grouped[item.sku] = [];
      }
      grouped[item.sku]!.add(item);
    }

    return grouped.entries.map((entry) {
      final firstItem = entry.value.first;
      return SKUGroup(sku: entry.key, name: firstItem.name, items: entry.value);
    }).toList();
  }

  Future<void> _sendCompletionReport() async {
    if (_skuGroups == null || _currentUser == null) return;

    final sortedSKUs = _skuGroups!
        .where((group) => group.isFullyChecked)
        .map(
          (group) => {
            'sku': group.sku,
            'name': group.name,
            'bins': group.items.map((item) => item.bin).toSet().toList(),
            'count': group.items.length,
          },
        )
        .toList();

    if (sortedSKUs.isEmpty) return;

    try {
      await _repository.sendCompletionReport(
        user: _currentUser!,
        sortedSKUs: sortedSKUs,
      );
      await AppLogger.instance.info(
        'Sort',
        'Sort completion report sent',
        context: {'user': _currentUser, 'skuCount': sortedSKUs.length},
      );
      debugPrint('Sort report sent successfully');
    } catch (e) {
      await AppLogger.instance.error(
        'Sort',
        'Sort completion report failed',
        error: e,
        upload: true,
        context: {'user': _currentUser, 'skuCount': sortedSKUs.length},
      );
      debugPrint('Error sending sort report: $e');
    }
  }

  Future<void> sendSortRequest(String text, String user) async {
    try {
      await AppLogger.instance.info(
        'Sort',
        'Sort request started',
        context: {'user': user, 'queryLength': text.length},
      );
      // Set loading state
      _isLoading = true;
      _error = null;
      _response = null;
      _skuItems = null;
      _skuGroups = null;
      _currentUser = user;
      notifyListeners();

      // Send to backend and get response
      final result = await _repository.sendSortRequest(text, user);
      _response = result;
      _skuItems = _parseSKUItems(result);
      _skuGroups = _groupSKUItems(_skuItems!);
      _error = null;
      await AppLogger.instance.info(
        'Sort',
        'Sort request succeeded',
        context: {
          'user': user,
          'itemCount': _skuItems?.length ?? 0,
          'groupCount': _skuGroups?.length ?? 0,
        },
      );
    } on ApiException catch (e) {
      _error = e.message;
      await AppLogger.instance.warn(
        'Sort',
        'Sort request failed',
        context: {'user': user, 'message': e.message},
      );
      _response = null;
      _skuItems = null;
      _skuGroups = null;
    } catch (e) {
      _error = 'Chưa xử lý được yêu cầu sắp xếp. Vui lòng thử lại.';
      _response = null;
      _skuItems = null;
      _skuGroups = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearResponse() {
    _response = null;
    _skuItems = null;
    _skuGroups = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void updateSKUItem(SKUItem item) {
    if (_skuGroups == null) return;

    // Find and update the item in the groups
    for (var group in _skuGroups!) {
      final index = group.items.indexWhere((i) => i.id == item.id);
      if (index != -1) {
        group.items[index] = item;
        notifyListeners();

        // Check if all groups are fully checked
        if (_skuGroups!.every((g) => g.isFullyChecked)) {
          _sendCompletionReport();
        }
        break;
      }
    }
  }
}
