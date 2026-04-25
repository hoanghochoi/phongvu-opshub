import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/validators.dart';

class ChatProvider extends ChangeNotifier {
  final ChatRepository _repository;
  final _uuid = const Uuid();

  static const _storageKey = 'fifo_chat_history';
  static const _maxMessages = 20; // 10 checks × 2 messages (user + bot)

  final List<Message> _messages = [];
  bool _isLoading = false;
  bool _historyLoaded = false;
  String? _error;

  ChatProvider(this._repository);

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load chat history from local storage (SharedPreferences)
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
        if (kDebugMode) debugPrint('✅ [ChatProvider] Loaded ${loaded.length} messages from local storage');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [ChatProvider] Error loading local history: $e');
    }

    _historyLoaded = true;
    notifyListeners();
  }

  /// Save current messages to local storage
  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only last N messages
      final toSave = _messages.length > _maxMessages
          ? _messages.sublist(_messages.length - _maxMessages)
          : _messages;
      final jsonStr = jsonEncode(toSave.map((m) => m.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
      if (kDebugMode) debugPrint('💾 [ChatProvider] Saved ${toSave.length} messages to local storage');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [ChatProvider] Error saving local history: $e');
    }
  }

  Future<void> sendMessage(String input, String userEmail) async {
    try {
      // Parse input (SKU và QTY)
      final parsed = Validators.parseMessage(input);
      final sku = parsed['sku']!;
      final qty = parsed['qty']!;

      // Add user message
      final userMessage = Message(
        id: _uuid.v4(),
        content: input.trim(),
        isUser: true,
        timestamp: DateTime.now(),
      );
      _messages.add(userMessage);
      notifyListeners();

      // Set loading state
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Send to backend and get response
      final botMessage = await _repository.sendMessage(sku, qty, userEmail);
      _messages.add(botMessage);
      _error = null;

      // Save to local storage after each successful check
      await _saveToLocal();
    } on FormatException catch (e) {
      _error = e.message;
      // Remove user message if format is invalid
      if (_messages.isNotEmpty && _messages.last.isUser) {
        _messages.removeLast();
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Lỗi không xác định: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearMessages() {
    _messages.clear();
    _historyLoaded = false;
    _saveToLocal(); // Clear local storage too
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
