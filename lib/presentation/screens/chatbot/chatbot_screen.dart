import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_sizes.dart';
import '../../../data/datasources/chatbot_remote_data_source.dart';
import '../../../data/datasources/message_remote_data_source.dart';
import '../../../data/models/message_models.dart';
import '../../widgets/tts_icon_button.dart';
import '../../widgets/voice_input_icon_button.dart';

enum _ChatMenuAction {
  loadHistory,
  reloadConversation,
  clearConversation,
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const int _maxSavedConversations = 20;

  final http.Client _client = http.Client();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final ChatbotRemoteDataSource _chatbotDataSource;
  late final MessageRemoteDataSource _messageDataSource;

  List<_UiChatMessage> _messages = const [];
  bool _isSending = false;
  bool _isLoadingHistory = false;
  String? _conversationId;
  List<_SavedConversation> _savedConversations = const [];
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _chatbotDataSource = ChatbotRemoteDataSource(client: _client);
    _messageDataSource = MessageRemoteDataSource(client: _client);
    _restoreSavedConversations();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.home),
        ),
        titleSpacing: AppSizes.xs,
        title: _ChatHeader(hasConversation: _conversationId != null),
        actions: [
          IconButton(
            tooltip: 'Xóa hội thoại',
            onPressed: _messages.isEmpty ? null : _clearConversation,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
          PopupMenuButton<_ChatMenuAction>(
            tooltip: 'Tùy chọn',
            onSelected: _handleMenuAction,
            itemBuilder: (context) {
              return [
                const PopupMenuItem(
                  value: _ChatMenuAction.loadHistory,
                  child: Text('Lịch sử hội thoại'),
                ),
                if (_conversationId != null)
                  const PopupMenuItem(
                    value: _ChatMenuAction.reloadConversation,
                    child: Text('Tải lại hội thoại hiện tại'),
                  ),
                if (_messages.isNotEmpty)
                  const PopupMenuItem(
                    value: _ChatMenuAction.clearConversation,
                    child: Text('Làm mới màn hình chat'),
                  ),
              ];
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md,
                AppSizes.sm,
                AppSizes.md,
                AppSizes.sm,
              ),
              child: _ConversationInfoCard(
                activeConversationTitle: _activeConversationTitle,
                savedConversationsCount: _savedConversations.length,
                hasMessages: _messages.isNotEmpty,
                onLoadHistory: _showConversationHistorySheet,
                onClear: _clearConversation,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _errorText == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.md,
                        0,
                        AppSizes.md,
                        AppSizes.sm,
                      ),
                      child: _InlineErrorBanner(
                        text: _errorText!,
                        onClose: () => setState(() => _errorText = null),
                      ),
                    ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSizes.radiusXl),
                  border: Border.all(color: scheme.outlineVariant),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surface,
                      AppColors.aiAccent.withValues(alpha: 0.03),
                    ],
                  ),
                ),
                child: _buildMessagesContent(context),
              ),
            ),
            _buildComposer(context),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(_ChatMenuAction action) {
    switch (action) {
      case _ChatMenuAction.loadHistory:
        _showConversationHistorySheet();
        return;
      case _ChatMenuAction.reloadConversation:
        final id = _conversationId;
        if (id != null) {
          _loadConversationHistory(id);
        }
        return;
      case _ChatMenuAction.clearConversation:
        _clearConversation();
        return;
    }
  }

  Widget _buildComposer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSend = _messageController.text.trim().isNotEmpty && !_isSending;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        AppSizes.md + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: AppColors.aiComposerShadow,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (canSend) {
                    _sendMessage();
                  }
                },
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Hỏi về tuyến, trạm, trung chuyển, giá vé...',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(
                    AppSizes.md,
                    AppSizes.md,
                    AppSizes.sm,
                    AppSizes.md,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                    maxWidth: 140,
                  ),
                  suffixIcon: SizedBox(
                    width: _messageController.text.isEmpty ? 88 : 132,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        VoiceInputIconButton(
                          controller: _messageController,
                          tooltip: 'Nhập câu hỏi bằng giọng nói',
                          stopTooltip: 'Dừng nhập giọng nói',
                          onTextChanged: (_) => setState(() {}),
                        ),
                        TtsIconButton(
                          controller: _messageController,
                          tooltip: 'Đọc nội dung ô nhập',
                          emptyMessage:
                              'Bạn chưa nhập nội dung để đọc thành tiếng.',
                        ),
                        if (_messageController.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Xóa nội dung',
                            onPressed: () {
                              _messageController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                right: AppSizes.sm,
                bottom: AppSizes.sm,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.aiGradientStart,
                      AppColors.aiGradientEnd
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.aiGradientEnd.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  tooltip: 'Gửi tin nhắn',
                  onPressed: canSend ? _sendMessage : null,
                  color: Colors.white,
                  icon: _isSending
                      ? SizedBox(
                          width: AppSizes.md,
                          height: AppSizes.md,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesContent(BuildContext context) {
    if (_isLoadingHistory) {
      return const _LoadingHistoryState();
    }

    if (_messages.isEmpty) {
      return _EmptyChatState(
        onSuggestionTap: (text) {
          _messageController.text = text;
          _sendMessage();
        },
      );
    }

    final itemCount = _messages.length + (_isSending ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () async {
        final id = _conversationId;
        if (id != null) {
          await _loadConversationHistory(id);
        }
      },
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSizes.md,
          AppSizes.md,
          AppSizes.md,
          AppSizes.lg,
        ),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            return const _TypingIndicatorBubble();
          }
          return _ChatBubble(message: _messages[index]);
        },
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    final userMessage = _UiChatMessage(
      content: text,
      isFromUser: true,
      timestamp: DateTime.now(),
    );

    _messageController.clear();
    setState(() {
      _messages = [..._messages, userMessage];
      _isSending = true;
      _errorText = null;
    });
    _scrollToBottom();

    final accessToken = getIt<StorageService>().getAuthToken();

    try {
      final response = await _chatbotDataSource.chat(
        message: text,
        conversationId: _conversationId,
        accessToken: accessToken,
      );

      if (!mounted) {
        return;
      }

      final resolvedConversationId = response.conversationId.isEmpty
          ? _conversationId
          : response.conversationId;

      final updatedHistory = resolvedConversationId == null
          ? _savedConversations
          : _upsertSavedConversation(
              conversationId: resolvedConversationId,
              seedText: text,
              latestPreview: response.reply,
            );

      setState(() {
        _conversationId = resolvedConversationId;
        _savedConversations = updatedHistory;
        _messages = [
          ..._messages,
          _UiChatMessage(
            content: response.reply,
            isFromUser: false,
            timestamp: DateTime.now(),
          ),
        ];
      });

      if (resolvedConversationId != null) {
        await _persistSavedConversations(updatedHistory);
      }

      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = 'Không gửi được tin nhắn: $e';
        _messages = [
          ..._messages,
          _UiChatMessage(
            content:
                'Hệ thống AI đang gặp lỗi tạm thời. Bạn thử lại sau ít giây.',
            isFromUser: false,
            isError: true,
            timestamp: DateTime.now(),
          ),
        ];
      });
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _showConversationHistorySheet() async {
    final selectedConversationId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      barrierColor: Colors.black26,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusXl),
        ),
      ),
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.md,
            AppSizes.sm,
            AppSizes.md,
            AppSizes.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: AppSizes.xl,
                    height: AppSizes.xl,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      color: AppColors.aiAccent.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.history_rounded),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lịch sử hội thoại',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Chọn cuộc trò chuyện để tải lại lịch sử chat.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              if (_savedConversations.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    'Chưa có lịch sử nào được lưu. Hãy bắt đầu chat, ứng dụng sẽ tự lưu hội thoại cho bạn.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.52,
                  child: ListView.separated(
                    itemCount: _savedConversations.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (context, index) {
                      final item = _savedConversations[index];
                      return _ConversationHistoryTile(
                        item: item,
                        isCurrent: item.id == _conversationId,
                        onTap: () => Navigator.of(context).pop(item.id),
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSizes.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selectedConversationId == null || selectedConversationId.isEmpty) {
      return;
    }

    await _loadConversationHistory(selectedConversationId);
  }

  Future<void> _loadConversationHistory(String conversationId) async {
    setState(() {
      _isLoadingHistory = true;
      _errorText = null;
    });

    final accessToken = getIt<StorageService>().getAuthToken();

    try {
      final response = await _messageDataSource.getMessages(
        conversationId: conversationId,
        accessToken: accessToken,
        page: 1,
        limit: 50,
        orderBy: 'createdAt',
        orderDirection: 'asc',
        searchFields: 'content',
      );

      if (!mounted) {
        return;
      }

      final loadedMessages = response.data
          .map(
            (message) => _UiChatMessage(
              content: message.content,
              isFromUser: message.role == MessageRole.user,
              isError: false,
              timestamp: message.createdAt ?? DateTime.now(),
            ),
          )
          .toList();

      setState(() {
        _conversationId = conversationId;
        _messages = loadedMessages;
        _savedConversations = _upsertSavedConversation(
          conversationId: conversationId,
          seedText: _pickConversationTitle(loadedMessages),
          latestPreview:
              loadedMessages.isEmpty ? '' : loadedMessages.last.content,
        );
      });

      await _persistSavedConversations(_savedConversations);

      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = 'Không tải được lịch sử hội thoại: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _clearConversation() {
    setState(() {
      _conversationId = null;
      _messages = const [];
      _errorText = null;
    });
  }

  Future<void> _restoreSavedConversations() async {
    final raw = getIt<StorageService>().getString(
      AppConstants.chatbotConversationHistoryKey,
    );
    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    try {
      final parsed = json.decode(raw);
      if (parsed is! List) {
        return;
      }

      final items = <_SavedConversation>[];
      for (final entry in parsed) {
        if (entry is Map<String, dynamic>) {
          items.add(_SavedConversation.fromJson(entry));
          continue;
        }

        if (entry is Map) {
          items.add(
            _SavedConversation.fromJson(
              entry.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      }

      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) {
        return;
      }

      setState(() {
        _savedConversations = items.take(_maxSavedConversations).toList();
      });
    } catch (_) {
      await getIt<StorageService>().removeKey(
        AppConstants.chatbotConversationHistoryKey,
      );
    }
  }

  Future<void> _persistSavedConversations(
    List<_SavedConversation> conversations,
  ) async {
    final storage = getIt<StorageService>();

    if (conversations.isEmpty) {
      await storage.removeKey(AppConstants.chatbotConversationHistoryKey);
      return;
    }

    final encoded = json.encode(
      conversations.map((item) => item.toJson()).toList(),
    );
    await storage.saveString(
        AppConstants.chatbotConversationHistoryKey, encoded);
  }

  List<_SavedConversation> _upsertSavedConversation({
    required String conversationId,
    required String seedText,
    required String latestPreview,
  }) {
    final trimmedId = conversationId.trim();
    if (trimmedId.isEmpty) {
      return _savedConversations;
    }

    final now = DateTime.now();
    final seed = seedText.trim();
    final preview = latestPreview.trim().isEmpty ? seed : latestPreview.trim();
    final index =
        _savedConversations.indexWhere((item) => item.id == trimmedId);

    final nextItem = index >= 0
        ? _savedConversations[index].copyWith(
            preview: _truncate(preview, 92),
            updatedAt: now,
          )
        : _SavedConversation(
            id: trimmedId,
            title: _pickTitle(seed),
            preview: _truncate(preview, 92),
            updatedAt: now,
          );

    final updated = [..._savedConversations];
    if (index >= 0) {
      updated.removeAt(index);
    }
    updated.insert(0, nextItem);

    if (updated.length > _maxSavedConversations) {
      return updated.take(_maxSavedConversations).toList();
    }
    return updated;
  }

  String _pickTitle(String seedText) {
    final text = seedText.trim();
    if (text.isEmpty) {
      return 'Cuộc trò chuyện gần đây';
    }
    return _truncate(text, 52);
  }

  String _pickConversationTitle(List<_UiChatMessage> messages) {
    for (final message in messages) {
      if (message.isFromUser && message.content.trim().isNotEmpty) {
        return message.content;
      }
    }

    for (final message in messages) {
      if (message.content.trim().isNotEmpty) {
        return message.content;
      }
    }

    return 'Cuộc trò chuyện gần đây';
  }

  String _truncate(String text, int maxLength) {
    final trimmed = text.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength - 1)}...';
  }

  String? get _activeConversationTitle {
    final id = _conversationId;
    if (id == null || id.isEmpty) {
      return null;
    }

    for (final item in _savedConversations) {
      if (item.id == id) {
        return item.title;
      }
    }

    return 'Cuộc trò chuyện đang mở';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }
}

class _ChatHeader extends StatelessWidget {
  final bool hasConversation;

  const _ChatHeader({required this.hasConversation});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trợ lý SmartGo AI',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSizes.xxs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppSizes.xs,
              height: AppSizes.xs,
              decoration: const BoxDecoration(
                color: AppColors.aiOnline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSizes.xs),
            Text(
              hasConversation
                  ? 'Đang tiếp tục hội thoại'
                  : 'Sẵn sàng hỗ trợ lộ trình',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConversationInfoCard extends StatelessWidget {
  final String? activeConversationTitle;
  final int savedConversationsCount;
  final bool hasMessages;
  final VoidCallback onLoadHistory;
  final VoidCallback onClear;

  const _ConversationInfoCard({
    required this.activeConversationTitle,
    required this.savedConversationsCount,
    required this.hasMessages,
    required this.onLoadHistory,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = activeConversationTitle ?? 'Cuộc trò chuyện mới';
    final subtitle = savedConversationsCount == 0
        ? 'Lịch sử sẽ được lưu tự động sau khi bạn chat.'
        : 'Bạn có $savedConversationsCount cuộc trò chuyện đã lưu.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerLowest,
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.xl,
            height: AppSizes.xl,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              gradient: const LinearGradient(
                colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSizes.xxs),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Tải lịch sử',
            onPressed: onLoadHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Làm mới khung chat',
            onPressed: hasMessages ? onClear : null,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
    );
  }
}

class _ConversationHistoryTile extends StatelessWidget {
  final _SavedConversation item;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ConversationHistoryTile({
    required this.item,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: isCurrent
              ? AppColors.aiAccent.withValues(alpha: 0.08)
              : scheme.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: isCurrent ? AppColors.aiAccent : scheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSizes.lg,
                height: AppSizes.lg,
                decoration: BoxDecoration(
                  color: AppColors.aiAccent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      item.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      _formatHistoryTime(item.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.aiOnline)
              else
                Icon(
                  Icons.arrow_forward_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHistoryTime(DateTime updatedAt) {
    final now = DateTime.now();
    final difference = now.difference(updatedAt);

    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} phút trước';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours} giờ trước';
    }

    final local = updatedAt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month lúc $hour:$minute';
  }
}

class _InlineErrorBanner extends StatelessWidget {
  final String text;
  final VoidCallback onClose;

  const _InlineErrorBanner({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.aiDanger.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.sm),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.aiDanger),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.aiDanger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingHistoryState extends StatelessWidget {
  const _LoadingHistoryState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Đang tải lịch sử hội thoại...',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _UiChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFromUser = message.isFromUser;

    return Row(
      mainAxisAlignment:
          isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isFromUser) ...[
          const _MessageAvatar(isFromUser: false),
          const SizedBox(width: AppSizes.xs),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.68,
          ),
          child: DecoratedBox(
            decoration: _bubbleDecoration(scheme, isFromUser),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md,
                AppSizes.sm,
                AppSizes.md,
                AppSizes.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: isFromUser ? Colors.white : scheme.onSurface,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          color: isFromUser
                              ? Colors.white70
                              : scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      if (!isFromUser) ...[
                        const SizedBox(width: AppSizes.xs),
                        TtsIconButton.fromText(
                          text: message.content,
                          tooltip: 'Đọc câu trả lời',
                          emptyMessage: 'Câu trả lời đang trống.',
                          errorMessage: 'Không thể đọc câu trả lời lúc này.',
                          iconColor: scheme.onSurfaceVariant,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isFromUser) ...[
          const SizedBox(width: AppSizes.xs),
          const _MessageAvatar(isFromUser: true),
        ],
      ],
    );
  }

  BoxDecoration _bubbleDecoration(ColorScheme scheme, bool isFromUser) {
    if (isFromUser) {
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSizes.radiusMd),
          topRight: Radius.circular(AppSizes.radiusMd),
          bottomLeft: Radius.circular(AppSizes.radiusMd),
          bottomRight: Radius.circular(AppSizes.radiusSm),
        ),
      );
    }

    return BoxDecoration(
      color: message.isError
          ? AppColors.aiDanger.withValues(alpha: 0.1)
          : AppColors.aiAssistantBubble,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppSizes.radiusMd),
        topRight: Radius.circular(AppSizes.radiusMd),
        bottomLeft: Radius.circular(AppSizes.radiusSm),
        bottomRight: Radius.circular(AppSizes.radiusMd),
      ),
      border: Border.all(
        color: message.isError
            ? AppColors.aiDanger.withValues(alpha: 0.35)
            : scheme.outlineVariant,
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _MessageAvatar extends StatelessWidget {
  final bool isFromUser;

  const _MessageAvatar({required this.isFromUser});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: AppSizes.lg,
      height: AppSizes.lg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFromUser
            ? scheme.primaryContainer
            : AppColors.aiAccent.withValues(alpha: 0.12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(
        isFromUser ? Icons.person_rounded : Icons.smart_toy_rounded,
        size: 14,
        color: isFromUser ? scheme.onPrimaryContainer : AppColors.aiGradientEnd,
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatelessWidget {
  const _TypingIndicatorBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const _MessageAvatar(isFromUser: false),
        const SizedBox(width: AppSizes.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.aiAssistantBubble,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: AppSizes.sm,
                height: AppSizes.sm,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(
                'AI đang soạn câu trả lời...',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  final ValueChanged<String> onSuggestionTap;

  const _EmptyChatState({required this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    const suggestions = [
      'Đi từ Bến xe Miền Tây đến Bến Thành như thế nào?',
      'Tuyến nào đến Quận 1 ít trung chuyển nhất?',
      'Giá vé và giờ hoạt động của tuyến 01 là gì?',
      'Tôi ở gần Chợ Lớn, nên bắt đầu từ trạm nào?',
    ];

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(AppSizes.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSizes.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(color: scheme.outlineVariant),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.aiAccent.withValues(alpha: 0.08),
                AppColors.aiGradientEnd.withValues(alpha: 0.06),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                width: AppSizes.xxl,
                height: AppSizes.xxl,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.aiGradientStart,
                      AppColors.aiGradientEnd
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              const Text(
                'SmartGo AI sẵn sàng hỗ trợ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Hỏi về lộ trình, điểm dừng, trung chuyển và thông tin giá vé trong một khung chat duy nhất.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Text(
          'Câu hỏi gợi ý',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        ...suggestions.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.sm),
            child: _SuggestionCard(
              text: item,
              onTap: () => onSuggestionTap(item),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SuggestionCard({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.md,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.flash_on_rounded,
                size: 18,
                color: AppColors.aiAccent,
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(height: 1.35),
                ),
              ),
              const SizedBox(width: AppSizes.xs),
              Icon(
                Icons.arrow_forward_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UiChatMessage {
  final String content;
  final bool isFromUser;
  final DateTime timestamp;
  final bool isError;

  const _UiChatMessage({
    required this.content,
    required this.isFromUser,
    required this.timestamp,
    this.isError = false,
  });
}

class _SavedConversation {
  final String id;
  final String title;
  final String preview;
  final DateTime updatedAt;

  const _SavedConversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.updatedAt,
  });

  _SavedConversation copyWith({
    String? title,
    String? preview,
    DateTime? updatedAt,
  }) {
    return _SavedConversation(
      id: id,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory _SavedConversation.fromJson(Map<String, dynamic> json) {
    final rawUpdatedAt = json['updatedAt']?.toString() ?? '';

    return _SavedConversation(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Cuộc trò chuyện gần đây').toString(),
      preview: (json['preview'] ?? '').toString(),
      updatedAt: DateTime.tryParse(rawUpdatedAt) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'preview': preview,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
