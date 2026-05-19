import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/platform/sse_client.dart';
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

  final http.Client _client = getIt<http.Client>();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final ChatbotRemoteDataSource _chatbotDataSource;
  late final MessageRemoteDataSource _messageDataSource;

  SseClient? _chatSseClient;
  StreamSubscription<SseEvent>? _chatSseSubscription;

  List<_UiChatMessage> _messages = const [];
  bool _isSending = false;
  bool _isAssistantStreaming = false;
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
    _stopChatStream();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
        leadingWidth: 68,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20, top: 14, bottom: 14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Color(0xFF334155), size: 20),
              onPressed: () => context.go(AppRoutes.home),
            ),
          ),
        ),
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF14B8A6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trợ lý AI',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0D9488),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Trực tuyến',
                      style: TextStyle(
                        color: Color(0xFF0D9488),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Lịch sử hội thoại',
            onPressed: _showConversationHistorySheet,
            icon: const Icon(Icons.history_rounded, color: Color(0xFF334155)),
          ),
          PopupMenuButton<_ChatMenuAction>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF334155)),
            onSelected: _handleMenuAction,
            itemBuilder: (context) {
              return [
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _errorText == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _InlineErrorBanner(
                        text: _errorText!,
                        onClose: () => setState(() => _errorText = null),
                      ),
                    ),
            ),
            Expanded(
              child: _buildMessagesContent(context),
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
    final canSend = _messageController.text.trim().isNotEmpty && !_isSending;
    const suggestions = [
      "Đi Bến Thành",
      "Tuyến 08 mấy giờ chạy?",
      "Lộ trình tới sân bay"
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: suggestions
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () {
                            _messageController.text = s;
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              s,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 32,
                  offset: const Offset(0, -8),
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
                      if (canSend) _sendMessage();
                    },
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Hỏi trợ lý AI...',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                VoiceInputIconButton(
                  controller: _messageController,
                  tooltip: 'Nhập bằng giọng nói',
                  stopTooltip: 'Dừng',
                  onTextChanged: (_) => setState(() {}),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: canSend ? _sendMessage : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isSending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesContent(BuildContext context) {
    if (_isLoadingHistory) {
      return const _LoadingHistoryState();
    }

    final showTypingIndicator = _isSending && !_isAssistantStreaming;
    final itemCount = _messages.length + (showTypingIndicator ? 1 : 0);

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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: itemCount == 0 ? 1 : itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (itemCount == 0) {
            return _ChatBubble(
              message: _UiChatMessage(
                content:
                    "Xin chào! Mình có thể giúp bạn tra cứu tuyến xe buýt, tìm đường, hoặc gợi ý lộ trình tối ưu. Bạn cần đi đâu?",
                isFromUser: false,
                timestamp: DateTime.now(),
              ),
            );
          }
          if (showTypingIndicator && index >= _messages.length) {
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
      _isAssistantStreaming = false;
      _errorText = null;
    });
    _scrollToBottom();

    final rawAccessToken = getIt<StorageService>().getAuthToken();
    final accessToken = (rawAccessToken ?? '').trim();
    final useStreaming = kIsWeb &&
        _chatbotDataSource.shouldUseStreaming(
          message: text,
          token: accessToken,
        );

    try {
      final response = useStreaming
          ? await _sendMessageStreaming(
              message: text,
              accessToken: accessToken,
            )
          : await _sendMessageNonStreaming(
              message: text,
              accessToken: rawAccessToken,
            );

      if (!mounted) {
        return;
      }

      final assistantReply = _sanitizeAssistantReply(response.reply);
      final resolvedConversationId = response.conversationId;

      final updatedHistory = resolvedConversationId == null
          ? _savedConversations
          : _upsertSavedConversation(
              conversationId: resolvedConversationId,
              seedText: text,
              latestPreview: assistantReply,
            );

      setState(() {
        _conversationId = resolvedConversationId;
        _savedConversations = updatedHistory;

        if (useStreaming) {
          _replaceLatestAssistantMessage(
            content: assistantReply,
            isError: false,
          );
          return;
        }

        _messages = [
          ..._messages,
          _UiChatMessage(
            content: assistantReply,
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

      final hasAssistantMessage =
          _messages.isNotEmpty && !_messages.last.isFromUser;

      setState(() {
        _errorText = 'Không gửi được tin nhắn: $e';

        if (!hasAssistantMessage) {
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
          return;
        }

        _replaceLatestAssistantMessage(
          content: _messages.last.content,
          isError: true,
        );
      });
      _scrollToBottom();
    } finally {
      _stopChatStream();
      if (mounted) {
        setState(() {
          _isSending = false;
          _isAssistantStreaming = false;
        });
      }
    }
  }

  Future<_ChatSendResult> _sendMessageNonStreaming({
    required String message,
    String? accessToken,
  }) async {
    final response = await _chatbotDataSource.chat(
      message: message,
      conversationId: _conversationId,
      accessToken: accessToken,
    );

    final resolvedConversationId = response.conversationId.isEmpty
        ? _conversationId
        : response.conversationId;

    return _ChatSendResult(
      reply: response.reply,
      conversationId: resolvedConversationId,
    );
  }

  Future<_ChatSendResult> _sendMessageStreaming({
    required String message,
    required String accessToken,
  }) async {
    _stopChatStream();

    final uri = _chatbotDataSource.chatStreamUri(
      message: message,
      token: accessToken,
      conversationId: _conversationId,
    );

    final completer = Completer<_ChatSendResult>();
    final buffer = StringBuffer();
    String? resolvedConversationId = _conversationId;
    bool hasAssistantMessage = false;

    void upsertAssistantMessage(String content) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isAssistantStreaming = true;

        final shouldInsert = !hasAssistantMessage ||
            _messages.isEmpty ||
            _messages.last.isFromUser;

        if (shouldInsert) {
          _messages = [
            ..._messages,
            _UiChatMessage(
              content: content,
              isFromUser: false,
              timestamp: DateTime.now(),
            ),
          ];
          hasAssistantMessage = true;
          return;
        }

        _replaceLatestAssistantMessage(
          content: content,
          isError: false,
        );
      });
      _scrollToBottom();
    }

    void completeSuccess(String reply) {
      if (!completer.isCompleted) {
        completer.complete(
          _ChatSendResult(
            reply: reply,
            conversationId: resolvedConversationId,
          ),
        );
      }
    }

    void completeFailure(Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    final sseClient = createSseClient();
    _chatSseClient = sseClient;

    _chatSseSubscription = sseClient.connectToEvents(
      uri,
      eventNames: const ['meta', 'chunk', 'done', 'error'],
    ).listen(
      (event) {
        try {
          switch (event.event) {
            case 'meta':
              final meta = _chatbotDataSource.parseChatStreamMeta(event.data);
              final streamConversationId = meta.conversationId.trim();
              if (streamConversationId.isNotEmpty) {
                resolvedConversationId = streamConversationId;
              }
              return;
            case 'chunk':
              final chunk = _chatbotDataSource.parseChatStreamChunk(event.data);
              if (chunk.content.isEmpty) {
                return;
              }
              buffer.write(chunk.content);
              upsertAssistantMessage(buffer.toString());
              return;
            case 'done':
              final done = _chatbotDataSource.parseChatStreamDone(event.data);
              final streamConversationId = done.conversationId.trim();
              if (streamConversationId.isNotEmpty) {
                resolvedConversationId = streamConversationId;
              }

              final rawReply = done.fullReply.trim().isNotEmpty
                  ? done.fullReply
                  : buffer.toString();

              if (rawReply.trim().isNotEmpty) {
                upsertAssistantMessage(rawReply);
              }

              completeSuccess(rawReply);
              return;
            case 'error':
              final streamError =
                  _chatbotDataSource.parseChatStreamError(event.data);
              final message = streamError.message.trim().isEmpty
                  ? 'Chatbot streaming gap loi.'
                  : streamError.message.trim();
              completeFailure(Exception(message));
              return;
            default:
              return;
          }
        } catch (error) {
          completeFailure(error);
        }
      },
      onError: (error) {
        completeFailure(error);
      },
      onDone: () {
        if (completer.isCompleted) {
          return;
        }

        final fallbackReply = buffer.toString();
        if (fallbackReply.trim().isNotEmpty) {
          completeSuccess(fallbackReply);
          return;
        }

        completeFailure(
          Exception('Luong phan hoi ket thuc som. Vui long thu lai.'),
        );
      },
      cancelOnError: false,
    );

    return completer.future.whenComplete(_stopChatStream);
  }

  void _replaceLatestAssistantMessage({
    required String content,
    required bool isError,
  }) {
    if (_messages.isEmpty || _messages.last.isFromUser) {
      _messages = [
        ..._messages,
        _UiChatMessage(
          content: content,
          isFromUser: false,
          isError: isError,
          timestamp: DateTime.now(),
        ),
      ];
      return;
    }

    final updatedMessages = [..._messages];
    updatedMessages[updatedMessages.length - 1] = updatedMessages.last.copyWith(
      content: content,
      isError: isError,
      timestamp: DateTime.now(),
    );
    _messages = updatedMessages;
  }

  void _stopChatStream() {
    _chatSseSubscription?.cancel();
    _chatSseSubscription = null;

    _chatSseClient?.close();
    _chatSseClient = null;
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
    _stopChatStream();

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

      final loadedMessages = response.data.map((message) {
        final isUserMessage = message.role == MessageRole.user;
        return _UiChatMessage(
          content: isUserMessage
              ? message.content
              : _sanitizeAssistantReply(message.content),
          isFromUser: isUserMessage,
          isError: false,
          timestamp: message.createdAt ?? DateTime.now(),
        );
      }).toList();

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
    _stopChatStream();

    setState(() {
      _conversationId = null;
      _messages = const [];
      _errorText = null;
      _isSending = false;
      _isAssistantStreaming = false;
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

      final restoredConversations = items.take(_maxSavedConversations).toList();
      final latestConversationId = restoredConversations.isEmpty
          ? ''
          : restoredConversations.first.id.trim();

      setState(() {
        _savedConversations = restoredConversations;
      });

      if (latestConversationId.isNotEmpty &&
          _conversationId == null &&
          _messages.isEmpty) {
        await _loadConversationHistory(latestConversationId);
      }
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

  String _sanitizeAssistantReply(String rawText) {
    final normalized = rawText.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return rawText;
    }

    final withoutTechnicalCodeBlocks = normalized.replaceAllMapped(
      RegExp(r'```[\s\S]*?```'),
      (match) {
        final block = match.group(0) ?? '';
        return _containsTechnicalToken(block) ? '' : block;
      },
    );

    final lines = withoutTechnicalCodeBlocks.split('\n');
    final keptLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (keptLines.isNotEmpty && keptLines.last.isNotEmpty) {
          keptLines.add('');
        }
        continue;
      }

      if (_isTechnicalLine(trimmed)) {
        continue;
      }

      keptLines.add(line);
    }

    final cleaned =
        keptLines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (cleaned.isEmpty) {
      return 'Mình đã ẩn bớt dữ liệu kỹ thuật nội bộ. Bạn hỏi lại theo tuyến, trạm hoặc điểm đi/điểm đến để mình hỗ trợ rõ ràng hơn nhé.';
    }

    return cleaned;
  }

  bool _isTechnicalLine(String line) {
    if (_containsTechnicalToken(line)) {
      final looksLikeTransitInfo = RegExp(
        r'^(tuyến|trạm|tram|điểm|lộ trình|giá vé)\b',
        caseSensitive: false,
      ).hasMatch(line);
      if (!looksLikeTransitInfo) {
        return true;
      }
    }

    if (RegExp(r'^[\[{]').hasMatch(line) && line.contains(':')) {
      return true;
    }

    if (RegExp(r'[\]}]$').hasMatch(line) && line.contains(':')) {
      return true;
    }

    if (RegExp(
      r'^[\-\*\s\d\.)]*[A-Za-z_][A-Za-z0-9_]{1,30}\s*[:=]\s*(true|false)\b',
      caseSensitive: false,
    ).hasMatch(line)) {
      return true;
    }

    return false;
  }

  bool _containsTechnicalToken(String text) {
    return RegExp(
      r'routeid|tripid|stationid|conversationid|\bisworking\b|\brawdata\b|\bmetadata\b|\bstatuscode\b|"_id"|"id"\s*:|\bbus simulation\b|\bsse\b|\bpolling\b',
      caseSensitive: false,
    ).hasMatch(text);
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: AppSizes.sm),
          _LoadingHistoryText(),
        ],
      ),
    );
  }
}

class _LoadingHistoryText extends StatelessWidget {
  const _LoadingHistoryText();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      'Đang tải lịch sử hội thoại...',
      style: TextStyle(color: scheme.onSurfaceVariant),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _UiChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isFromUser = message.isFromUser;

    return Row(
      mainAxisAlignment:
          isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: DecoratedBox(
            decoration: _bubbleDecoration(isFromUser),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color:
                          isFromUser ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          color: isFromUser
                              ? Colors.white70
                              : const Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                      if (!isFromUser) ...[
                        const SizedBox(width: 8),
                        TtsIconButton.fromText(
                          text: message.content,
                          tooltip: 'Đọc câu trả lời',
                          emptyMessage: 'Câu trả lời đang trống.',
                          errorMessage: 'Không thể đọc câu trả lời lúc này.',
                          iconColor: const Color(0xFF94A3B8),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
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
      ],
    );
  }

  BoxDecoration _bubbleDecoration(bool isFromUser) {
    if (isFromUser) {
      return const BoxDecoration(
        color: Color(0xFF0D9488),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(6),
        ),
      );
    }

    return BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
        bottomRight: Radius.circular(24),
        bottomLeft: Radius.circular(6),
      ),
      border: Border.all(
        color: message.isError
            ? const Color(0xFFEF4444).withValues(alpha: 0.35)
            : const Color(0xFFF1F5F9),
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

class _TypingIndicatorBubble extends StatelessWidget {
  const _TypingIndicatorBubble();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
              bottomLeft: Radius.circular(6),
            ),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                ),
              ),
              SizedBox(width: 8),
              Text(
                'AI đang soạn...',
                style: TextStyle(
                  color: Color(0xFF64748B),
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

class _ChatSendResult {
  final String reply;
  final String? conversationId;

  const _ChatSendResult({
    required this.reply,
    required this.conversationId,
  });
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

  _UiChatMessage copyWith({
    String? content,
    bool? isFromUser,
    DateTime? timestamp,
    bool? isError,
  }) {
    return _UiChatMessage(
      content: content ?? this.content,
      isFromUser: isFromUser ?? this.isFromUser,
      timestamp: timestamp ?? this.timestamp,
      isError: isError ?? this.isError,
    );
  }
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
