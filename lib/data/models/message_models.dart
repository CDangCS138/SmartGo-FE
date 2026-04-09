enum MessageRole {
  user,
  bot,
  admin,
  system;

  String toApiValue() => name;

  static MessageRole fromApiValue(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'user':
        return MessageRole.user;
      case 'bot':
      case 'assistant':
        return MessageRole.bot;
      case 'admin':
        return MessageRole.admin;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.user;
    }
  }
}

class MessageModel {
  final String id;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String conversationId;
  final String? userId;
  final MessageRole role;
  final String content;
  final Map<String, dynamic> metadata;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.metadata,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
    this.userId,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);

    return MessageModel(
      id: (data['_id'] ?? data['id'] ?? '').toString(),
      createdAt: _tryParseDate(data['createdAt']),
      createdBy: data['createdBy']?.toString(),
      updatedAt: _tryParseDate(data['updatedAt']),
      updatedBy: data['updatedBy']?.toString(),
      conversationId: (data['conversationId'] ?? '').toString(),
      userId: data['userId']?.toString(),
      role: MessageRole.fromApiValue(data['role']?.toString()),
      content: (data['content'] ?? '').toString(),
      metadata: _mapOrEmpty(data['metadata']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (createdBy != null) 'createdBy': createdBy,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (updatedBy != null) 'updatedBy': updatedBy,
      'conversationId': conversationId,
      if (userId != null) 'userId': userId,
      'role': role.toApiValue(),
      'content': content,
      'metadata': metadata,
    };
  }
}

class MessageListResponse {
  final int total;
  final int page;
  final int limit;
  final List<MessageModel> data;

  const MessageListResponse({
    required this.total,
    required this.page,
    required this.limit,
    required this.data,
  });

  factory MessageListResponse.fromJson(Map<String, dynamic> json) {
    final dataMap = _unwrapData(json);
    final rawList = dataMap['data'];

    final list = <MessageModel>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          list.add(MessageModel.fromJson(item));
        }
      }
    }

    return MessageListResponse(
      total: (dataMap['total'] as num?)?.toInt() ?? list.length,
      page: (dataMap['page'] as num?)?.toInt() ?? 1,
      limit: (dataMap['limit'] as num?)?.toInt() ?? 10,
      data: list,
    );
  }
}

class CreateMessageRequest {
  final String conversationId;
  final MessageRole role;
  final String content;
  final Map<String, dynamic> metadata;

  const CreateMessageRequest({
    required this.conversationId,
    required this.role,
    required this.content,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'conversationId': conversationId,
      'role': role.toApiValue(),
      'content': content,
      'metadata': metadata,
    };
  }
}

class UpdateMessageRequest {
  final String content;
  final Map<String, dynamic> metadata;

  const UpdateMessageRequest({
    required this.content,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'metadata': metadata,
    };
  }
}

Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
  final rawData = json['data'];
  if (rawData is Map<String, dynamic>) {
    final hasPaging = rawData.containsKey('total') ||
        rawData.containsKey('page') ||
        rawData.containsKey('limit') ||
        rawData.containsKey('data');
    if (hasPaging) {
      return rawData;
    }
  }
  return json;
}

Map<String, dynamic> _mapOrEmpty(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  return const {};
}

DateTime? _tryParseDate(dynamic raw) {
  if (raw == null) {
    return null;
  }
  return DateTime.tryParse(raw.toString());
}
