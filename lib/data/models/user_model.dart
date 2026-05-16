import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.email,
    required super.name,
    super.createdAt,
    super.updatedAt,
    super.favoriteRouteIds,
    super.favoriteStationIds,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] as String? ?? json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      favoriteRouteIds: _parseStringList(json['favoriteRouteIds']),
      favoriteStationIds: _parseStringList(json['favoriteStationIds']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'email': email,
      'name': name,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (favoriteRouteIds.isNotEmpty) 'favoriteRouteIds': favoriteRouteIds,
      if (favoriteStationIds.isNotEmpty)
        'favoriteStationIds': favoriteStationIds,
    };
  }

  User toEntity() => this;

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toList();
    }
    return const <String>[];
  }
}
