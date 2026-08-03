import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/widgets/app_buttons.dart';
import '../../../app/widgets/app_cards.dart';
import '../../../app/widgets/app_chips.dart';
import '../../../app/widgets/app_inputs.dart';
import '../../../app/widgets/app_layout.dart';
import '../../../app/widgets/app_state_widgets.dart';
import '../../../app/widgets/app_toast.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../notifications/presentation/providers/app_notifications_provider.dart';
import '../data/support_chat_repository.dart';
import '../domain/support_chat_models.dart';
import 'providers/support_chat_provider.dart';

SupportChatProvider? maybeSupportChatProvider(
  BuildContext context, {
  bool listen = false,
}) {
  try {
    return Provider.of<SupportChatProvider>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

AppNotificationsProvider? _maybeAppNotificationsProvider(
  BuildContext context, {
  bool listen = false,
}) {
  try {
    return Provider.of<AppNotificationsProvider>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

Future<void> showSupportChatSurface(BuildContext context) async {
  final provider = maybeSupportChatProvider(context);
  if (provider == null) return;
  if (!provider.enabled) return;
  if (provider.isSuperAdmin) {
    context.push('/admin/support-chats');
    return;
  }
  await AppLogger.instance.info(
    'SupportChat',
    'Requester support surface opening',
  );
  if (!context.mounted) return;
  final compact =
      MediaQuery.sizeOf(context).width < AppLayoutTokens.compactBreakpoint;
  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.96,
        child: SupportChatPanel(showCloseButton: true),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Align(
        alignment: Alignment.centerRight,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
            child: SizedBox(
              width: 520,
              height: MediaQuery.sizeOf(dialogContext).height - 48,
              child: const Material(
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppLayoutTokens.cardRadius),
                ),
                child: SupportChatPanel(showCloseButton: true),
              ),
            ),
          ),
        ),
      ),
    );
  }
  await AppLogger.instance.info(
    'SupportChat',
    'Requester support surface closed',
  );
}

class SupportChatBubble extends StatelessWidget {
  final VoidCallback onPressed;

  const SupportChatBubble({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<SupportChatProvider, bool>(
      (provider) => provider.enabled,
    );
    final notificationUnread = _maybeAppNotificationsProvider(
      context,
      listen: true,
    )?.supportChatUnreadCount;
    final unread =
        notificationUnread ??
        context.select<SupportChatProvider, int>(
          (provider) => provider.unreadCount,
        );
    if (!enabled) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: unread > 0 ? 'Mở hỗ trợ, có $unread tin chưa đọc' : 'Mở hỗ trợ',
      child: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        child: FloatingActionButton(
          heroTag: null,
          tooltip: 'Hỗ trợ',
          onPressed: onPressed,
          child: const Icon(Icons.support_agent_rounded),
        ),
      ),
    );
  }
}

class SupportChatPanel extends StatefulWidget {
  final bool showCloseButton;
  final VoidCallback? onBackToInbox;

  const SupportChatPanel({
    super.key,
    this.showCloseButton = false,
    this.onBackToInbox,
  });

  @override
  State<SupportChatPanel> createState() => _SupportChatPanelState();
}

class _SupportChatPanelState extends State<SupportChatPanel> {
  final _textController = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  List<SupportChatImageDraft> _images = const [];
  String? _pendingClientMessageId;
  SupportChatProvider? _provider;
  bool _sendInFlight = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<SupportChatProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<SupportChatProvider>().setSurfaceActive(true));
    });
  }

  @override
  void dispose() {
    final provider = _provider;
    if (provider != null) unawaited(provider.setSurfaceActive(false));
    _textController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picked = await _picker.pickMultiImage(limit: 4);
      if (picked.isEmpty) return;
      final drafts = <SupportChatImageDraft>[];
      var totalBytes = 0;
      for (final image in picked.take(4)) {
        final bytes = await image.readAsBytes();
        if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
          if (mounted) {
            _showMessage('Mỗi ảnh phải nhỏ hơn hoặc bằng 5 MiB.');
          }
          return;
        }
        totalBytes += bytes.length;
        if (totalBytes > 20 * 1024 * 1024) {
          if (mounted) {
            _showMessage('Tổng dung lượng ảnh phải nhỏ hơn hoặc bằng 20 MiB.');
          }
          return;
        }
        final contentType = _supportedImageContentType(image, bytes);
        if (contentType == null) {
          if (mounted) {
            _showMessage('Chỉ hỗ trợ ảnh JPEG, PNG, WebP, HEIC hoặc HEIF.');
          }
          return;
        }
        drafts.add(
          SupportChatImageDraft(
            bytes: Uint8List.fromList(bytes),
            contentType: contentType,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _images = drafts;
        _pendingClientMessageId ??= _newClientMessageId();
      });
      await AppLogger.instance.info(
        'SupportChat',
        'Support images selected',
        context: {'imageCount': drafts.length, 'totalBytes': totalBytes},
      );
    } catch (error) {
      await AppLogger.instance.warn(
        'SupportChat',
        'Support image selection failed',
        context: {'errorType': error.runtimeType.toString()},
      );
      if (mounted) _showMessage('Chưa chọn được ảnh. Vui lòng thử lại.');
    }
  }

  Future<void> _send() async {
    final provider = context.read<SupportChatProvider>();
    if (_sendInFlight || provider.isSending) return;
    if (_images.isEmpty && _textController.text.trim().isEmpty) return;
    _sendInFlight = true;
    final clientMessageId = _pendingClientMessageId ??= _newClientMessageId();
    try {
      final success = _images.isNotEmpty
          ? await provider.sendImages(clientMessageId, _images)
          : await provider.sendText(clientMessageId, _textController.text);
      if (!mounted) return;
      if (success) {
        setState(() {
          if (_images.isEmpty) _textController.clear();
          _images = const [];
          _pendingClientMessageId = null;
        });
        _composerFocusNode.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      _sendInFlight = false;
    }
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    // Let the IME finish composing text; intercepting here would drop the
    // composition candidate instead of submitting the completed message.
    if (_textController.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      final value = _textController.value;
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      final start = selection.start.clamp(0, value.text.length);
      final end = selection.end.clamp(start, value.text.length);
      final text = value.text.replaceRange(start, end, '\n');
      _textController.value = value.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: start + 1),
        composing: TextRange.empty,
      );
      _pendingClientMessageId ??= _newClientMessageId();
      setState(() {});
      return KeyEventResult.handled;
    }
    unawaited(_send());
    return KeyEventResult.handled;
  }

  String _newClientMessageId() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$suffix';
  }

  void _showMessage(String message) {
    AppToast.show(context, SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SupportChatProvider>();
    final thread = provider.thread;
    final conversation = thread?.conversation;
    final userId = context.select<AuthProvider, String?>(
      (auth) => auth.user?.id,
    );
    final canReply =
        !provider.isSuperAdmin || conversation?.isAssignedTo(userId) == true;
    return PopScope(
      canPop: widget.onBackToInbox == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBackToInbox?.call();
      },
      child: ColoredBox(
        color: AppColors.canvasOf(context),
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    if (widget.onBackToInbox != null)
                      AppIconAction(
                        onPressed: widget.onBackToInbox,
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Quay lại hộp thư',
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.isSuperAdmin && conversation != null
                                ? conversation.requesterDisplayName ??
                                      'Nhân viên OpsHub'
                                : 'Hỗ trợ OpsHub',
                            style: AppTextStyles.titleEmphasis,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (provider.isSuperAdmin && conversation != null)
                            Text(
                              'Nhân viên cần hỗ trợ',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (conversation != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: AppStatusChip(
                          label: _statusLabel(conversation),
                          color: _statusColor(conversation),
                        ),
                      ),
                    if (widget.showCloseButton)
                      AppIconAction(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icons.close_rounded,
                        tooltip: 'Đóng',
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: AppColors.borderOf(context)),
            if (provider.isSuperAdmin && conversation != null)
              _AdminConversationActions(conversation: conversation),
            Expanded(child: _buildMessages(provider, thread, userId)),
            if (provider.errorMessage != null && thread != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  provider.errorMessage!,
                  style: AppTextStyles.labelM.copyWith(color: AppColors.error),
                ),
              ),
            if (canReply) _buildComposer(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(
    SupportChatProvider provider,
    SupportChatThread? thread,
    String? userId,
  ) {
    if (provider.isLoading && thread == null) {
      return const AppStatePanel.loading(title: 'Đang tải cuộc trò chuyện');
    }
    if (provider.errorMessage != null &&
        thread == null &&
        (!provider.isSuperAdmin || provider.adminConversations.isNotEmpty)) {
      final selectedId = provider.selectedAdminConversationId;
      return AppStatePanel.error(
        title: provider.isSuperAdmin
            ? 'Chưa mở được cuộc trò chuyện'
            : 'Chưa tải được cuộc trò chuyện',
        message: provider.errorMessage,
        actionLabel: 'Thử lại',
        actionIcon: Icons.refresh_rounded,
        onAction: provider.isSuperAdmin && selectedId != null
            ? () => provider.openAdminConversation(selectedId)
            : provider.loadMine,
      );
    }
    if (thread == null || thread.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
          child: AppStatePanel.empty(
            title: provider.isSuperAdmin
                ? 'Chưa chọn cuộc trò chuyện'
                : 'Bắt đầu trò chuyện hỗ trợ',
            message: provider.isSuperAdmin
                ? 'Chọn một nhân viên trong hộp thư để xem nội dung.'
                : 'Gửi nội dung cần hỗ trợ. Sẽ phản hồi khi có người tiếp nhận.',
            icon: Icons.support_agent_rounded,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
      itemCount: thread.messages.length + (thread.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (thread.hasMore && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppSecondaryButton(
              onPressed: provider.isLoading ? null : provider.loadOlderMessages,
              icon: Icons.history_rounded,
              label: 'Tải tin nhắn trước',
              isLoading: provider.isLoading,
            ),
          );
        }
        final message = thread.messages[index - (thread.hasMore ? 1 : 0)];
        return _MessageBubble(message: message, mine: message.sentBy(userId));
      },
    );
  }

  Widget _buildComposer(SupportChatProvider provider) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          border: Border(top: BorderSide(color: AppColors.borderOf(context))),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_images.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_images.length} ảnh đã chọn',
                        style: AppTextStyles.labelM,
                      ),
                    ),
                    AppIconAction(
                      onPressed: provider.isSending
                          ? null
                          : () => setState(() {
                              _images = const [];
                              _pendingClientMessageId = null;
                            }),
                      icon: Icons.clear_rounded,
                      tooltip: 'Bỏ ảnh đã chọn',
                    ),
                  ],
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppIconAction(
                    onPressed: provider.isSending ? null : _pickImages,
                    icon: Icons.add_photo_alternate_outlined,
                    tooltip: 'Đính kèm ảnh',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleComposerKeyEvent,
                      child: AppTextInput(
                        controller: _textController,
                        focusNode: _composerFocusNode,
                        label: 'Tin nhắn',
                        hintText: 'Enter để gửi · Shift+Enter xuống dòng',
                        minLines: 1,
                        maxLines: 4,
                        enabled: !provider.isSending && _images.isEmpty,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onChanged: (_) {
                          _pendingClientMessageId ??= _newClientMessageId();
                          setState(() {});
                        },
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppIconAction(
                    onPressed:
                        provider.isSending ||
                            (_images.isEmpty &&
                                _textController.text.trim().isEmpty)
                        ? null
                        : _send,
                    icon: provider.isSending
                        ? Icons.hourglass_top_rounded
                        : Icons.send_rounded,
                    tooltip: provider.isSending ? 'Đang gửi' : 'Gửi',
                    filled: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SupportChatAdminScreen extends StatefulWidget {
  const SupportChatAdminScreen({super.key});

  @override
  State<SupportChatAdminScreen> createState() => _SupportChatAdminScreenState();
}

class _SupportChatAdminScreenState extends State<SupportChatAdminScreen> {
  static const _buckets = {
    'UNASSIGNED': 'Chưa tiếp nhận',
    'MINE': 'Của tôi',
    'ACTIVE': 'Đang xử lý',
    'RESOLVED': 'Đã xử lý',
  };
  SupportChatProvider? _provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<SupportChatProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SupportChatProvider>();
      unawaited(provider.setSurfaceActive(true));
      unawaited(provider.loadAdminBucket(provider.adminBucket));
    });
  }

  @override
  void dispose() {
    final provider = _provider;
    if (provider != null) unawaited(provider.setSurfaceActive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SupportChatProvider>();
    if (!provider.enabled || !provider.isSuperAdmin) {
      return const Center(
        child: AppStatePanel(
          icon: Icons.lock_outline_rounded,
          tone: AppStateTone.warning,
          title: 'Không có quyền mở hộp thư hỗ trợ',
          message: 'Tải lại tài khoản hoặc quay về trang chủ.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppLayoutTokens.tabletBreakpoint;
        if (!wide && provider.selectedAdminConversationId != null) {
          return SupportChatPanel(
            key: ValueKey(provider.thread?.conversation?.id),
            onBackToInbox: provider.clearSelectedAdminConversation,
          );
        }
        final list = _buildInbox(provider);
        if (!wide) return list;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: min(380, constraints.maxWidth * 0.36),
              child: AppSurfaceCard(padding: EdgeInsets.zero, child: list),
            ),
            const SizedBox(width: AppLayoutTokens.cardGap),
            Expanded(
              child: AppSurfaceCard(
                padding: EdgeInsets.zero,
                child: const SupportChatPanel(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInbox(SupportChatProvider provider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Hộp thư hỗ trợ', style: AppTextStyles.headingS),
              ),
              Text(
                '${provider.adminConversations.length} hội thoại',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textMutedOf(context),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _buckets.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: provider.adminBucket == entry.key,
                  onSelected: provider.isLoading
                      ? null
                      : (_) {
                          provider.clearSelectedAdminConversation();
                          unawaited(provider.loadAdminBucket(entry.key));
                        },
                ),
            ],
          ),
        ),
        Expanded(
          child: provider.isLoading && provider.adminConversations.isEmpty
              ? const AppStatePanel.loading(title: 'Đang tải hộp thư hỗ trợ')
              : provider.errorMessage != null &&
                    provider.adminConversations.isEmpty
              ? AppStatePanel.error(
                  title: 'Chưa tải được hộp thư hỗ trợ',
                  message: provider.errorMessage,
                  actionLabel: 'Thử lại',
                  actionIcon: Icons.refresh_rounded,
                  onAction: () =>
                      provider.loadAdminBucket(provider.adminBucket),
                )
              : provider.adminConversations.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppLayoutTokens.cardPadding),
                    child: AppStatePanel.empty(
                      title: 'Chưa có cuộc trò chuyện',
                      message: 'Các yêu cầu phù hợp sẽ xuất hiện tại đây.',
                      icon: Icons.mark_chat_unread_outlined,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount:
                      provider.adminConversations.length +
                      (provider.hasMoreAdminConversations ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == provider.adminConversations.length) {
                      return AppSecondaryButton(
                        onPressed: provider.isLoading
                            ? null
                            : provider.loadMoreAdminConversations,
                        icon: Icons.expand_more_rounded,
                        label: 'Tải thêm cuộc trò chuyện',
                        isLoading: provider.isLoading,
                      );
                    }
                    final item = provider.adminConversations[index];
                    final selected =
                        provider.selectedAdminConversationId == item.id;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label:
                          'Cuộc trò chuyện với ${item.requesterDisplayName ?? 'Nhân viên OpsHub'}',
                      child: AppSurfaceCard(
                        onTap: () => provider.openAdminConversation(item.id),
                        backgroundColor: selected
                            ? AppColors.primarySurfaceOf(context)
                            : null,
                        child: Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.person_outline_rounded),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.requesterDisplayName ??
                                        'Nhân viên OpsHub',
                                    style: AppTextStyles.labelL,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _statusLabel(item),
                                    style: AppTextStyles.bodyS.copyWith(
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (item.unreadCount > 0)
                              Badge.count(count: item.unreadCount),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AdminConversationActions extends StatelessWidget {
  final SupportConversation conversation;

  const _AdminConversationActions({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SupportChatProvider>();
    final userId = context.select<AuthProvider, String?>(
      (auth) => auth.user?.id,
    );
    final assignedToMe = conversation.isAssignedTo(userId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (conversation.assigneeId == null)
            AppLinkButton(
              onPressed: provider.isSending
                  ? null
                  : () => provider.mutateAdmin('claim'),
              icon: Icons.person_add_alt_1_rounded,
              label: 'Tiếp nhận',
            ),
          if (assignedToMe)
            AppLinkButton(
              onPressed: provider.isSending
                  ? null
                  : () => provider.mutateAdmin('release'),
              icon: Icons.person_remove_alt_1_outlined,
              label: 'Bàn giao',
            ),
          if (conversation.assigneeId != null && !assignedToMe)
            AppLinkButton(
              onPressed: provider.isSending
                  ? null
                  : () => _confirmTakeover(context, provider),
              icon: Icons.swap_horiz_rounded,
              label: 'Nhận thay',
            ),
          if (assignedToMe && !conversation.isResolved)
            AppLinkButton(
              onPressed: provider.isSending
                  ? null
                  : () => provider.mutateAdmin(
                      'resolve',
                      body: {
                        'expectedLastMessageSequence':
                            conversation.lastMessageSequence,
                      },
                    ),
              icon: Icons.task_alt_rounded,
              label: 'Đánh dấu đã xử lý',
            ),
        ],
      ),
    );
  }

  Future<void> _confirmTakeover(
    BuildContext context,
    SupportChatProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nhận xử lý cuộc trò chuyện?'),
        content: const Text(
          'Cuộc trò chuyện đang có người tiếp nhận. Chỉ nhận thay khi cần tiếp tục hỗ trợ.',
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppDialogConfirmButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: Icons.swap_horiz_rounded,
            label: 'Nhận thay',
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.mutateAdmin('takeover');
  }
}

class _MessageBubble extends StatelessWidget {
  final SupportChatMessage message;
  final bool mine;

  const _MessageBubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: mine
          ? 'Tin nhắn của bạn'
          : message.senderKind == 'SUPER_ADMIN'
          ? 'Tin nhắn từ bộ phận hỗ trợ'
          : 'Tin nhắn từ nhân viên cần hỗ trợ',
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppSurfaceCard(
            margin: const EdgeInsets.only(bottom: 8),
            backgroundColor: mine
                ? AppColors.primarySurfaceOf(context)
                : AppColors.cardOf(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.text?.isNotEmpty == true)
                  Text(message.text!, style: AppTextStyles.bodyM),
                if (message.attachments.isNotEmpty)
                  for (final attachment in message.attachments) ...[
                    if (message.text?.isNotEmpty == true)
                      const SizedBox(height: 8),
                    _SupportPrivateImage(attachment: attachment),
                  ],
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.createdAt),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportPrivateImage extends StatefulWidget {
  final SupportChatAttachment attachment;

  const _SupportPrivateImage({required this.attachment});

  @override
  State<_SupportPrivateImage> createState() => _SupportPrivateImageState();
}

class _SupportPrivateImageState extends State<_SupportPrivateImage> {
  late final Future<Uint8List> _bytes = context
      .read<SupportChatProvider>()
      .loadPrivateImage(widget.attachment.url);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const AppStatePanel.error(
            title: 'Chưa tải được ảnh',
            message: 'Vui lòng thử mở lại cuộc trò chuyện.',
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const SizedBox(
            height: 120,
            child: AppStatePanel.loading(title: 'Đang tải ảnh', compact: true),
          );
        }
        return ClipRRect(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppLayoutTokens.cardRadius),
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: false,
            semanticLabel: 'Ảnh trong cuộc trò chuyện hỗ trợ',
          ),
        );
      },
    );
  }
}

String _statusLabel(SupportConversation conversation) {
  if (conversation.isResolved) return 'Đã xử lý';
  if (conversation.assigneeId == null) return 'Đang chờ tiếp nhận';
  return 'Đang được hỗ trợ';
}

Color _statusColor(SupportConversation conversation) {
  if (conversation.isResolved) return AppColors.success;
  if (conversation.assigneeId == null) return AppColors.warning;
  return AppColors.info;
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)} ${two(local.day)}/${two(local.month)}/${local.year}';
}

String? _supportedImageContentType(XFile image, Uint8List bytes) {
  final declared = image.mimeType?.trim().toLowerCase();
  const supported = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  };
  if (supported.contains(declared)) return declared;
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (brand.startsWith('hei') || brand == 'mif1' || brand == 'msf1') {
      return brand == 'heif' || brand == 'mif1' || brand == 'msf1'
          ? 'image/heif'
          : 'image/heic';
    }
  }
  return null;
}
