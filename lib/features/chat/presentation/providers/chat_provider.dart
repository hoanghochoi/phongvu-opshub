import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/validators.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/entities/message.dart';

class ChatProvider extends ChangeNotifier {
  final ChatRepository _repository;
  final _uuid = const Uuid();

  static const _storageKey = 'fifo_chat_history';
  static const _maxMessages = 20;

  final List<Message> _messages = [];
  bool _isLoading = false;
  bool _historyLoaded = false;
  String? _error;

  ChatProvider(this._repository);

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadHistory() async {
    if (_historyLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        final loaded = jsonList
            .map((j) => Message.fromJson(j as Map<String, dynamic>))
            .toList();
        _messages.addAll(loaded);
        await AppLogger.instance.info(
          'FIFO',
          'Chat history loaded',
          context: {'messageCount': loaded.length},
        );
      }
    } catch (error) {
      await AppLogger.instance.error(
        'FIFO',
        'Chat history load failed',
        error: error,
      );
    }

    _historyLoaded = true;
    notifyListeners();
  }

  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _messages.length > _maxMessages
          ? _messages.sublist(_messages.length - _maxMessages)
          : _messages;
      final jsonStr = jsonEncode(toSave.map((m) => m.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
      await AppLogger.instance.info(
        'FIFO',
        'Chat history saved',
        context: {'messageCount': toSave.length},
      );
    } catch (error) {
      await AppLogger.instance.error(
        'FIFO',
        'Chat history save failed',
        error: error,
      );
    }
  }

  Future<void> sendMessage(String input, String userEmail) async {
    try {
      final parsed = Validators.parseMessage(input);
      final sku = parsed['sku']!;
      final qty = parsed['qty']!;
      await AppLogger.instance.info(
        'FIFO',
        'FIFO check started',
        context: {'userEmail': userEmail, 'sku': sku, 'qty': qty},
      );

      final userMessage = Message(
        id: _uuid.v4(),
        content: input.trim(),
        isUser: true,
        timestamp: DateTime.now(),
      );
      _messages.add(userMessage);
      notifyListeners();

      _isLoading = true;
      _error = null;
      notifyListeners();

      final botMessage = await _repository.sendMessage(sku, qty, userEmail);
      _messages.add(botMessage);
      _error = null;
      await AppLogger.instance.info(
        'FIFO',
        'FIFO check succeeded',
        context: {
          'userEmail': userEmail,
          'sku': sku,
          'qty': qty,
          'skuItemCount': botMessage.skuItems?.length ?? 0,
          'suggestedItemCount': botMessage.suggestedItems?.length ?? 0,
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
      if (_messages.isNotEmpty && _messages.last.isUser) {
        _messages.removeLast();
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

  void clearMessages() {
    unawaited(
      AppLogger.instance.info(
        'FIFO',
        'Chat history cleared',
        context: {'messageCount': _messages.length},
      ),
    );
    _messages.clear();
    _historyLoaded = false;
    unawaited(_saveToLocal());
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
