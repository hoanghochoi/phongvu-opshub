import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/support_chat_repository.dart';
import '../../domain/support_chat_models.dart';

class SupportChatProvider extends ChangeNotifier {
  final SupportChatDataSource _repository;
  final RealtimeClient _realtimeClient;
  late final StreamSubscription<RealtimeEnvelope> _eventSubscription;
  late final StreamSubscription<RealtimeSyncReason> _syncSubscription;

  SupportChatProvider(this._repository, {RealtimeClient? realtimeClient})
    : _realtimeClient = realtimeClient ?? RealtimeConnectionManager.instance {
    _eventSubscription = _realtimeClient.events.listen(_handleRealtimeEvent);
    _syncSubscription = _realtimeClient.syncRequests.listen(_handleSyncRequest);
  }

  User? _user;
  bool _enabled = false;
  bool _surfaceActive = false;
  bool _loading = false;
  bool _sending = false;
  bool _dirty = false;
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _disposed = false;
  int _generation = 0;
  String? _errorMessage;
  String _adminBucket = 'UNASSIGNED';
  String? _adminNextCursor;
  String? _selectedAdminConversationId;
  SupportChatThread? _thread;
  List<SupportConversation> _adminConversations = const [];

  bool get enabled => _enabled;
  bool get isSuperAdmin => _user?.isSuperAdmin == true;
  bool get isLoading => _loading;
  bool get isSending => _sending;
  String? get errorMessage => _errorMessage;
  String get adminBucket => _adminBucket;
  bool get hasMoreAdminConversations => _adminNextCursor != null;
  String? get selectedAdminConversationId => _selectedAdminConversationId;
  SupportChatThread? get thread => _thread;
  List<SupportConversation> get adminConversations =>
      List.unmodifiable(_adminConversations);
  int get unreadCount => isSuperAdmin
      ? _adminConversations.fold(0, (total, item) => total + item.unreadCount)
      : (_thread?.conversation?.unreadCount ?? 0);

  Future<void> syncAuth(User? user, {required bool enabled}) async {
    if (_disposed) return;
    final nextIdentity = '${user?.id}:${user?.role}:${user?.status}:$enabled';
    final previousIdentity =
        '${_user?.id}:${_user?.role}:${_user?.status}:$_enabled';
    _user = user;
    _enabled = enabled && user != null;
    if (nextIdentity == previousIdentity) return;
    _generation += 1;
    _loading = false;
    _sending = false;
    _dirty = _enabled;
    _errorMessage = null;
    _thread = null;
    _selectedAdminConversationId = null;
    _adminConversations = const [];
    _adminNextCursor = null;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    notifyListeners();
    await AppLogger.instance.info(
      'SupportChat',
      'Support chat authorization synchronized',
      context: {
        'enabled': _enabled,
        'isSuperAdmin': isSuperAdmin,
        'hasUser': user != null,
      },
    );
  }

  Future<void> setSurfaceActive(bool active) async {
    if (_disposed || _surfaceActive == active) return;
    _surfaceActive = active;
    if (active && _enabled && (_dirty || _thread == null)) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    if (_disposed || !_enabled) return;
    if (_refreshing || _loading) {
      _refreshQueued = true;
      return;
    }
    final generation = _generation;
    _refreshing = true;
    try {
      do {
        _refreshQueued = false;
        if (!_isCurrent(generation) || !_enabled) return;
        if (isSuperAdmin) {
          final selectedConversationId = _selectedAdminConversationId;
          await loadAdminBucket(_adminBucket);
          if (selectedConversationId != null && _isCurrent(generation)) {
            await openAdminConversation(selectedConversationId);
          }
        } else {
          await loadMine();
        }
      } while (_refreshQueued && _isCurrent(generation) && _enabled);
    } finally {
      _refreshing = false;
      if (!_disposed && _refreshQueued && _surfaceActive && _enabled) {
        unawaited(refresh());
      }
    }
  }

  Future<void> loadMine({String? beforeSequence}) async {
    if (_disposed || !_enabled || isSuperAdmin || _loading) return;
    final generation = _generation;
    final startedAt = DateTime.now();
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    await AppLogger.instance.info(
      'SupportChat',
      'Requester conversation load started',
      context: {'hasCursor': beforeSequence != null},
    );
    try {
      final result = await _repository.getMine(beforeSequence: beforeSequence);
      if (!_isCurrent(generation)) return;
      _thread = beforeSequence == null
          ? result
          : _prependOlder(_thread, result);
      _dirty = false;
      await _markCurrentThreadRead();
      await AppLogger.instance.info(
        'SupportChat',
        'Requester conversation load succeeded',
        context: {
          'messageCount': _thread?.messages.length ?? 0,
          'hasConversation': _thread?.conversation != null,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _errorMessage = 'Chưa tải được cuộc trò chuyện. Vui lòng thử lại.';
      await _logFailure('Requester conversation load failed', error, startedAt);
    } finally {
      _finishLoading(generation);
    }
  }

  Future<void> loadAdminBucket(
    String bucket, {
    String? query,
    String? cursor,
    bool append = false,
  }) async {
    if (_disposed || !_enabled || !isSuperAdmin || _loading) return;
    final generation = _generation;
    final startedAt = DateTime.now();
    _adminBucket = bucket;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.listAdmin(
        bucket: bucket,
        query: query,
        cursor: cursor,
      );
      if (!_isCurrent(generation)) return;
      _adminConversations = append
          ? _mergeAdminConversations(_adminConversations, page.items)
          : page.items;
      _adminNextCursor = page.nextCursor;
      _dirty = false;
      await AppLogger.instance.info(
        'SupportChat',
        'Admin inbox load succeeded',
        context: {
          'bucket': bucket,
          'conversationCount': page.items.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _errorMessage = 'Chưa tải được hộp thư hỗ trợ. Vui lòng thử lại.';
      await _logFailure('Admin inbox load failed', error, startedAt, {
        'bucket': bucket,
      });
    } finally {
      _finishLoading(generation);
    }
  }

  Future<void> loadMoreAdminConversations() async {
    final cursor = _adminNextCursor;
    if (cursor == null) return;
    await loadAdminBucket(_adminBucket, cursor: cursor, append: true);
  }

  Future<void> openAdminConversation(
    String conversationId, {
    String? beforeSequence,
  }) async {
    if (!_enabled || !isSuperAdmin || _loading) return;
    final generation = _generation;
    _selectedAdminConversationId = conversationId;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _repository.getAdminConversation(
        conversationId,
        beforeSequence: beforeSequence,
      );
      if (!_isCurrent(generation)) return;
      _thread = beforeSequence == null
          ? result
          : _prependOlder(_thread, result);
      _selectedAdminConversationId = conversationId;
      await _markCurrentThreadRead();
    } catch (error) {
      if (_isCurrent(generation)) {
        _errorMessage = 'Chưa mở được cuộc trò chuyện. Vui lòng thử lại.';
        await _logFailure(
          'Admin conversation load failed',
          error,
          DateTime.now(),
        );
      }
    } finally {
      _finishLoading(generation);
    }
  }

  Future<void> loadOlderMessages() async {
    final beforeSequence = _thread?.nextBeforeSequence;
    if (beforeSequence == null || beforeSequence.isEmpty) return;
    if (isSuperAdmin) {
      final conversationId = _thread?.conversation?.id;
      if (conversationId != null) {
        await openAdminConversation(
          conversationId,
          beforeSequence: beforeSequence,
        );
      }
      return;
    }
    await loadMine(beforeSequence: beforeSequence);
  }

  Future<bool> sendText(String clientMessageId, String text) async {
    final normalized = text.trim();
    if (!_enabled || _sending || normalized.isEmpty) return false;
    final generation = _generation;
    final userId = _user?.id;
    final startedAt = DateTime.now();
    _sending = true;
    _errorMessage = null;
    notifyListeners();
    await AppLogger.instance.info(
      'SupportChat',
      'Text message send started',
      context: {'characterCount': normalized.runes.length},
    );
    try {
      final conversationId = _thread?.conversation?.id;
      final result = isSuperAdmin
          ? await _repository.sendAdminText(
              conversationId: conversationId!,
              clientMessageId: clientMessageId,
              text: normalized,
            )
          : await _repository.sendMyText(
              clientMessageId: clientMessageId,
              text: normalized,
            );
      if (!_isCurrentIdentity(generation, userId)) return false;
      _thread = result;
      _dirty = false;
      await _markCurrentThreadRead();
      if (!_isCurrentIdentity(generation, userId)) return false;
      await AppLogger.instance.info(
        'SupportChat',
        'Text message send succeeded',
        context: {
          'messageCount': result.messages.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return true;
    } catch (error) {
      if (!_isCurrentIdentity(generation, userId)) return false;
      _errorMessage =
          'Chưa gửi được tin nhắn. Nội dung vẫn được giữ để thử lại.';
      await _logFailure('Text message send failed', error, startedAt);
      return false;
    } finally {
      if (_isCurrentIdentity(generation, userId)) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  Future<bool> sendImages(
    String clientMessageId,
    List<SupportChatImageDraft> images,
  ) async {
    if (!_enabled || _sending || images.isEmpty) return false;
    final generation = _generation;
    final userId = _user?.id;
    final startedAt = DateTime.now();
    _sending = true;
    _errorMessage = null;
    notifyListeners();
    await AppLogger.instance.info(
      'SupportChat',
      'Image message send started',
      context: {
        'imageCount': images.length,
        'totalBytes': images.fold<int>(
          0,
          (sum, item) => sum + item.bytes.length,
        ),
      },
    );
    try {
      final conversationId = _thread?.conversation?.id;
      final result = isSuperAdmin
          ? await _repository.sendAdminImages(
              conversationId: conversationId!,
              clientMessageId: clientMessageId,
              images: images,
            )
          : await _repository.sendMyImages(
              clientMessageId: clientMessageId,
              images: images,
            );
      if (!_isCurrentIdentity(generation, userId)) return false;
      _thread = result;
      _dirty = false;
      await _markCurrentThreadRead();
      if (!_isCurrentIdentity(generation, userId)) return false;
      await AppLogger.instance.info(
        'SupportChat',
        'Image message send succeeded',
        context: {
          'imageCount': images.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return true;
    } catch (error) {
      if (!_isCurrentIdentity(generation, userId)) return false;
      _errorMessage = 'Chưa gửi được ảnh. Ảnh vẫn được giữ để thử lại.';
      await _logFailure('Image message send failed', error, startedAt);
      return false;
    } finally {
      if (_isCurrentIdentity(generation, userId)) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  Future<bool> mutateAdmin(
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    final conversationId = _thread?.conversation?.id;
    if (!_enabled || !isSuperAdmin || conversationId == null || _sending) {
      return false;
    }
    final generation = _generation;
    final userId = _user?.id;
    _sending = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _repository.mutateAdmin(
        conversationId,
        action,
        body: body,
      );
      if (!_isCurrentIdentity(generation, userId)) return false;
      _thread = result;
      _dirty = true;
      await loadAdminBucket(_adminBucket);
      if (!_isCurrentIdentity(generation, userId)) return false;
      return true;
    } catch (error) {
      if (!_isCurrentIdentity(generation, userId)) return false;
      _errorMessage = 'Chưa cập nhật được cuộc trò chuyện. Vui lòng tải lại.';
      await _logFailure(
        'Admin conversation mutation failed',
        error,
        DateTime.now(),
        {'action': action},
      );
      return false;
    } finally {
      if (_isCurrentIdentity(generation, userId)) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  void clearSelectedAdminConversation() {
    if (!isSuperAdmin) return;
    _selectedAdminConversationId = null;
    _thread = null;
    notifyListeners();
  }

  Future<Uint8List> loadPrivateImage(String url) =>
      _repository.loadPrivateImage(url);

  Future<void> _markCurrentThreadRead() async {
    final conversation = _thread?.conversation;
    if (conversation == null || conversation.lastMessageSequence == '0') return;
    try {
      if (isSuperAdmin) {
        await _repository.markAdminRead(
          conversation.id,
          conversation.lastMessageSequence,
        );
      } else {
        await _repository.markMineRead(conversation.lastMessageSequence);
      }
    } catch (error) {
      await AppLogger.instance.warn(
        'SupportChat',
        'Read receipt update failed',
        context: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  SupportChatThread _prependOlder(
    SupportChatThread? current,
    SupportChatThread older,
  ) {
    if (current == null) return older;
    final byId = <String, SupportChatMessage>{
      for (final item in older.messages) item.id: item,
      for (final item in current.messages) item.id: item,
    };
    final messages = byId.values.toList()
      ..sort(
        (a, b) => BigInt.parse(a.sequence).compareTo(BigInt.parse(b.sequence)),
      );
    return SupportChatThread(
      conversation: older.conversation ?? current.conversation,
      messages: messages,
      nextBeforeSequence: older.nextBeforeSequence,
      hasMore: older.hasMore,
    );
  }

  List<SupportConversation> _mergeAdminConversations(
    List<SupportConversation> current,
    List<SupportConversation> next,
  ) {
    final byId = <String, SupportConversation>{
      for (final item in current) item.id: item,
      for (final item in next) item.id: item,
    };
    return byId.values.toList(growable: false);
  }

  void _handleRealtimeEvent(RealtimeEnvelope envelope) {
    if (!_enabled ||
        envelope.kind != 'SUPPORT_CHAT_INVALIDATED' ||
        envelope.topic != 'support.chat') {
      return;
    }
    _dirty = true;
    unawaited(
      AppLogger.instance.info(
        'SupportChat',
        'Support chat realtime invalidation received',
        context: {'eventId': envelope.id, 'surfaceActive': _surfaceActive},
      ),
    );
    if (_surfaceActive) unawaited(refresh());
  }

  void _handleSyncRequest(RealtimeSyncReason reason) {
    if (!_enabled) return;
    _dirty = true;
    if (_surfaceActive) unawaited(refresh());
  }

  Future<void> _logFailure(
    String message,
    Object error,
    DateTime startedAt, [
    Map<String, Object?> context = const {},
  ]) {
    return AppLogger.instance.warn(
      'SupportChat',
      message,
      context: {
        ...context,
        'errorType': error.runtimeType.toString(),
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isCurrentIdentity(int generation, String? userId) =>
      _isCurrent(generation) && userId != null && _user?.id == userId;

  void _finishLoading(int generation) {
    if (!_isCurrent(generation)) return;
    _loading = false;
    notifyListeners();
    if (_refreshQueued && _surfaceActive && !_refreshing) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription.cancel();
    _syncSubscription.cancel();
    super.dispose();
  }
}
