import 'package:equatable/equatable.dart';

class PathSegment extends Equatable {
  final String from;
  final String to;
  final String routeCode;
  final String routeName;
  final double distance;
  final double time;
  final double cost;
  const PathSegment({
    required this.from,
    required this.to,
    required this.routeCode,
    required this.routeName,
    required this.distance,
    required this.time,
    required this.cost,
  });
  @override
  List<Object?> get props =>
      [from, to, routeCode, routeName, distance, time, cost];
}

class PathRouteInfo extends Equatable {
  final String routeCode;
  final String routeName;
  const PathRouteInfo({
    required this.routeCode,
    required this.routeName,
  });
  @override
  List<Object?> get props => [routeCode, routeName];
}

class PathStationInfo extends Equatable {
  final String stationCode;
  final String stationName;
  final double latitude;
  final double longitude;
  final PathCoordinates? accessPoint;
  final PathCoordinates? snappedPoint;
  final bool isInAlley;
  final double? walkDistanceToAccessPointKm;
  final double? walkTimeToAccessPointMinutes;

  const PathStationInfo({
    required this.stationCode,
    required this.stationName,
    required this.latitude,
    required this.longitude,
    this.accessPoint,
    this.snappedPoint,
    this.isInAlley = false,
    this.walkDistanceToAccessPointKm,
    this.walkTimeToAccessPointMinutes,
  });

  PathCoordinates get stopCoordinate {
    return PathCoordinates(latitude: latitude, longitude: longitude);
  }

  PathCoordinates get busAccessCoordinate {
    return accessPoint ?? snappedPoint ?? stopCoordinate;
  }

  bool get hasAccessPoint => accessPoint != null || snappedPoint != null;

  double get accessWalkingDistanceKm => walkDistanceToAccessPointKm ?? 0;

  double get accessWalkingTimeMinutes {
    if (walkTimeToAccessPointMinutes != null) {
      return walkTimeToAccessPointMinutes!;
    }

    if (accessWalkingDistanceKm <= 0) {
      return 0;
    }

    // 5 km/h walking speed fallback.
    return (accessWalkingDistanceKm / 5) * 60;
  }

  PathStationInfo copyWith({
    String? stationCode,
    String? stationName,
    double? latitude,
    double? longitude,
    PathCoordinates? accessPoint,
    PathCoordinates? snappedPoint,
    bool? isInAlley,
    double? walkDistanceToAccessPointKm,
    double? walkTimeToAccessPointMinutes,
    bool clearAccessPoint = false,
    bool clearSnappedPoint = false,
    bool clearWalkDistanceToAccessPointKm = false,
    bool clearWalkTimeToAccessPointMinutes = false,
  }) {
    return PathStationInfo(
      stationCode: stationCode ?? this.stationCode,
      stationName: stationName ?? this.stationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accessPoint: clearAccessPoint ? null : (accessPoint ?? this.accessPoint),
      snappedPoint:
          clearSnappedPoint ? null : (snappedPoint ?? this.snappedPoint),
      isInAlley: isInAlley ?? this.isInAlley,
      walkDistanceToAccessPointKm: clearWalkDistanceToAccessPointKm
          ? null
          : (walkDistanceToAccessPointKm ?? this.walkDistanceToAccessPointKm),
      walkTimeToAccessPointMinutes: clearWalkTimeToAccessPointMinutes
          ? null
          : (walkTimeToAccessPointMinutes ?? this.walkTimeToAccessPointMinutes),
    );
  }

  @override
  List<Object?> get props => [
        stationCode,
        stationName,
        latitude,
        longitude,
        accessPoint,
        snappedPoint,
        isInAlley,
        walkDistanceToAccessPointKm,
        walkTimeToAccessPointMinutes,
      ];
}

class PathCoordinates extends Equatable {
  final double latitude;
  final double longitude;

  const PathCoordinates({
    required this.latitude,
    required this.longitude,
  });

  @override
  List<Object?> get props => [latitude, longitude];
}

class WalkingLeg extends Equatable {
  final String type;
  final PathCoordinates fromCoordinates;
  final PathCoordinates toCoordinates;
  final String stationCode;
  final String stationName;
  final String? fromStationCode;
  final String? fromStationName;
  final double distanceKm;
  final double estimatedTimeMinutes;

  const WalkingLeg({
    required this.type,
    required this.fromCoordinates,
    required this.toCoordinates,
    required this.stationCode,
    required this.stationName,
    this.fromStationCode,
    this.fromStationName,
    required this.distanceKm,
    required this.estimatedTimeMinutes,
  });

  String get normalizedType => type.trim().toLowerCase();

  bool get isTransfer => normalizedType == 'transfer';

  bool get isToFirstStation => normalizedType == 'to_first_station';

  bool get isFromLastStation => normalizedType == 'from_last_station';

  String get displayType {
    switch (normalizedType) {
      case 'to_first_station':
        return 'Đi bộ đến trạm lên xe';
      case 'from_last_station':
        return 'Đi bộ từ trạm cuối đến đích';
      case 'transfer':
        return 'Đi bộ chuyển tuyến';
      case 'station_access':
        return 'Đi bộ từ đường chính vào trạm';
      default:
        return 'Đi bộ';
    }
  }

  @override
  List<Object?> get props => [
        type,
        fromCoordinates,
        toCoordinates,
        stationCode,
        stationName,
        fromStationCode,
        fromStationName,
        distanceKm,
        estimatedTimeMinutes,
      ];
}

class PathResult extends Equatable {
  final List<PathStationInfo> stations;
  final List<PathRouteInfo> routes;
  final double totalDistance;
  final double totalTime;
  final double totalCost;
  final List<PathSegment> segments;
  final List<WalkingLeg> walkingLegs;
  final double? transitDistanceKm;
  final double? transitTimeMinutes;
  final double? totalWalkingDistanceKm;
  final double? totalWalkingTimeMinutes;
  final int? transfers;
  final double? optimizationScore;
  final String? optimizationType;

  const PathResult({
    required this.stations,
    required this.routes,
    required this.totalDistance,
    required this.totalTime,
    required this.totalCost,
    required this.segments,
    this.walkingLegs = const [],
    this.transitDistanceKm,
    this.transitTimeMinutes,
    this.totalWalkingDistanceKm,
    this.totalWalkingTimeMinutes,
    this.transfers,
    this.optimizationScore,
    this.optimizationType,
  });
  @override
  List<Object?> get props => [
        stations,
        routes,
        totalDistance,
        totalTime,
        totalCost,
        segments,
        walkingLegs,
        transitDistanceKm,
        transitTimeMinutes,
        totalWalkingDistanceKm,
        totalWalkingTimeMinutes,
        transfers,
        optimizationScore,
        optimizationType,
      ];

  String get formattedTime {
    return _formatMinutes(totalTime);
  }

  String get formattedDistance {
    return '${totalDistance.toStringAsFixed(1)} km';
  }

  String get formattedCost {
    return '${totalCost.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        )} đ';
  }

  double get walkingDistanceKm {
    if (totalWalkingDistanceKm != null) {
      return totalWalkingDistanceKm!;
    }
    return walkingLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.distanceKm,
    );
  }

  double get walkingTimeMinutes {
    if (totalWalkingTimeMinutes != null) {
      return totalWalkingTimeMinutes!;
    }
    return walkingLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.estimatedTimeMinutes,
    );
  }

  String get formattedWalkingDistance {
    return '${walkingDistanceKm.toStringAsFixed(1)} km';
  }

  String get formattedWalkingTime {
    return _formatMinutes(walkingTimeMinutes);
  }

  bool get hasWalkingLegs {
    return walkingLegs.isNotEmpty ||
        walkingDistanceKm > 0 ||
        walkingTimeMinutes > 0;
  }

  int get numberOfTransfers =>
      transfers ?? (routes.length > 1 ? routes.length - 1 : 0);

  List<WalkingLeg> get stationAccessWalkingLegs {
    final legs = <WalkingLeg>[];

    for (final station in stations) {
      if (!station.isInAlley || station.accessWalkingDistanceKm <= 0) {
        continue;
      }

      legs.add(
        WalkingLeg(
          type: 'station_access',
          fromCoordinates: station.busAccessCoordinate,
          toCoordinates: station.stopCoordinate,
          stationCode: station.stationCode,
          stationName: station.stationName,
          distanceKm: station.accessWalkingDistanceKm,
          estimatedTimeMinutes: station.accessWalkingTimeMinutes,
        ),
      );
    }

    return legs;
  }

  bool get hasStationAccessWalkingLegs => stationAccessWalkingLegs.isNotEmpty;

  List<WalkingLeg> get allWalkingLegs => [
        ...walkingLegs,
        ...stationAccessWalkingLegs,
      ];

  PathResult copyWith({
    List<PathStationInfo>? stations,
    List<PathRouteInfo>? routes,
    double? totalDistance,
    double? totalTime,
    double? totalCost,
    List<PathSegment>? segments,
    List<WalkingLeg>? walkingLegs,
    double? transitDistanceKm,
    double? transitTimeMinutes,
    double? totalWalkingDistanceKm,
    double? totalWalkingTimeMinutes,
    int? transfers,
    double? optimizationScore,
    String? optimizationType,
    bool clearTransitDistanceKm = false,
    bool clearTransitTimeMinutes = false,
    bool clearTotalWalkingDistanceKm = false,
    bool clearTotalWalkingTimeMinutes = false,
    bool clearTransfers = false,
    bool clearOptimizationScore = false,
    bool clearOptimizationType = false,
  }) {
    return PathResult(
      stations: stations ?? this.stations,
      routes: routes ?? this.routes,
      totalDistance: totalDistance ?? this.totalDistance,
      totalTime: totalTime ?? this.totalTime,
      totalCost: totalCost ?? this.totalCost,
      segments: segments ?? this.segments,
      walkingLegs: walkingLegs ?? this.walkingLegs,
      transitDistanceKm: clearTransitDistanceKm
          ? null
          : (transitDistanceKm ?? this.transitDistanceKm),
      transitTimeMinutes: clearTransitTimeMinutes
          ? null
          : (transitTimeMinutes ?? this.transitTimeMinutes),
      totalWalkingDistanceKm: clearTotalWalkingDistanceKm
          ? null
          : (totalWalkingDistanceKm ?? this.totalWalkingDistanceKm),
      totalWalkingTimeMinutes: clearTotalWalkingTimeMinutes
          ? null
          : (totalWalkingTimeMinutes ?? this.totalWalkingTimeMinutes),
      transfers: clearTransfers ? null : (transfers ?? this.transfers),
      optimizationScore: clearOptimizationScore
          ? null
          : (optimizationScore ?? this.optimizationScore),
      optimizationType: clearOptimizationType
          ? null
          : (optimizationType ?? this.optimizationType),
    );
  }

  String _formatMinutes(double minutesValue) {
    final minutes = minutesValue.round();
    if (minutes < 60) {
      return '$minutes phút';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes > 0
        ? '$hours giờ $remainingMinutes phút'
        : '$hours giờ';
  }
}

class PathMetrics extends Equatable {
  final String algorithm;
  final int executionTimeMs;
  final int nodesExplored;
  final double explorationRatePercent;
  final bool heuristicUsed;
  final bool hasFallback;
  final bool cacheHit;
  const PathMetrics({
    required this.algorithm,
    required this.executionTimeMs,
    required this.nodesExplored,
    required this.explorationRatePercent,
    required this.heuristicUsed,
    required this.hasFallback,
    required this.cacheHit,
  });
  @override
  List<Object?> get props => [
        algorithm,
        executionTimeMs,
        nodesExplored,
        explorationRatePercent,
        heuristicUsed,
        hasFallback,
        cacheHit,
      ];
}

// ignore_for_file: constant_identifier_names

enum PathOptimizationType {
  fastest('fastest', 'Nhanh nhất'),
  cheapest('cheapest', 'Rẻ nhất'),
  shortest('shortest', 'Ngắn nhất'),
  balanced('balanced', 'Cân bằng');

  final String value;
  final String displayName;
  const PathOptimizationType(this.value, this.displayName);
  static PathOptimizationType? fromString(String? value) {
    if (value == null) return null;
    return PathOptimizationType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => PathOptimizationType.balanced,
    );
  }
}

enum PathAlgorithm {
  astar('astar', 'A*'),
  dijkstra('dijkstra', 'Dijkstra'),
  bfs('bfs', 'BFS'),
  dfs('dfs', 'DFS');

  final String value;
  final String displayName;
  const PathAlgorithm(this.value, this.displayName);
  static PathAlgorithm fromString(String value) {
    return PathAlgorithm.values.firstWhere(
      (algo) => algo.value == value,
      orElse: () => PathAlgorithm.astar,
    );
  }
}

enum RoutingCriteria {
  TIME('TIME', 'Nhanh nhất'),
  COST('COST', 'Rẻ nhất'),
  DISTANCE('DISTANCE', 'Ngắn nhất'),
  BALANCED('BALANCED', 'Cân bằng');

  final String value;
  final String displayName;
  const RoutingCriteria(this.value, this.displayName);
  static RoutingCriteria fromString(String value) {
    return RoutingCriteria.values.firstWhere(
      (criteria) => criteria.value == value.toUpperCase(),
      orElse: () => RoutingCriteria.BALANCED,
    );
  }
}

enum OptimizationCriteria {
  distance('distance', 'Khoảng cách'),
  time('time', 'Thời gian'),
  cost('cost', 'Chi phí');

  final String value;
  final String displayName;
  const OptimizationCriteria(this.value, this.displayName);
  static OptimizationCriteria fromString(String value) {
    return OptimizationCriteria.values.firstWhere(
      (criteria) => criteria.value == value,
      orElse: () => OptimizationCriteria.distance,
    );
  }
}
