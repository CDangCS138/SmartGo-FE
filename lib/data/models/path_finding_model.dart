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
      'criteria': _normalizeRoutingCriteria(criteria),
      'numPaths': numPaths,
      'maxTransfers': maxTransfers,
      if (timeOfDay != null) 'timeOfDay': timeOfDay,
      'congestionAware': congestionAware,
    };
  }
}

String _normalizeRoutingCriteria(String raw) {
  final value = raw.trim().toLowerCase();

  switch (value) {
    case 'time':
    case 'fastest':
      return 'time';
    case 'cost':
    case 'cheapest':
      return 'cost';
    case 'distance':
    case 'shortest':
      return 'distance';
    case 'balanced':
      return 'balanced';
    default:
      return value;
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
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      routeCode: json['routeCode']?.toString() ?? '',
      routeName: json['routeName']?.toString() ?? '',
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
      routeCode: json['routeCode']?.toString() ?? '',
      routeName: json['routeName']?.toString() ?? '',
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

class PathCoordinatesModel extends PathCoordinates {
  const PathCoordinatesModel({
    required super.latitude,
    required super.longitude,
  });

  factory PathCoordinatesModel.fromJson(dynamic json) {
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return PathCoordinatesModel(
      latitude: ((map['latitude'] as num?) ?? 0).toDouble(),
      longitude: ((map['longitude'] as num?) ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class WalkingLegModel extends WalkingLeg {
  const WalkingLegModel({
    required super.type,
    required super.fromCoordinates,
    required super.toCoordinates,
    required super.stationCode,
    required super.stationName,
    super.fromStationCode,
    super.fromStationName,
    required super.distanceKm,
    required super.estimatedTimeMinutes,
  });

  factory WalkingLegModel.fromJson(Map<String, dynamic> json) {
    return WalkingLegModel(
      type: json['type']?.toString() ?? '',
      fromCoordinates: PathCoordinatesModel.fromJson(json['fromCoordinates']),
      toCoordinates: PathCoordinatesModel.fromJson(json['toCoordinates']),
      stationCode: json['stationCode']?.toString() ?? '',
      stationName: json['stationName']?.toString() ?? '',
      fromStationCode: json['fromStationCode']?.toString(),
      fromStationName: json['fromStationName']?.toString(),
      distanceKm: ((json['distanceKm'] as num?) ?? 0).toDouble(),
      estimatedTimeMinutes:
          ((json['estimatedTimeMinutes'] as num?) ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'fromCoordinates': (fromCoordinates is PathCoordinatesModel)
          ? (fromCoordinates as PathCoordinatesModel).toJson()
          : {
              'latitude': fromCoordinates.latitude,
              'longitude': fromCoordinates.longitude,
            },
      'toCoordinates': (toCoordinates is PathCoordinatesModel)
          ? (toCoordinates as PathCoordinatesModel).toJson()
          : {
              'latitude': toCoordinates.latitude,
              'longitude': toCoordinates.longitude,
            },
      'stationCode': stationCode,
      'stationName': stationName,
      if (fromStationCode != null) 'fromStationCode': fromStationCode,
      if (fromStationName != null) 'fromStationName': fromStationName,
      'distanceKm': distanceKm,
      'estimatedTimeMinutes': estimatedTimeMinutes,
    };
  }
}

class PathStationInfoModel extends PathStationInfo {
  const PathStationInfoModel({
    required super.stationCode,
    required super.stationName,
    required super.latitude,
    required super.longitude,
    super.accessPoint,
    super.snappedPoint,
    super.isInAlley,
    super.walkDistanceToAccessPointKm,
    super.walkTimeToAccessPointMinutes,
  });

  static PathCoordinatesModel? _parseOptionalCoordinates(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(raw);
    final hasLatitude = map['latitude'] is num;
    final hasLongitude = map['longitude'] is num;
    if (!hasLatitude || !hasLongitude) {
      return null;
    }

    return PathCoordinatesModel.fromJson(map);
  }

  factory PathStationInfoModel.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] is Map
        ? Map<String, dynamic>.from(json['coordinates'] as Map)
        : <String, dynamic>{};

    final accessPoint = _parseOptionalCoordinates(json['accessPoint']);
    final snappedPoint = _parseOptionalCoordinates(json['snappedPoint']);

    final walkDistanceRaw =
        (json['walkDistanceToAccessPointKm'] ?? json['walkDistanceKm']) as num?;
    final walkTimeRaw = (json['walkTimeToAccessPointMinutes'] ??
        json['walkTimeMinutes']) as num?;

    return PathStationInfoModel(
      stationCode: json['stationCode']?.toString() ?? '',
      stationName: json['stationName']?.toString() ?? '',
      latitude:
          ((coords['latitude'] ?? json['latitude']) as num?)?.toDouble() ?? 0,
      longitude:
          ((coords['longitude'] ?? json['longitude']) as num?)?.toDouble() ?? 0,
      accessPoint: accessPoint,
      snappedPoint: snappedPoint,
      isInAlley: (json['isInAlley'] as bool?) ?? false,
      walkDistanceToAccessPointKm: walkDistanceRaw?.toDouble(),
      walkTimeToAccessPointMinutes: walkTimeRaw?.toDouble(),
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
      if (accessPoint != null)
        'accessPoint': {
          'latitude': accessPoint!.latitude,
          'longitude': accessPoint!.longitude,
        },
      if (snappedPoint != null)
        'snappedPoint': {
          'latitude': snappedPoint!.latitude,
          'longitude': snappedPoint!.longitude,
        },
      'isInAlley': isInAlley,
      if (walkDistanceToAccessPointKm != null)
        'walkDistanceToAccessPointKm': walkDistanceToAccessPointKm,
      if (walkTimeToAccessPointMinutes != null)
        'walkTimeToAccessPointMinutes': walkTimeToAccessPointMinutes,
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
    super.walkingLegs,
    super.transitDistanceKm,
    super.transitTimeMinutes,
    super.totalWalkingDistanceKm,
    super.totalWalkingTimeMinutes,
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
      walkingLegs: (json['walkingLegs'] as List<dynamic>?)
              ?.map((e) => WalkingLegModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      transitDistanceKm: (json['transitDistanceKm'] as num?)?.toDouble(),
      transitTimeMinutes: (json['transitTimeMinutes'] as num?)?.toDouble(),
      totalWalkingDistanceKm:
          (json['totalWalkingDistanceKm'] as num?)?.toDouble(),
      totalWalkingTimeMinutes:
          (json['totalWalkingTimeMinutes'] as num?)?.toDouble(),
      transfers: (json['transfers'] as num?)?.toInt(),
      optimizationScore: (json['optimizationScore'] as num?)?.toDouble(),
      optimizationType: json['optimizationType'] as String?,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'stations': stations
          .map((s) => s is PathStationInfoModel
              ? s.toJson()
              : {
                  'stationCode': s.stationCode,
                  'stationName': s.stationName,
                  'coordinates': {
                    'latitude': s.latitude,
                    'longitude': s.longitude,
                  },
                  if (s.accessPoint != null)
                    'accessPoint': {
                      'latitude': s.accessPoint!.latitude,
                      'longitude': s.accessPoint!.longitude,
                    },
                  if (s.snappedPoint != null)
                    'snappedPoint': {
                      'latitude': s.snappedPoint!.latitude,
                      'longitude': s.snappedPoint!.longitude,
                    },
                  'isInAlley': s.isInAlley,
                  if (s.walkDistanceToAccessPointKm != null)
                    'walkDistanceToAccessPointKm':
                        s.walkDistanceToAccessPointKm,
                  if (s.walkTimeToAccessPointMinutes != null)
                    'walkTimeToAccessPointMinutes':
                        s.walkTimeToAccessPointMinutes,
                })
          .toList(),
      'routes': routes
          .map((r) => r is PathRouteInfoModel
              ? r.toJson()
              : {
                  'routeCode': r.routeCode,
                  'routeName': r.routeName,
                })
          .toList(),
      'totalDistance': totalDistance,
      'totalTime': totalTime,
      'totalCost': totalCost,
      'segments': segments
          .map((s) => s is PathSegmentModel
              ? s.toJson()
              : {
                  'from': s.from,
                  'to': s.to,
                  'routeCode': s.routeCode,
                  'routeName': s.routeName,
                  'distance': s.distance,
                  'time': s.time,
                  'cost': s.cost,
                })
          .toList(),
      'walkingLegs': walkingLegs
          .map((w) => w is WalkingLegModel
              ? w.toJson()
              : {
                  'type': w.type,
                  'fromCoordinates': {
                    'latitude': w.fromCoordinates.latitude,
                    'longitude': w.fromCoordinates.longitude,
                  },
                  'toCoordinates': {
                    'latitude': w.toCoordinates.latitude,
                    'longitude': w.toCoordinates.longitude,
                  },
                  'stationCode': w.stationCode,
                  'stationName': w.stationName,
                  if (w.fromStationCode != null)
                    'fromStationCode': w.fromStationCode,
                  if (w.fromStationName != null)
                    'fromStationName': w.fromStationName,
                  'distanceKm': w.distanceKm,
                  'estimatedTimeMinutes': w.estimatedTimeMinutes,
                })
          .toList(),
      if (transitDistanceKm != null) 'transitDistanceKm': transitDistanceKm,
      if (transitTimeMinutes != null) 'transitTimeMinutes': transitTimeMinutes,
      if (totalWalkingDistanceKm != null)
        'totalWalkingDistanceKm': totalWalkingDistanceKm,
      if (totalWalkingTimeMinutes != null)
        'totalWalkingTimeMinutes': totalWalkingTimeMinutes,
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
