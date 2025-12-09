import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/validators.dart';

class ChatProvider extends ChangeNotifier {
  final ChatRepository _repository;
  final _uuid = const Uuid();

  final List<Message> _messages = [];
  bool _isLoading = false;
  String? _error;

  ChatProvider(this._repository);

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

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

      // Send to n8n and get response
      final botMessage = await _repository.sendMessage(sku, qty, userEmail);
      _messages.add(botMessage);
      _error = null;
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
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
