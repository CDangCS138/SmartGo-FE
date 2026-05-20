enum NotificationType {
  paymentSuccess,
  billCreated,
  system,
  unknown;

  static NotificationType fromApi(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'PAYMENT_SUCCESS':
        return NotificationType.paymentSuccess;
      case 'BILL_CREATED':
        return NotificationType.billCreated;
      case 'SYSTEM':
        return NotificationType.system;
      default:
        return NotificationType.unknown;
    }
  }

  String toApiValue() {
    switch (this) {
      case NotificationType.paymentSuccess:
        return 'PAYMENT_SUCCESS';
      case NotificationType.billCreated:
        return 'BILL_CREATED';
      case NotificationType.system:
        return 'SYSTEM';
      case NotificationType.unknown:
        return '';
    }
  }
}

class NotificationModel {
  final String id;
  final String title;
  final String content;
  final NotificationType type;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    this.isRead = false,
    this.createdAt,
    this.readAt,
    this.metadata = const {},
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    // API gắn payload hóa đơn vào field "data" — không unwrap như wrapper list.
    final nestedPayload = json['data'];
    final metadata = nestedPayload is Map<String, dynamic>
        ? nestedPayload
        : nestedPayload is Map
            ? Map<String, dynamic>.from(nestedPayload)
            : _mapOrEmpty(json['metadata']);

    return NotificationModel(
      id: _readString(json['_id'] ?? json['id']),
      title: _readString(json['title']),
      content: _readString(json['content'] ?? json['body'] ?? json['message']),
      type: NotificationType.fromApi(
        _readStringOrNull(json['type']) ??
            json['notificationType']?.toString(),
      ),
      isRead: _readBool(json['isRead'] ?? json['read']),
      createdAt: _tryParseDate(json['createdAt'] ?? json['created_at']),
      readAt: _tryParseDate(json['readAt'] ?? json['read_at']),
      metadata: metadata,
    );
  }
}

class NotificationsPageResponse {
  final int total;
  final int page;
  final int limit;
  final List<NotificationModel> data;

  const NotificationsPageResponse({
    required this.total,
    required this.page,
    required this.limit,
    required this.data,
  });

  factory NotificationsPageResponse.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload = json;
    if (json['data'] is Map) {
      final inner = _asMap(json['data']);
      if (inner != null &&
          (inner['data'] is List ||
              inner['items'] is List ||
              inner['notifications'] is List ||
              inner['results'] is List)) {
        payload = inner;
      }
    }

    final rawList = payload['data'] ??
        payload['items'] ??
        payload['notifications'] ??
        payload['results'];
    final notifications = <NotificationModel>[];

    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          notifications.add(NotificationModel.fromJson(item));
        } else if (item is Map) {
          notifications.add(
            NotificationModel.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return NotificationsPageResponse(
      total: _readInt(payload['total'], fallback: notifications.length),
      page: _readInt(payload['page'], fallback: 1),
      limit: _readInt(payload['limit'], fallback: notifications.length),
      data: notifications,
    );
  }
}

Map<String, dynamic>? _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return null;
}

Map<String, dynamic> _mapOrEmpty(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return const {};
}

String _readString(dynamic raw, {String fallback = ''}) {
  if (raw == null) {
    return fallback;
  }
  if (raw is String) {
    return raw;
  }
  return raw.toString();
}

String? _readStringOrNull(dynamic raw) {
  final value = _readString(raw, fallback: '').trim();
  if (value.isEmpty) {
    return null;
  }
  return value;
}

int _readInt(dynamic raw, {int fallback = 0}) {
  if (raw == null) {
    return fallback;
  }
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw) ?? fallback;
  }
  return fallback;
}

bool _readBool(dynamic raw, {bool fallback = false}) {
  if (raw == null) {
    return fallback;
  }
  if (raw is bool) {
    return raw;
  }
  if (raw is String) {
    final normalized = raw.toLowerCase().trim();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  if (raw is num) {
    return raw != 0;
  }
  return fallback;
}

DateTime? _tryParseDate(dynamic raw) {
  if (raw == null) {
    return null;
  }
  return DateTime.tryParse(raw.toString());
}
