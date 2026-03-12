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
  const PathStationInfo({
    required this.stationCode,
    required this.stationName,
    required this.latitude,
    required this.longitude,
  });
  @override
  List<Object?> get props => [stationCode, stationName, latitude, longitude];
}

class PathResult extends Equatable {
  final List<PathStationInfo> stations;
  final List<PathRouteInfo> routes;
  final double totalDistance;
  final double totalTime;
  final double totalCost;
  final List<PathSegment> segments;
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
        transfers,
        optimizationScore,
        optimizationType,
      ];
  String get formattedTime {
    final minutes = totalTime.round();
    if (minutes < 60) {
      return '$minutes phút';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return remainingMinutes > 0
          ? '$hours giờ $remainingMinutes phút'
          : '$hours giờ';
    }
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

  int get numberOfTransfers => transfers ?? (routes.length - 1);
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
