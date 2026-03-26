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
    );
  }

  static DateTime? _tryParseDate(dynamic raw) {
    if (raw == null) {
      return null;
    }

    final text = raw.toString();
    return DateTime.tryParse(text);
  }
}
