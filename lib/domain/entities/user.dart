import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String email;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> favoriteRouteIds;
  final List<String> favoriteStationIds;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.createdAt,
    this.updatedAt,
    List<String>? favoriteRouteIds,
    List<String>? favoriteStationIds,
  })  : favoriteRouteIds = favoriteRouteIds ?? const [],
        favoriteStationIds = favoriteStationIds ?? const [];

  @override
  List<Object?> get props => [
        id,
        email,
        name,
        createdAt,
        updatedAt,
        favoriteRouteIds,
        favoriteStationIds,
      ];
}
