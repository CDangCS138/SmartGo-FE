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
    final rawData = json['data'];
    final users = <AdminUserModel>[];

    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map<String, dynamic>) {
          users.add(AdminUserModel.fromJson(item));
        }
      }
    }

    return UsersPageResponse(
      total: (json['total'] as num?)?.toInt() ?? users.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 10,
      data: users,
    );
  }
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
}
