enum ChatbotKnowledgeType {
  route,
  station,
  faq,
  general;

  String toApiValue() => name;

  static ChatbotKnowledgeType fromApiValue(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'route':
        return ChatbotKnowledgeType.route;
      case 'station':
        return ChatbotKnowledgeType.station;
      case 'faq':
        return ChatbotKnowledgeType.faq;
      case 'general':
      default:
        return ChatbotKnowledgeType.general;
    }
  }
}

class ChatbotChatResponse {
  final String reply;
  final String conversationId;
  final int contextCount;

  const ChatbotChatResponse({
    required this.reply,
    required this.conversationId,
    required this.contextCount,
  });

  factory ChatbotChatResponse.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    return ChatbotChatResponse(
      reply: (data['reply'] ?? '').toString(),
      conversationId: (data['conversationId'] ?? '').toString(),
      contextCount: (data['contextCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatbotStreamMeta {
  final String conversationId;
  final int contextCount;
  final bool cached;

  const ChatbotStreamMeta({
    required this.conversationId,
    required this.contextCount,
    required this.cached,
  });

  factory ChatbotStreamMeta.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    return ChatbotStreamMeta(
      conversationId: (data['conversationId'] ?? '').toString(),
      contextCount: (data['contextCount'] as num?)?.toInt() ?? 0,
      cached: _toBool(data['cached']),
    );
  }
}

class ChatbotStreamChunk {
  final String content;

  const ChatbotStreamChunk({required this.content});

  factory ChatbotStreamChunk.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    return ChatbotStreamChunk(
      content: (data['content'] ?? '').toString(),
    );
  }
}

class ChatbotStreamDone {
  final String conversationId;
  final String fullReply;
  final int contextCount;
  final bool cached;

  const ChatbotStreamDone({
    required this.conversationId,
    required this.fullReply,
    required this.contextCount,
    required this.cached,
  });

  factory ChatbotStreamDone.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    return ChatbotStreamDone(
      conversationId: (data['conversationId'] ?? '').toString(),
      fullReply: (data['fullReply'] ?? data['reply'] ?? '').toString(),
      contextCount: (data['contextCount'] as num?)?.toInt() ?? 0,
      cached: _toBool(data['cached']),
    );
  }
}

class ChatbotStreamError {
  final String message;

  const ChatbotStreamError({required this.message});

  factory ChatbotStreamError.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    return ChatbotStreamError(
      message: (data['message'] ?? data['error'] ?? '').toString(),
    );
  }
}

class ChatbotEmbedRequest {
  final String text;
  final ChatbotKnowledgeType type;
  final Map<String, dynamic> metadata;

  const ChatbotEmbedRequest({
    required this.text,
    required this.type,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'type': type.toApiValue(),
      'metadata': metadata,
    };
  }
}

class ChatbotEmbeddedVector {
  final String id;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String text;
  final ChatbotKnowledgeType type;
  final Map<String, dynamic> metadata;

  const ChatbotEmbeddedVector({
    required this.id,
    required this.text,
    required this.type,
    required this.metadata,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  factory ChatbotEmbeddedVector.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    return ChatbotEmbeddedVector(
      id: (data['_id'] ?? data['id'] ?? '').toString(),
      createdAt: _tryParseDate(data['createdAt']),
      createdBy: data['createdBy']?.toString(),
      updatedAt: _tryParseDate(data['updatedAt']),
      updatedBy: data['updatedBy']?.toString(),
      text: (data['text'] ?? '').toString(),
      type: ChatbotKnowledgeType.fromApiValue(data['type']?.toString()),
      metadata: _mapOrEmpty(data['metadata']),
    );
  }
}

class ChatbotBulkEmbedResponse {
  final int total;
  final int page;
  final int limit;
  final List<dynamic> data;

  const ChatbotBulkEmbedResponse({
    required this.total,
    required this.page,
    required this.limit,
    required this.data,
  });

  factory ChatbotBulkEmbedResponse.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    final rawList = data['data'];

    return ChatbotBulkEmbedResponse(
      total: (data['total'] as num?)?.toInt() ?? 0,
      page: (data['page'] as num?)?.toInt() ?? 1,
      limit: (data['limit'] as num?)?.toInt() ?? 10,
      data: rawList is List ? rawList : const [],
    );
  }
}

Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
  final rawData = json['data'];
  if (rawData is Map<String, dynamic>) {
    return rawData;
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

bool _toBool(dynamic raw) {
  if (raw is bool) {
    return raw;
  }

  final text = raw?.toString().trim().toLowerCase();
  if (text == null || text.isEmpty) {
    return false;
  }

  return text == 'true' || text == '1' || text == 'yes';
}
