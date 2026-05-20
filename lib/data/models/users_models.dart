import 'route_model.dart';
import 'station_model.dart';

class UsersPageResponse {
  final int total;
  final int page;
  final int limit;
  final List<AdminUserModel> data;

  const UsersPageResponse({
    required this.total,
    required this.page,
    required this.limit,
    required this.data,
  });

  factory UsersPageResponse.fromJson(Map<String, dynamic> json) {
    final payload = _unwrapDataMap(json);
    final rawData = _extractUsersList(payload);
    final users = <AdminUserModel>[];

    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map<String, dynamic>) {
          users.add(AdminUserModel.fromJson(item));
        }
      }
    }

    return UsersPageResponse(
      total: _readInt(payload['total'] ?? payload['count'], users.length),
      page: _readInt(payload['page'], 1),
      limit: _readInt(payload['limit'], 10),
      data: users,
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

dynamic _extractUsersList(Map<String, dynamic> payload) {
  dynamic raw = payload['data'] ??
      payload['items'] ??
      payload['users'] ??
      payload['results'];

  if (raw is Map) {
    final map = Map<String, dynamic>.from(raw);
    raw = map['data'] ?? map['items'] ?? map['users'] ?? map['results'];
  }

  return raw;
}

int _readInt(dynamic raw, int fallback) {
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

class AdminUserModel {
  final String id;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String email;
  final String name;
  final String role;
  final String? avatar;
  final List<String> favoriteRouteIds;
  final List<String> favoriteStationIds;
  final List<RouteModel> favoriteRoutes;
  final List<StationModel> favoriteStations;

  const AdminUserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.avatar,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
    this.favoriteRouteIds = const [],
    this.favoriteStationIds = const [],
    this.favoriteRoutes = const [],
    this.favoriteStations = const [],
  });

  factory AdminUserModel.fromJson(Map<String, dynamic> json) {
    return AdminUserModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      createdAt: _tryParseDate(json['createdAt']),
      createdBy: json['createdBy']?.toString(),
      updatedAt: _tryParseDate(json['updatedAt']),
      updatedBy: json['updatedBy']?.toString(),
      email: (json['email'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      role: (json['role'] ?? 'member').toString(),
      avatar: json['avatar']?.toString(),
      favoriteRouteIds: _parseStringList(json['favoriteRouteIds']),
      favoriteStationIds: _parseStringList(json['favoriteStationIds']),
      favoriteRoutes: _parseRoutes(json['favoriteRoutes']),
      favoriteStations: _parseStations(json['favoriteStations']),
    );
  }

  static DateTime? _tryParseDate(dynamic raw) {
    if (raw == null) {
      return null;
    }

    final text = raw.toString();
    return DateTime.tryParse(text);
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toList();
    }
    return const <String>[];
  }

  static List<RouteModel> _parseRoutes(dynamic raw) {
    if (raw is! List) {
      return const <RouteModel>[];
    }

    final routes = <RouteModel>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        routes.add(RouteModel.fromJson(item));
      } else if (item is Map) {
        routes.add(RouteModel.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return routes;
  }

  static List<StationModel> _parseStations(dynamic raw) {
    if (raw is! List) {
      return const <StationModel>[];
    }

    final stations = <StationModel>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        stations.add(StationModel.fromJson(item));
      } else if (item is Map) {
        stations.add(StationModel.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return stations;
  }
}
