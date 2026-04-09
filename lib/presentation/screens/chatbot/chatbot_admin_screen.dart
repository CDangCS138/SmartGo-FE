import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_sizes.dart';
import '../../../data/datasources/chatbot_remote_data_source.dart';
import '../../../data/datasources/message_remote_data_source.dart';
import '../../../data/models/chatbot_models.dart';
import '../../../data/models/message_models.dart';

class ChatbotAdminScreen extends StatefulWidget {
  const ChatbotAdminScreen({super.key});

  @override
  State<ChatbotAdminScreen> createState() => _ChatbotAdminScreenState();
}

class _ChatbotAdminScreenState extends State<ChatbotAdminScreen> {
  final http.Client _client = http.Client();

  late final ChatbotRemoteDataSource _chatbotDataSource;
  late final MessageRemoteDataSource _messageDataSource;

  final TextEditingController _embedTextController = TextEditingController();
  final TextEditingController _embedMetadataController =
      TextEditingController(text: '{"source":"manual"}');

  Uint8List? _selectedFileBytes;
  String? _selectedFileName;

  ChatbotKnowledgeType _embedType = ChatbotKnowledgeType.route;
  bool _isEmbedding = false;
  bool _isUploadingFile = false;
  ChatbotEmbeddedVector? _lastEmbedResult;
  ChatbotBulkEmbedResponse? _lastBulkResult;

  final TextEditingController _conversationIdController =
      TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageIdController = TextEditingController();

  bool _isMessagesLoading = false;
  bool _isMessageBusy = false;
  List<MessageModel> _messages = const [];
  int _total = 0;
  int _page = 1;
  final int _limit = 10;
  String _orderDirection = 'desc';
  List<_ConversationHistoryRef> _savedConversations = const [];
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _chatbotDataSource = ChatbotRemoteDataSource(client: _client);
    _messageDataSource = MessageRemoteDataSource(client: _client);
    _restoreConversationHistory();
  }

  @override
  void dispose() {
    _embedTextController.dispose();
    _embedMetadataController.dispose();
    _conversationIdController.dispose();
    _searchController.dispose();
    _messageIdController.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: AppBar(
          title: const Text('Chatbot Admin'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.psychology_outlined), text: 'Embed Text'),
              Tab(icon: Icon(Icons.upload_file_outlined), text: 'Embed File'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'Messages'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildEmbedTextTab(),
            _buildEmbedFileTab(),
            _buildMessagesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbedTextTab() {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(
            title: 'Embed 1 knowledge item',
            subtitle:
                'POST /api/v1/chatbot/embed (admin only). Type: route/station/faq/general.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _embedTextController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Knowledge text',
                    hintText:
                        'Tuyen xe buyt so 01 chay tu Ben xe Mien Tay den Ben Thanh.',
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                DropdownButtonFormField<ChatbotKnowledgeType>(
                  initialValue: _embedType,
                  items: ChatbotKnowledgeType.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _embedType = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Type',
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                TextField(
                  controller: _embedMetadataController,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Metadata JSON',
                    hintText: '{"routeCode":"01","routeName":"Tuyen 01"}',
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isEmbedding ? null : _embedSingleText,
                    icon: _isEmbedding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_as_rounded),
                    label: Text(_isEmbedding ? 'Embedding...' : 'Embed now'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          if (_lastEmbedResult != null)
            _panel(
              title: 'Last embed result',
              subtitle: 'Server response (201/200).',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('ID', _lastEmbedResult!.id),
                  _kv('Type', _lastEmbedResult!.type.name),
                  _kv('Text', _lastEmbedResult!.text),
                  _kv('Created by', _lastEmbedResult!.createdBy ?? '-'),
                  _kv('Created at',
                      _lastEmbedResult!.createdAt?.toIso8601String() ?? '-'),
                ],
              ),
            )
          else
            Text(
              'Chua co ket qua embed.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _buildEmbedFileTab() {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(
            title: 'Bulk embed from JSON file',
            subtitle:
                'POST /api/v1/chatbot/embed/file (multipart/form-data, field: file).',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _pickJsonFile,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: Text(
                          _selectedFileName == null
                              ? 'Select JSON file'
                              : _selectedFileName!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                if (_selectedFileBytes != null)
                  Text(
                    'Loaded bytes: ${_selectedFileBytes!.lengthInBytes}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: AppSizes.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isUploadingFile ? null : _uploadJsonFile,
                    icon: _isUploadingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_isUploadingFile ? 'Uploading...' : 'Upload'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          if (_lastBulkResult != null)
            _panel(
              title: 'Bulk response summary',
              subtitle: 'Ket qua tra ve tu endpoint bulk embed.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Total', _lastBulkResult!.total.toString()),
                  _kv('Page', _lastBulkResult!.page.toString()),
                  _kv('Limit', _lastBulkResult!.limit.toString()),
                  _kv('Data count', _lastBulkResult!.data.length.toString()),
                ],
              ),
            )
          else
            Text(
              'Chua co ket qua bulk embed.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _buildMessagesTab() {
    final scheme = Theme.of(context).colorScheme;
    final hasNext = _page * _limit < _total;

    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        children: [
          _panel(
            title: 'Message manager',
            subtitle: 'Chọn hội thoại từ lịch sử chat rồi thao tác messages.',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _conversationIdController,
                        decoration: const InputDecoration(
                          labelText: 'Hội thoại',
                          hintText:
                              'Dán mã hội thoại hoặc chọn từ lịch sử bên dưới',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    FilledButton.icon(
                      onPressed: _isMessagesLoading ? null : _loadMessages,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Tải'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _savedConversations.isEmpty
                        ? null
                        : _selectConversationFromHistory,
                    icon: const Icon(Icons.history_rounded),
                    label: Text(
                      _savedConversations.isEmpty
                          ? 'Chưa có lịch sử hội thoại'
                          : 'Chọn từ lịch sử (${_savedConversations.length})',
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'Lọc nội dung (tùy chọn)',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    DropdownButton<String>(
                      value: _orderDirection,
                      items: const [
                        DropdownMenuItem(value: 'desc', child: Text('desc')),
                        DropdownMenuItem(value: 'asc', child: Text('asc')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _orderDirection = value);
                      },
                    ),
                    const SizedBox(width: AppSizes.sm),
                    FilledButton.tonalIcon(
                      onPressed:
                          _isMessageBusy ? null : _showCreateMessageSheet,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tạo'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageIdController,
                        decoration: const InputDecoration(
                          labelText: 'Xem message theo ID',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    FilledButton.tonalIcon(
                      onPressed: _isMessageBusy ? null : _getMessageById,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Xem'),
                    ),
                  ],
                ),
                if (_statusText != null) ...[
                  const SizedBox(height: AppSizes.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _statusText!,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                if (_isMessagesLoading) ...[
                  const SizedBox(height: AppSizes.sm),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Chua co message nao.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: _messages.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSizes.sm),
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      return _buildMessageItem(item);
                    },
                  ),
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _isMessagesLoading || _page <= 1
                    ? null
                    : () => _loadMessages(targetPage: _page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Prev'),
              ),
              const Spacer(),
              Text('Page $_page / ${_calcTotalPages()}'),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _isMessagesLoading || !hasNext
                    ? null
                    : () => _loadMessages(targetPage: _page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(MessageModel item) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.sm,
                  vertical: AppSizes.xs,
                ),
                decoration: BoxDecoration(
                  color: _roleColor(item.role).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: Text(
                  item.role.name,
                  style: TextStyle(
                    color: _roleColor(item.role),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                item.createdAt?.toIso8601String() ?? '-',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            item.content,
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'ID: ${item.id}',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _showMessageDetail(item.id),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View'),
              ),
              TextButton.icon(
                onPressed: () => _showEditMessageSheet(item),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => _deleteMessage(item),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.aiDanger,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            subtitle,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          child,
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: scheme.onSurface, fontSize: 13),
          children: [
            TextSpan(
              text: '$key: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Future<void> _embedSingleText() async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      _toast('Thieu access token. Vui long dang nhap lai.');
      return;
    }

    final text = _embedTextController.text.trim();
    if (text.isEmpty) {
      _toast('Knowledge text khong duoc de trong.');
      return;
    }

    Map<String, dynamic> metadata = const {};
    final metadataRaw = _embedMetadataController.text.trim();
    if (metadataRaw.isNotEmpty) {
      try {
        final parsed = json.decode(metadataRaw);
        if (parsed is! Map<String, dynamic>) {
          _toast('Metadata JSON phai la object.');
          return;
        }
        metadata = parsed;
      } catch (_) {
        _toast('Metadata JSON khong hop le.');
        return;
      }
    }

    setState(() => _isEmbedding = true);
    try {
      final result = await _chatbotDataSource.embedKnowledge(
        request: ChatbotEmbedRequest(
          text: text,
          type: _embedType,
          metadata: metadata,
        ),
        accessToken: token,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _lastEmbedResult = result;
      });
      _toast('Embed thanh cong.');
    } catch (e) {
      _toast('Embed that bai: $e');
    } finally {
      if (mounted) {
        setState(() => _isEmbedding = false);
      }
    }
  }

  Future<void> _pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    if (file.bytes == null) {
      _toast('Khong doc duoc bytes tu file da chon.');
      return;
    }

    setState(() {
      _selectedFileBytes = file.bytes;
      _selectedFileName = file.name;
    });
  }

  Future<void> _uploadJsonFile() async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      _toast('Thieu access token. Vui long dang nhap lai.');
      return;
    }

    if (_selectedFileBytes == null || _selectedFileName == null) {
      _toast('Ban chua chon file JSON.');
      return;
    }

    setState(() => _isUploadingFile = true);
    try {
      final result = await _chatbotDataSource.embedKnowledgeFile(
        accessToken: token,
        bytes: _selectedFileBytes!,
        filename: _selectedFileName!,
      );

      if (!mounted) {
        return;
      }

      setState(() => _lastBulkResult = result);
      _toast('Upload file va embed thanh cong.');
    } catch (e) {
      _toast('Upload that bai: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploadingFile = false);
      }
    }
  }

  Future<void> _restoreConversationHistory() async {
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

      final items = <_ConversationHistoryRef>[];
      for (final entry in parsed) {
        if (entry is Map<String, dynamic>) {
          items.add(_ConversationHistoryRef.fromJson(entry));
          continue;
        }

        if (entry is Map) {
          items.add(
            _ConversationHistoryRef.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }

      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) {
        return;
      }

      setState(() {
        _savedConversations = items.take(20).toList();
      });
    } catch (_) {
      // Keep current state when local history payload is malformed.
    }
  }

  Future<void> _selectConversationFromHistory() async {
    if (_savedConversations.isEmpty) {
      _toast('Chưa có lịch sử hội thoại để chọn.');
      return;
    }

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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
              const Text(
                'Chọn hội thoại',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Dùng hội thoại đã lưu để tải danh sách messages.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSizes.md),
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.5,
                child: ListView.separated(
                  itemCount: _savedConversations.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSizes.sm),
                  itemBuilder: (context, index) {
                    final item = _savedConversations[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      onTap: () => Navigator.of(context).pop(item.id),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                          color: scheme.surface,
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSizes.md),
                          child: Row(
                            children: [
                              const Icon(Icons.history_rounded),
                              const SizedBox(width: AppSizes.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: AppSizes.xs),
                                    Text(
                                      item.preview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: AppSizes.xs),
                                    Text(
                                      _formatConversationUpdatedAt(
                                        item.updatedAt,
                                      ),
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selectedId == null || selectedId.isEmpty) {
      return;
    }

    _conversationIdController.text = selectedId;
    setState(() {
      _statusText = 'Đã chọn hội thoại từ lịch sử.';
      _page = 1;
    });

    await _loadMessages(targetPage: 1);
  }

  String _formatConversationUpdatedAt(DateTime updatedAt) {
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

  Future<void> _loadMessages({int? targetPage}) async {
    final conversationId = _conversationIdController.text.trim();
    if (conversationId.isEmpty) {
      _toast('Hãy nhập hoặc chọn hội thoại từ lịch sử để tải messages.');
      return;
    }

    setState(() {
      _isMessagesLoading = true;
      _statusText = null;
    });

    try {
      final response = await _messageDataSource.getMessages(
        conversationId: conversationId,
        accessToken: _accessToken,
        page: targetPage ?? _page,
        limit: _limit,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        orderBy: 'createdAt',
        orderDirection: _orderDirection,
        searchFields: 'content',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = response.data;
        _total = response.total;
        _page = response.page;
        _statusText =
            'Loaded ${response.data.length} items (total: ${response.total}).';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusText = 'Load messages that bai: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isMessagesLoading = false);
      }
    }
  }

  Future<void> _showCreateMessageSheet() async {
    final conversationId = _conversationIdController.text.trim();
    if (conversationId.isEmpty) {
      _toast('Hãy chọn hội thoại trước khi tạo message.');
      return;
    }

    final contentController = TextEditingController();
    final metadataController = TextEditingController(text: '{}');
    MessageRole selectedRole = MessageRole.user;

    final shouldCreate = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppSizes.md,
                right: AppSizes.md,
                top: AppSizes.md,
                bottom: MediaQuery.of(context).viewInsets.bottom + AppSizes.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Create message',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSizes.md),
                  DropdownButtonFormField<MessageRole>(
                    initialValue: selectedRole,
                    items: MessageRole.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setModalState(() => selectedRole = value);
                    },
                    decoration: const InputDecoration(labelText: 'Role'),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  TextField(
                    controller: contentController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'Content'),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  TextField(
                    controller: metadataController,
                    minLines: 2,
                    maxLines: 6,
                    decoration:
                        const InputDecoration(labelText: 'Metadata JSON'),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Create'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (shouldCreate != true) {
      return;
    }

    final content = contentController.text.trim();
    if (content.isEmpty) {
      _toast('Content khong duoc de trong.');
      return;
    }

    final metadata = _parseMetadata(metadataController.text.trim());
    if (metadata == null) {
      _toast('Metadata JSON khong hop le.');
      return;
    }

    setState(() => _isMessageBusy = true);
    try {
      await _messageDataSource.createMessage(
        request: CreateMessageRequest(
          conversationId: conversationId,
          role: selectedRole,
          content: content,
          metadata: metadata,
        ),
        accessToken: _accessToken,
      );
      _toast('Tao message thanh cong.');
      await _loadMessages(targetPage: 1);
    } catch (e) {
      _toast('Tao message that bai: $e');
    } finally {
      if (mounted) {
        setState(() => _isMessageBusy = false);
      }
    }
  }

  Future<void> _showEditMessageSheet(MessageModel message) async {
    final contentController = TextEditingController(text: message.content);
    final metadataController =
        TextEditingController(text: json.encode(message.metadata));

    final shouldUpdate = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSizes.md,
            right: AppSizes.md,
            top: AppSizes.md,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSizes.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Update message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSizes.md),
              TextField(
                controller: contentController,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Content'),
              ),
              const SizedBox(height: AppSizes.sm),
              TextField(
                controller: metadataController,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Metadata JSON'),
              ),
              const SizedBox(height: AppSizes.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Update'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (shouldUpdate != true) {
      return;
    }

    final content = contentController.text.trim();
    if (content.isEmpty) {
      _toast('Content khong duoc de trong.');
      return;
    }

    final metadata = _parseMetadata(metadataController.text.trim());
    if (metadata == null) {
      _toast('Metadata JSON khong hop le.');
      return;
    }

    setState(() => _isMessageBusy = true);
    try {
      await _messageDataSource.updateMessageById(
        id: message.id,
        request: UpdateMessageRequest(
          content: content,
          metadata: metadata,
        ),
        accessToken: _accessToken,
      );
      _toast('Cap nhat message thanh cong.');
      await _loadMessages();
    } catch (e) {
      _toast('Cap nhat message that bai: $e');
    } finally {
      if (mounted) {
        setState(() => _isMessageBusy = false);
      }
    }
  }

  Future<void> _deleteMessage(MessageModel message) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete message'),
            content: Text('Delete message id ${message.id}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) {
      return;
    }

    setState(() => _isMessageBusy = true);
    try {
      await _messageDataSource.deleteMessageById(
        id: message.id,
        accessToken: _accessToken,
      );
      _toast('Da xoa message.');
      await _loadMessages();
    } catch (e) {
      _toast('Xoa message that bai: $e');
    } finally {
      if (mounted) {
        setState(() => _isMessageBusy = false);
      }
    }
  }

  Future<void> _showMessageDetail(String id) async {
    setState(() => _isMessageBusy = true);
    try {
      final message = await _messageDataSource.getMessageById(
        id: id,
        accessToken: _accessToken,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Message detail'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _kv('ID', message.id),
                  _kv('Conversation', message.conversationId),
                  _kv('Role', message.role.name),
                  _kv('Content', message.content),
                  _kv('Metadata', json.encode(message.metadata)),
                  _kv('Created', message.createdAt?.toIso8601String() ?? '-'),
                  _kv('Updated', message.updatedAt?.toIso8601String() ?? '-'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _toast('Lay message detail that bai: $e');
    } finally {
      if (mounted) {
        setState(() => _isMessageBusy = false);
      }
    }
  }

  Future<void> _getMessageById() async {
    final id = _messageIdController.text.trim();
    if (id.isEmpty) {
      _toast('Nhap message id de truy van.');
      return;
    }
    await _showMessageDetail(id);
  }

  Map<String, dynamic>? _parseMetadata(String input) {
    if (input.isEmpty) {
      return const {};
    }

    try {
      final parsed = json.decode(input);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Color _roleColor(MessageRole role) {
    switch (role) {
      case MessageRole.user:
        return AppColors.aiGradientEnd;
      case MessageRole.bot:
        return AppColors.aiGradientStart;
      case MessageRole.admin:
        return AppColors.aiWarning;
      case MessageRole.system:
        return AppColors.aiDanger;
    }
  }

  int _calcTotalPages() {
    if (_total <= 0) {
      return 1;
    }
    return (_total / _limit).ceil();
  }

  String? get _accessToken => getIt<StorageService>().getAuthToken();

  void _toast(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ConversationHistoryRef {
  final String id;
  final String title;
  final String preview;
  final DateTime updatedAt;

  const _ConversationHistoryRef({
    required this.id,
    required this.title,
    required this.preview,
    required this.updatedAt,
  });

  factory _ConversationHistoryRef.fromJson(Map<String, dynamic> json) {
    final rawUpdatedAt = json['updatedAt']?.toString() ?? '';

    return _ConversationHistoryRef(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Cuộc trò chuyện gần đây').toString(),
      preview: (json['preview'] ?? '').toString(),
      updatedAt: DateTime.tryParse(rawUpdatedAt) ?? DateTime.now(),
    );
  }
}
