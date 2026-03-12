import 'package:smartgo/domain/entities/path_finding.dart';

class LocationCoordinates {
  final double latitude;
  final double longitude;
  const LocationCoordinates({
    required this.latitude,
    required this.longitude,
  });
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory LocationCoordinates.fromJson(Map<String, dynamic> json) {
    return LocationCoordinates(
      latitude: ((json['latitude'] as num?) ?? 0).toDouble(),
      longitude: ((json['longitude'] as num?) ?? 0).toDouble(),
    );
  }
}

class StationCodePair {
  final String from;
  final String to;
  const StationCodePair({
    required this.from,
    required this.to,
  });
  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
    };
  }
}

class CoordinatesPair {
  final LocationCoordinates from;
  final LocationCoordinates to;
  const CoordinatesPair({
    required this.from,
    required this.to,
  });
  Map<String, dynamic> toJson() {
    return {
      'from': from.toJson(),
      'to': to.toJson(),
    };
  }
}

class PathRequest {
  final StationCodePair? stationCode;
  final CoordinatesPair? coordinates;
  final String criteria;
  final int numPaths;
  final int maxTransfers;
  final int? timeOfDay;
  final bool congestionAware;
  const PathRequest({
    this.stationCode,
    this.coordinates,
    required this.criteria,
    this.numPaths = 3,
    this.maxTransfers = 3,
    this.timeOfDay,
    this.congestionAware = true,
  }) : assert(
          stationCode != null || coordinates != null,
          'Either stationCode or coordinates must be provided',
        );
  Map<String, dynamic> toJson() {
    return {
      if (stationCode != null) 'stationCode': stationCode!.toJson(),
      if (coordinates != null) 'coordinates': coordinates!.toJson(),
      'criteria': criteria,
      'numPaths': numPaths,
      'maxTransfers': maxTransfers,
      if (timeOfDay != null) 'timeOfDay': timeOfDay,
      'congestionAware': congestionAware,
    };
  }
}

class PathSegmentModel extends PathSegment {
  const PathSegmentModel({
    required super.from,
    required super.to,
    required super.routeCode,
    required super.routeName,
    required super.distance,
    required super.time,
    required super.cost,
  });
  factory PathSegmentModel.fromJson(Map<String, dynamic> json) {
    return PathSegmentModel(
      from: json['from'] as String,
      to: json['to'] as String,
      routeCode: json['routeCode'] as String,
      routeName: json['routeName'] as String,
      distance: ((json['distance'] as num?) ?? 0).toDouble(),
      time: ((json['time'] as num?) ?? 0).toDouble(),
      cost: ((json['cost'] as num?) ?? 0).toDouble(),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
      'routeCode': routeCode,
      'routeName': routeName,
      'distance': distance,
      'time': time,
      'cost': cost,
    };
  }
}

class PathRouteInfoModel extends PathRouteInfo {
  const PathRouteInfoModel({
    required super.routeCode,
    required super.routeName,
  });
  factory PathRouteInfoModel.fromJson(Map<String, dynamic> json) {
    return PathRouteInfoModel(
      routeCode: json['routeCode'] as String,
      routeName: json['routeName'] as String,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'routeCode': routeCode,
      'routeName': routeName,
    };
  }
}

class StationCoordinatesModel {
  final double latitude;
  final double longitude;
  const StationCoordinatesModel({
    required this.latitude,
    required this.longitude,
  });
  factory StationCoordinatesModel.fromJson(Map<String, dynamic> json) {
    return StationCoordinatesModel(
      latitude: ((json['latitude'] as num?) ?? 0).toDouble(),
      longitude: ((json['longitude'] as num?) ?? 0).toDouble(),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class PathStationInfoModel extends PathStationInfo {
  const PathStationInfoModel({
    required super.stationCode,
    required super.stationName,
    required super.latitude,
    required super.longitude,
  });
  factory PathStationInfoModel.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] as Map<String, dynamic>? ?? {};
    return PathStationInfoModel(
      stationCode: json['stationCode'] as String,
      stationName: json['stationName'] as String,
      latitude: ((coords['latitude'] as num?) ?? 0).toDouble(),
      longitude: ((coords['longitude'] as num?) ?? 0).toDouble(),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'stationCode': stationCode,
      'stationName': stationName,
      'coordinates': {
        'latitude': latitude,
        'longitude': longitude,
      },
    };
  }
}

class PathResultModel extends PathResult {
  const PathResultModel({
    required super.stations,
    required super.routes,
    required super.totalDistance,
    required super.totalTime,
    required super.totalCost,
    required super.segments,
    super.transfers,
    super.optimizationScore,
    super.optimizationType,
  });
  factory PathResultModel.fromJson(Map<String, dynamic> json) {
    return PathResultModel(
      stations: (json['stations'] as List<dynamic>?)
              ?.map((e) =>
                  PathStationInfoModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      routes: (json['routes'] as List<dynamic>?)
              ?.map(
                  (e) => PathRouteInfoModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalDistance: ((json['totalDistance'] as num?) ?? 0).toDouble(),
      totalTime: ((json['totalTime'] as num?) ?? 0).toDouble(),
      totalCost: ((json['totalCost'] as num?) ?? 0).toDouble(),
      segments: (json['segments'] as List<dynamic>?)
              ?.map((e) => PathSegmentModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      transfers: json['transfers'] as int?,
      optimizationScore: (json['optimizationScore'] as num?)?.toDouble(),
      optimizationType: json['optimizationType'] as String?,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'stations':
          stations.map((s) => (s as PathStationInfoModel).toJson()).toList(),
      'routes': routes.map((r) => (r as PathRouteInfoModel).toJson()).toList(),
      'totalDistance': totalDistance,
      'totalTime': totalTime,
      'totalCost': totalCost,
      'segments':
          segments.map((s) => (s as PathSegmentModel).toJson()).toList(),
      if (transfers != null) 'transfers': transfers,
      if (optimizationScore != null) 'optimizationScore': optimizationScore,
      if (optimizationType != null) 'optimizationType': optimizationType,
    };
  }
}

class PathMetricsModel extends PathMetrics {
  const PathMetricsModel({
    required super.algorithm,
    required super.executionTimeMs,
    required super.nodesExplored,
    required super.explorationRatePercent,
    required super.heuristicUsed,
    required super.hasFallback,
    required super.cacheHit,
  });
  factory PathMetricsModel.fromJson(Map<String, dynamic> json) {
    return PathMetricsModel(
      algorithm: json['algorithm'] as String,
      executionTimeMs: (json['executionTimeMs'] as int?) ?? 0,
      nodesExplored: (json['nodesExplored'] as int?) ?? 0,
      explorationRatePercent:
          ((json['explorationRatePercent'] as num?) ?? 0).toDouble(),
      heuristicUsed: (json['heuristicUsed'] as bool?) ?? false,
      hasFallback: (json['hasFallback'] as bool?) ?? false,
      cacheHit: (json['cacheHit'] as bool?) ?? false,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'algorithm': algorithm,
      'executionTimeMs': executionTimeMs,
      'nodesExplored': nodesExplored,
      'explorationRatePercent': explorationRatePercent,
      'heuristicUsed': heuristicUsed,
      'hasFallback': hasFallback,
      'cacheHit': cacheHit,
    };
  }
}

class PathResponse {
  final List<PathResultModel> paths;
  final PathMetricsModel? metrics;
  final bool congestionApplied;
  final int? timeOfDay;
  const PathResponse({
    required this.paths,
    this.metrics,
    required this.congestionApplied,
    this.timeOfDay,
  });
  factory PathResponse.fromJson(Map<String, dynamic> json) {
    return PathResponse(
      paths: (json['paths'] as List<dynamic>?)
              ?.map((e) => PathResultModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      metrics: json['metrics'] != null
          ? PathMetricsModel.fromJson(json['metrics'] as Map<String, dynamic>)
          : null,
      congestionApplied: (json['congestionApplied'] as bool?) ?? false,
      timeOfDay: json['timeOfDay'] as int?,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'paths': paths.map((p) => p.toJson()).toList(),
      if (metrics != null) 'metrics': metrics!.toJson(),
      'congestionApplied': congestionApplied,
      if (timeOfDay != null) 'timeOfDay': timeOfDay,
    };
  }
}
