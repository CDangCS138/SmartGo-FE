class BillCreateRequest {
  final String routeId;
  final String ticketType;
  final int quantity;
  final int discountAmount;
  final Map<String, dynamic> metadata;

  const BillCreateRequest({
    required this.routeId,
    required this.ticketType,
    required this.quantity,
    this.discountAmount = 0,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'routeId': routeId,
      'ticketType': ticketType,
      'quantity': quantity,
      'discountAmount': discountAmount,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TicketModel {
  final String ticketCode;
  final String ticketType;
  final int unitPrice;
  final DateTime? expiredAt;
  final int remainingTrips;
  final String? qrPayload;
  final String? qrImageUrl;
  final String ticketStatus;

  const TicketModel({
    required this.ticketCode,
    required this.ticketType,
    required this.unitPrice,
    required this.ticketStatus,
    this.expiredAt,
    this.remainingTrips = 0,
    this.qrPayload,
    this.qrImageUrl,
  });

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    final data = _unwrapDataMap(json);

    return TicketModel(
      ticketCode: _readString(data['ticketCode'] ?? data['ticket_code']),
      ticketType: _readString(data['ticketType'] ?? data['ticket_type']),
      unitPrice: _readInt(data['unitPrice']),
      expiredAt: _tryParseDate(data['expiredAt'] ?? data['expired_at']),
      remainingTrips: _readInt(data['remainingTrips']),
      qrPayload: _readStringOrNull(data['qrPayload'] ?? data['qr_payload']),
      qrImageUrl: _readStringOrNull(data['qrImageUrl'] ?? data['qr_image_url']),
      ticketStatus: _readString(data['ticketStatus'] ?? data['status']),
    );
  }
}

class BillModel {
  final String id;
  final String billCode;
  final String status;
  final String ticketType;
  final int quantity;
  final int unitPrice;
  final int subTotal;
  final int discountAmount;
  final int totalAmount;
  final String? paymentTransactionId;
  final String? txnRef;
  final String? routeId;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;
  final List<TicketModel> tickets;
  final Map<String, dynamic> metadata;

  const BillModel({
    required this.id,
    required this.billCode,
    required this.status,
    required this.ticketType,
    required this.quantity,
    required this.unitPrice,
    required this.subTotal,
    required this.discountAmount,
    required this.totalAmount,
    required this.tickets,
    this.paymentTransactionId,
    this.txnRef,
    this.routeId,
    this.createdAt,
    this.paidAt,
    this.cancelledAt,
    this.metadata = const {},
  });

  factory BillModel.fromJson(Map<String, dynamic> json) {
    final data = _unwrapDataMap(json);

    return BillModel(
      id: _readString(data['_id'] ?? data['id']),
      billCode: _readString(data['billCode']),
      status: _readString(data['status']),
      ticketType: _readString(data['ticketType'] ?? data['ticket_type']),
      quantity: _readInt(data['quantity']),
      unitPrice: _readInt(data['unitPrice']),
      subTotal: _readInt(data['subTotal']),
      discountAmount: _readInt(data['discountAmount']),
      totalAmount: _readInt(data['totalAmount']),
      paymentTransactionId:
          _readStringOrNull(data['paymentTransactionId'] ?? data['paymentId']),
      txnRef: _readStringOrNull(data['txnRef'] ?? data['txn_ref']),
      routeId: _readStringOrNull(data['routeId'] ?? data['route_id']),
      createdAt: _tryParseDate(data['createdAt'] ?? data['created_at']),
      paidAt: _tryParseDate(data['paidAt'] ?? data['paid_at']),
      cancelledAt: _tryParseDate(data['cancelledAt'] ?? data['cancelled_at']),
      tickets: _parseTickets(data['tickets']),
      metadata: _mapOrEmpty(data['metadata']),
    );
  }

  static List<TicketModel> _parseTickets(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    final tickets = <TicketModel>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        tickets.add(TicketModel.fromJson(item));
      } else if (item is Map) {
        tickets.add(TicketModel.fromJson(Map<String, dynamic>.from(item)));
      } else if (item != null) {
        tickets.add(
          TicketModel(
            ticketCode: item.toString(),
            ticketType: '',
            unitPrice: 0,
            ticketStatus: '',
          ),
        );
      }
    }

    return tickets;
  }
}

class BillsPageResponse {
  final int total;
  final int page;
  final int limit;
  final List<BillModel> data;

  const BillsPageResponse({
    required this.total,
    required this.page,
    required this.limit,
    required this.data,
  });

  factory BillsPageResponse.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload = json;
    if (json['data'] is Map) {
      final inner = _asMap(json['data']);
      if (inner != null &&
          (inner['data'] is List ||
              inner['items'] is List ||
              inner['bills'] is List ||
              inner['results'] is List)) {
        payload = inner;
      }
    }

    final rawList = payload['data'] ??
        payload['items'] ??
        payload['bills'] ??
        payload['results'];
    final bills = <BillModel>[];

    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          bills.add(BillModel.fromJson(item));
        } else if (item is Map) {
          bills.add(BillModel.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return BillsPageResponse(
      total: _readInt(payload['total'], fallback: bills.length),
      page: _readInt(payload['page'], fallback: 1),
      limit: _readInt(payload['limit'], fallback: bills.length),
      data: bills,
    );
  }
}

Map<String, dynamic> _unwrapDataMap(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  return json;
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

DateTime? _tryParseDate(dynamic raw) {
  if (raw == null) {
    return null;
  }
  return DateTime.tryParse(raw.toString());
}
