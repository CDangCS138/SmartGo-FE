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
    return StationListResponse(
      statusCode: json['statusCode'] as int,
      message: json['message'] as String,
      data: (json['data'] as List)
          .map((station) =>
              StationModel.fromJson(station as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int?,
      page: json['page'] as int?,
      limit: json['limit'] as int?,
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
    return StationResponse(
      statusCode: json['statusCode'] as int,
      message: json['message'] as String,
      data: StationModel.fromJson(json['data'] as Map<String, dynamic>),
    );
  }
}
