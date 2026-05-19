import '../../domain/entities/station.dart';

class StationModel extends Station {
  const StationModel({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    required super.stationCode,
    required super.stationName,
    required super.latitude,
    required super.longitude,
    required super.condition,
    required super.stopCategory,
    required super.streetName,
    required super.addressNo,
    required super.hasWheelchair,
    required super.hasRamp,
    required super.stationType,
    required super.status,
  });

  factory StationModel.fromJson(Map<String, dynamic> json) {
    return StationModel(
      id: json['_id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      stationCode: json['stationCode'] as String,
      stationName: json['stationName'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      condition: json['condition'] as String,
      stopCategory: json['stopCategory'] as String,
      streetName: json['streetName'] as String,
      addressNo: json['addressNo'] as String,
      hasWheelchair: json['hasWheelchair'] as bool? ?? false,
      hasRamp: json['hasRamp'] as bool? ?? false,
      stationType: StationType.fromString(json['stationType'] as String),
      status: StationStatus.fromString(json['status'] as String),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'stationCode': stationCode,
      'stationName': stationName,
      'latitude': latitude,
      'longitude': longitude,
      'condition': condition,
      'stopCategory': stopCategory,
      'streetName': streetName,
      'addressNo': addressNo,
      'hasWheelchair': hasWheelchair,
      'hasRamp': hasRamp,
      'stationType': stationType.toJson(),
      'status': status.toJson(),
    };
  }

  Station toEntity() => this;
}

class StationListResponse {
  final int statusCode;
  final String message;
  final List<StationModel> data;
  final int? total;
  final int? page;
  final int? limit;
  const StationListResponse({
    required this.statusCode,
    required this.message,
    required this.data,
    this.total,
    this.page,
    this.limit,
  });
  factory StationListResponse.fromJson(Map<String, dynamic> json) {
    final payload = _unwrapDataMap(json);
    final stations = _extractStations(payload);
    return StationListResponse(
      statusCode:
          _readInt(json['statusCode'] ?? payload['statusCode'], fallback: 200),
      message: _readString(json['message'] ?? payload['message']),
      data: stations,
      total: _readOptionalInt(payload['total'] ?? payload['count']),
      page: _readOptionalInt(payload['page']),
      limit: _readOptionalInt(payload['limit']),
    );
  }
}

class StationResponse {
  final int statusCode;
  final String message;
  final StationModel data;
  const StationResponse({
    required this.statusCode,
    required this.message,
    required this.data,
  });
  factory StationResponse.fromJson(Map<String, dynamic> json) {
    final payload = _unwrapDataMap(json);
    final stationJson = _asMap(payload['station']) ?? payload;
    return StationResponse(
      statusCode:
          _readInt(json['statusCode'] ?? payload['statusCode'], fallback: 200),
      message: _readString(json['message'] ?? payload['message']),
      data: StationModel.fromJson(stationJson),
    );
  }
}

Map<String, dynamic> _unwrapDataMap(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map<String, dynamic>) {
    return data;
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

String _readString(dynamic raw, {String fallback = ''}) {
  if (raw == null) {
    return fallback;
  }
  if (raw is String) {
    return raw;
  }
  return raw.toString();
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
  return int.tryParse(raw.toString()) ?? fallback;
}

int? _readOptionalInt(dynamic raw) {
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse(raw.toString());
}

List<StationModel> _extractStations(Map<String, dynamic> json) {
  dynamic raw =
      json['stations'] ?? json['items'] ?? json['results'] ?? json['data'];

  if (raw is Map) {
    final map = Map<String, dynamic>.from(raw);
    raw = map['stations'] ?? map['items'] ?? map['results'] ?? map['data'];
  }

  if (raw is! List) {
    return const <StationModel>[];
  }

  return raw
      .whereType<Map<String, dynamic>>()
      .map(StationModel.fromJson)
      .toList();
}
