import 'package:equatable/equatable.dart';
import 'package:smartgo/domain/entities/path_finding.dart';

class FavoriteRouteModel extends Equatable {
  final String id;
  final String routeName;
  final String? fromStationCode;
  final String? toStationCode;
  final PathCoordinates? fromCoordinates;
  final PathCoordinates? toCoordinates;
  final String? userId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FavoriteRouteModel({
    required this.id,
    required this.routeName,
    this.fromStationCode,
    this.toStationCode,
    this.fromCoordinates,
    this.toCoordinates,
    this.userId,
    this.createdAt,
    this.updatedAt,
  });

  bool get usesStationCode {
    return (fromStationCode ?? '').isNotEmpty &&
        (toStationCode ?? '').isNotEmpty;
  }

  bool get usesCoordinates {
    return fromCoordinates != null && toCoordinates != null;
  }

  factory FavoriteRouteModel.fromJson(Map<String, dynamic> json) {
    final stationCode = _asMap(json['stationCode']);
    final coordinates = _asMap(json['coordinates']);

    final fromStationCode =
        stationCode?['from']?.toString() ?? json['fromStationCode']?.toString();
    final toStationCode =
        stationCode?['to']?.toString() ?? json['toStationCode']?.toString();

    final fromCoordinates = _parseCoordinates(
      coordinates?['from'] ?? json['fromCoordinates'],
    );
    final toCoordinates = _parseCoordinates(
      coordinates?['to'] ?? json['toCoordinates'],
    );

    return FavoriteRouteModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      routeName: (json['routeName'] ?? '').toString(),
      fromStationCode: fromStationCode,
      toStationCode: toStationCode,
      fromCoordinates: fromCoordinates,
      toCoordinates: toCoordinates,
      userId: json['userId']?.toString(),
      createdAt: _tryParseDate(json['createdAt']),
      updatedAt: _tryParseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'routeName': routeName,
    };

    if (usesStationCode) {
      payload['stationCode'] = {
        'from': fromStationCode,
        'to': toStationCode,
      };
    }

    if (usesCoordinates) {
      payload['coordinates'] = {
        'from': _coordinatesToJson(fromCoordinates!),
        'to': _coordinatesToJson(toCoordinates!),
      };
    }

    return payload;
  }

  @override
  List<Object?> get props => [
        id,
        routeName,
        fromStationCode,
        toStationCode,
        fromCoordinates,
        toCoordinates,
        userId,
        createdAt,
        updatedAt,
      ];

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static PathCoordinates? _parseCoordinates(dynamic raw) {
    final map = _asMap(raw);
    if (map == null) {
      return null;
    }

    final lat = map['latitude'] ?? map['lat'];
    final lon = map['longitude'] ?? map['lon'];
    if (lat == null || lon == null) {
      return null;
    }

    return PathCoordinates(
      latitude: (lat as num).toDouble(),
      longitude: (lon as num).toDouble(),
    );
  }

  static Map<String, dynamic> _coordinatesToJson(PathCoordinates coordinates) {
    return {
      'latitude': coordinates.latitude,
      'longitude': coordinates.longitude,
    };
  }

  static DateTime? _tryParseDate(dynamic raw) {
    if (raw == null) {
      return null;
    }

    return DateTime.tryParse(raw.toString());
  }
}

class FavoriteRoutesResponse extends Equatable {
  final int total;
  final int page;
  final int limit;
  final List<FavoriteRouteModel> data;

  const FavoriteRoutesResponse({
    required this.total,
    required this.page,
    required this.limit,
    required this.data,
  });

  factory FavoriteRoutesResponse.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload = json;
    if (json['data'] is Map) {
      final inner = FavoriteRouteModel._asMap(json['data']);
      if (inner != null &&
          (inner['data'] is List ||
              inner['items'] is List ||
              inner['favorites'] is List)) {
        payload = inner;
      }
    }

    final rawList = payload['data'] ?? payload['favorites'] ?? payload['items'];
    final favorites = <FavoriteRouteModel>[];

    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          favorites.add(FavoriteRouteModel.fromJson(item));
        } else if (item is Map) {
          favorites.add(
              FavoriteRouteModel.fromJson(Map<String, dynamic>.from(item)));
        } else if (item != null) {
          favorites.add(
            FavoriteRouteModel(
              id: item.toString(),
              routeName: item.toString(),
            ),
          );
        }
      }
    }

    return FavoriteRoutesResponse(
      total: (payload['total'] as num?)?.toInt() ?? favorites.length,
      page: (payload['page'] as num?)?.toInt() ?? 1,
      limit: (payload['limit'] as num?)?.toInt() ?? favorites.length,
      data: favorites,
    );
  }

  @override
  List<Object?> get props => [total, page, limit, data];
}
