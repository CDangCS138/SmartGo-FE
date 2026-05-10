import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:latlong2/latlong.dart';
import '../logging/app_logger.dart';

class TransitStationAccessPoint {
  final LatLng stopCoordinate;
  final LatLng busAccessCoordinate;
  final LatLng? snappedRoadCoordinate;
  final bool isInAlley;
  final double walkDistanceToAccessPointKm;
  final double walkTimeToAccessPointMinutes;

  const TransitStationAccessPoint({
    required this.stopCoordinate,
    required this.busAccessCoordinate,
    this.snappedRoadCoordinate,
    required this.isInAlley,
    required this.walkDistanceToAccessPointKm,
    required this.walkTimeToAccessPointMinutes,
  });
}

class TransitGeometryResult {
  final List<TransitStationAccessPoint> stationAccessPoints;
  final List<LatLng> drivingWaypoints;
  final List<LatLng> transitGeometry;

  const TransitGeometryResult({
    required this.stationAccessPoints,
    required this.drivingWaypoints,
    required this.transitGeometry,
  });
}

class _NearestRoadCandidate {
  final LatLng point;
  final double distanceMeters;

  const _NearestRoadCandidate({
    required this.point,
    required this.distanceMeters,
  });
}

class _SegmentAlignment {
  final double lateralDistanceMeters;
  final double projectionRatio;

  const _SegmentAlignment({
    required this.lateralDistanceMeters,
    required this.projectionRatio,
  });
}


/// Service to get actual route geometry from routing engines
@lazySingleton
class RouteGeometryService {
  final Dio _dio;
  final Distance _distance = const Distance();
  final Map<String, List<_NearestRoadCandidate>> _nearestCandidatesCache = {};
  final Map<String, Future<List<_NearestRoadCandidate>>> _nearestInFlight = {};
  final Map<String, List<LatLng>> _routeGeometryCache = {};
  final Map<String, Future<List<LatLng>>> _routeGeometryInFlight = {};
  final Map<String, List<LatLng>> _matchGeometryCache = {};
  final Map<String, Future<List<LatLng>>> _matchGeometryInFlight = {};
  final Map<String, List<LatLng>> _walkingGeometryCache = {};
  final Map<String, Future<List<LatLng>>> _walkingGeometryInFlight = {};
  final Map<String, DateTime> _nearestFailureBackoff = {};
  int _osrmRouteRequestCount = 0;
  int _osrmMatchRequestCount = 0;
  int _osrmNearestRequestCount = 0;
  int _osrmWalkingRequestCount = 0;
  DateTime? _lastOsrmStatsLogAt;
  DateTime? _nearestTemporarilyDisabledUntil;
  DateTime? _matchTemporarilyDisabledUntil;
  DateTime? _nearestLastFailureAt;
  DateTime? _lastNearestFailureLogAt;
  DateTime? _lastRouteErrorLogAt;
  int _nearestFailureBurstCount = 0;

  RouteGeometryService(this._dio);

  static const String _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving/';
  static const String _osrmMatchBaseUrl =
      'https://router.project-osrm.org/match/v1/driving/';
  static const String _osrmWalkingBaseUrl =
      'https://router.project-osrm.org/route/v1/walking/';
  static const String _osrmNearestBaseUrl =
      'https://router.project-osrm.org/nearest/v1/driving/';
  static const int _fastModeStationThreshold = 20;
  static const int _fastModeMaxWaypointsPerRequest = 18;
  static const int _maxMatchCoordinatesPerRequest = 12;
  static const int _directMatchThreshold = 10;
  static const int _matchChunkSize = 10;
  static const int _matchChunkOverlap = 2;
  static const int _matchSecondaryChunkSize = 8;
  static const int _matchSecondaryChunkOverlap = 1;
  static const int _matchRouteFirstThreshold = 16;
  static const int _hybridBaseMaxLocalMatchPatches = 3;
  static const int _hybridAbsoluteMaxLocalMatchPatches = 5;
  static const double _maxWaypointDeviationFromGeometryMeters = 180;
  static const double _minSnapDistanceMeters = 8;
  static const double _alleyDistanceThresholdMeters = 35;
  static const double _maxSnapDistanceMeters = 280;
  static const double _directionOutlierMinSnapMeters = 14;
  static const double _directionOutlierLateralMeters = 95;
  static const double _directionOutlierStretchRatio = 1.7;
  static const double _walkingSpeedKmPerHour = 5;
  static const int _nearestRequestBatchSize = 4;
  static const String _routeCacheSchemaVersion = 'v4_hybrid_route_match';
  static const Duration _nearestFailureBackoffDuration = Duration(minutes: 3);
  static const Duration _nearestFailureBurstWindow = Duration(seconds: 20);
  static const int _nearestFailureBurstThreshold = 3;
  static const Duration _nearestDisableDuration = Duration(minutes: 2);
  static const Duration _matchDisableDurationOnTooBig = Duration(minutes: 2);
  static const Duration _failureLogThrottle = Duration(seconds: 8);
  static const Duration _osrmStatsLogThrottle = Duration(seconds: 20);

  Map<String, int> getOsrmRequestStatsSnapshot() {
    return <String, int>{
      'route': _osrmRouteRequestCount,
      'match': _osrmMatchRequestCount,
      'nearest': _osrmNearestRequestCount,
      'walking': _osrmWalkingRequestCount,
    };
  }

  void _recordOsrmRequest(String type) {
    switch (type) {
      case 'route':
        _osrmRouteRequestCount += 1;
        break;
      case 'match':
        _osrmMatchRequestCount += 1;
        break;
      case 'nearest':
        _osrmNearestRequestCount += 1;
        break;
      case 'walking':
        _osrmWalkingRequestCount += 1;
        break;
      default:
        return;
    }

    final now = DateTime.now();
    final lastLoggedAt = _lastOsrmStatsLogAt;
    if (lastLoggedAt != null &&
        now.difference(lastLoggedAt) < _osrmStatsLogThrottle) {
      return;
    }

    _lastOsrmStatsLogAt = now;
    AppLogger.info(
      'OSRM stats route=$_osrmRouteRequestCount match=$_osrmMatchRequestCount nearest=$_osrmNearestRequestCount walking=$_osrmWalkingRequestCount',
    );
  }

  Future<TransitGeometryResult> buildTransitGeometryWithAccessPoints(
    List<LatLng> stopCoordinates, {
    int maxWaypointsPerRequest = 25,
    int nearestCandidates = 3,
    void Function(List<LatLng> refinedGeometry)? onGeometryRefined,
  }) async {
    if (stopCoordinates.isEmpty) {
      return const TransitGeometryResult(
        stationAccessPoints: [],
        drivingWaypoints: [],
        transitGeometry: [],
      );
    }

    var resolvedNearestCandidates = nearestCandidates;
    if (resolvedNearestCandidates < 1) {
      resolvedNearestCandidates = 1;
    }
    if (resolvedNearestCandidates > 5) {
      resolvedNearestCandidates = 5;
    }

    if (stopCoordinates.length >= _fastModeStationThreshold) {
      final fallbackAccessPoints = stopCoordinates
          .map(
            (stop) => TransitStationAccessPoint(
              stopCoordinate: stop,
              busAccessCoordinate: stop,
              isInAlley: false,
              walkDistanceToAccessPointKm: 0,
              walkTimeToAccessPointMinutes: 0,
            ),
          )
          .toList(growable: false);

      final dedupedWaypoints = _dedupeConsecutiveWaypoints(stopCoordinates);
      final filteredWaypoints =
          _filterDirectionalOutlierWaypoints(dedupedWaypoints);
      final routeWaypoints = filteredWaypoints.length >= 2
          ? filteredWaypoints
          : dedupedWaypoints;

      // Phase 1: get route immediately for display.
      final geometry = await _getRouteGeometryBatchedWithoutSnapping(
        routeWaypoints,
        maxWaypointsPerRequest: _fastModeMaxWaypointsPerRequest,
      );

      // Phase 2: schedule background match refinement for difficult segments.
      if (onGeometryRefined != null && routeWaypoints.length >= 3) {
        _scheduleGeometryRefinement(
          geometry,
          routeWaypoints,
          onGeometryRefined,
        );
      }

      return TransitGeometryResult(
        stationAccessPoints: fallbackAccessPoints,
        drivingWaypoints: stopCoordinates,
        transitGeometry: geometry,
      );
    }

    final candidatesPerStation = List<List<_NearestRoadCandidate>>.filled(
      stopCoordinates.length,
      const <_NearestRoadCandidate>[],
    );

    for (var startIndex = 0;
        startIndex < stopCoordinates.length;
        startIndex += _nearestRequestBatchSize) {
      final endIndex =
          (startIndex + _nearestRequestBatchSize < stopCoordinates.length)
              ? startIndex + _nearestRequestBatchSize
              : stopCoordinates.length;

      final batchStops = stopCoordinates.sublist(startIndex, endIndex);
      final batchResults = await Future.wait(
        batchStops.map(
          (stop) => _fetchNearestDrivableCandidates(
            stop,
            number: resolvedNearestCandidates,
          ),
        ),
      );

      for (var batchIndex = 0; batchIndex < batchResults.length; batchIndex++) {
        candidatesPerStation[startIndex + batchIndex] =
            batchResults[batchIndex];
      }
    }

    final accessPoints = <TransitStationAccessPoint>[];
    for (var i = 0; i < stopCoordinates.length; i++) {
      accessPoints.add(
        _resolveAccessPoint(
          stop: stopCoordinates[i],
          previousStop: i > 0 ? stopCoordinates[i - 1] : null,
          nextStop:
              i < stopCoordinates.length - 1 ? stopCoordinates[i + 1] : null,
          candidates: candidatesPerStation[i],
        ),
      );
    }

    final stabilizedAccessPoints =
        _stabilizeDirectionOutlierAccessPoints(accessPoints);

    final drivingWaypoints = stabilizedAccessPoints
        .map((accessPoint) => accessPoint.busAccessCoordinate)
        .toList(growable: false);
    final dedupedDrivingWaypoints =
        _dedupeConsecutiveWaypoints(drivingWaypoints);
    final filteredRoutingWaypoints =
        _filterDirectionalOutlierWaypoints(dedupedDrivingWaypoints);
    final routingWaypoints = filteredRoutingWaypoints.length >= 2
        ? filteredRoutingWaypoints
        : dedupedDrivingWaypoints;

    var geometry = await getDrivingGeometryPreferMatch(
      routingWaypoints,
    );
    if (_isSamePointSequence(geometry, routingWaypoints)) {
      geometry = await _getRouteGeometryBatchedWithoutSnapping(
        routingWaypoints,
        maxWaypointsPerRequest: maxWaypointsPerRequest,
      );
    }

    // Schedule background match refinement for normal mode too.
    if (onGeometryRefined != null && routingWaypoints.length >= 3) {
      _scheduleGeometryRefinement(
        geometry,
        routingWaypoints,
        onGeometryRefined,
      );
    }

    return TransitGeometryResult(
      stationAccessPoints: stabilizedAccessPoints,
      drivingWaypoints: drivingWaypoints,
      transitGeometry: geometry,
    );
  }

  /// Get route geometry using OSRM (free, no API key needed)
  /// Returns list of LatLng points that follow actual roads
  Future<List<LatLng>> getRouteGeometry(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      return waypoints;
    }

    final result = await buildTransitGeometryWithAccessPoints(waypoints);
    if (result.transitGeometry.isNotEmpty) {
      return result.transitGeometry;
    }

    return result.drivingWaypoints;
  }

  Future<List<LatLng>> getWalkingGeometry({
    required LatLng from,
    required LatLng to,
  }) async {
    if (_distanceMeters(from, to) < 5) {
      return <LatLng>[from, to];
    }

    final directWaypoints = <LatLng>[from, to];
    final cacheKey = _buildRouteCacheKey(
      directWaypoints,
      profile: 'walking',
    );
    final cached = _walkingGeometryCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final inFlight = _walkingGeometryInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final requestFuture = () async {
      try {
        _recordOsrmRequest('walking');
        final walkingResponse =
            await _dio.getUri(_buildWalkingRouteUri(from, to));
        final walkingPoints = _extractRoutePoints(walkingResponse.data);
        if (walkingPoints != null && walkingPoints.length >= 2) {
          _walkingGeometryCache[cacheKey] = walkingPoints;
          return walkingPoints;
        }
      } catch (_) {
        // Some public OSRM deployments do not expose walking profile.
      }

      try {
        _recordOsrmRequest('route');
        final drivingResponse = await _dio.getUri(
            _buildRouteUri(directWaypoints, useStrictDrivingHints: false));
        final drivingPoints = _extractRoutePoints(drivingResponse.data);
        if (drivingPoints != null && drivingPoints.length >= 2) {
          _walkingGeometryCache[cacheKey] = drivingPoints;
          return drivingPoints;
        }
      } catch (_) {
        // Fallback to direct line when route provider is unavailable.
      }

      _walkingGeometryCache[cacheKey] = directWaypoints;
      return directWaypoints;
    }();

    _walkingGeometryInFlight[cacheKey] = requestFuture;
    try {
      return await requestFuture;
    } finally {
      _walkingGeometryInFlight.remove(cacheKey);
    }
  }

  Uri _buildNearestUri(LatLng coordinate, {int number = 5}) {
    final nearestPath = '${coordinate.longitude},${coordinate.latitude}';
    return Uri.parse('$_osrmNearestBaseUrl$nearestPath').replace(
      queryParameters: {
        'number': number.toString(),
      },
    );
  }

  Future<List<_NearestRoadCandidate>> _fetchNearestDrivableCandidates(
    LatLng stop, {
    int number = 5,
  }) async {
    final now = DateTime.now();
    if (_isNearestTemporarilyDisabled(now)) {
      return const [];
    }

    final key =
        '${stop.latitude.toStringAsFixed(6)},${stop.longitude.toStringAsFixed(6)}#$number';
    final cached = _nearestCandidatesCache[key];
    if (cached != null) {
      return cached;
    }

    final inFlight = _nearestInFlight[key];
    if (inFlight != null) {
      return inFlight;
    }

    final failedAt = _nearestFailureBackoff[key];
    if (failedAt != null) {
      if (now.difference(failedAt) < _nearestFailureBackoffDuration) {
        return const [];
      }
      _nearestFailureBackoff.remove(key);
    }

    final requestFuture = () async {
      try {
        _recordOsrmRequest('nearest');
        final response =
            await _dio.getUri(_buildNearestUri(stop, number: number));
        final data = response.data;
        if (data is! Map<String, dynamic> || data['code'] != 'Ok') {
          _recordNearestFailure(key, 'Invalid nearest response payload');
          return const <_NearestRoadCandidate>[];
        }

        final waypoints = data['waypoints'];
        if (waypoints is! List) {
          _recordNearestFailure(key, 'Nearest response missing waypoints list');
          return const <_NearestRoadCandidate>[];
        }

        final candidates = <_NearestRoadCandidate>[];
        for (final waypoint in waypoints) {
          if (waypoint is! Map<String, dynamic>) {
            continue;
          }

          final location = waypoint['location'];
          if (location is! List || location.length < 2) {
            continue;
          }

          final lon = (location[0] as num?)?.toDouble();
          final lat = (location[1] as num?)?.toDouble();
          if (lon == null || lat == null) {
            continue;
          }

          final distanceMeters =
              ((waypoint['distance'] as num?) ?? double.infinity).toDouble();
          candidates.add(
            _NearestRoadCandidate(
              point: LatLng(lat, lon),
              distanceMeters: distanceMeters,
            ),
          );
        }

        _nearestCandidatesCache[key] = candidates;
        _nearestFailureBackoff.remove(key);
        _nearestFailureBurstCount = 0;
        _nearestLastFailureAt = null;
        return candidates;
      } catch (e) {
        _recordNearestFailure(key, e);
        return const <_NearestRoadCandidate>[];
      }
    }();

    _nearestInFlight[key] = requestFuture;
    try {
      return await requestFuture;
    } finally {
      _nearestInFlight.remove(key);
    }
  }

  bool _isNearestTemporarilyDisabled(DateTime now) {
    final disabledUntil = _nearestTemporarilyDisabledUntil;
    if (disabledUntil == null) {
      return false;
    }

    if (now.isAfter(disabledUntil)) {
      _nearestTemporarilyDisabledUntil = null;
      return false;
    }

    return true;
  }

  void _recordNearestFailure(String key, Object reason) {
    final now = DateTime.now();
    _nearestFailureBackoff[key] = now;

    if (_nearestLastFailureAt != null &&
        now.difference(_nearestLastFailureAt!) <= _nearestFailureBurstWindow) {
      _nearestFailureBurstCount += 1;
    } else {
      _nearestFailureBurstCount = 1;
    }
    _nearestLastFailureAt = now;

    final shouldDisableNearest =
        _nearestFailureBurstCount >= _nearestFailureBurstThreshold;
    if (shouldDisableNearest) {
      _nearestTemporarilyDisabledUntil = now.add(_nearestDisableDuration);
      _nearestFailureBurstCount = 0;
      _nearestLastFailureAt = null;
      _logNearestWarning(
        'OSRM nearest is unstable. Temporarily skipping road snapping for 2 minutes.',
      );
      return;
    }

    _logNearestWarning('Unable to snap station to road: $reason');
  }

  void _logNearestWarning(String message) {
    final now = DateTime.now();
    final lastLoggedAt = _lastNearestFailureLogAt;
    if (lastLoggedAt != null &&
        now.difference(lastLoggedAt) < _failureLogThrottle) {
      return;
    }

    _lastNearestFailureLogAt = now;
    AppLogger.warning(message);
  }

  void _logRouteError(Object error) {
    final now = DateTime.now();
    final lastLoggedAt = _lastRouteErrorLogAt;
    if (lastLoggedAt != null &&
        now.difference(lastLoggedAt) < _failureLogThrottle) {
      return;
    }

    _lastRouteErrorLogAt = now;
    AppLogger.error('Error fetching route geometry: $error');
  }

  TransitStationAccessPoint _resolveAccessPoint({
    required LatLng stop,
    required LatLng? previousStop,
    required LatLng? nextStop,
    required List<_NearestRoadCandidate> candidates,
  }) {
    if (candidates.isEmpty) {
      return TransitStationAccessPoint(
        stopCoordinate: stop,
        busAccessCoordinate: stop,
        isInAlley: false,
        walkDistanceToAccessPointKm: 0,
        walkTimeToAccessPointMinutes: 0,
      );
    }

    final bestCandidate = _pickBestCandidate(
      stop: stop,
      previousStop: previousStop,
      nextStop: nextStop,
      candidates: candidates,
    );

    final canUseSnappedRoad =
        bestCandidate.distanceMeters <= _maxSnapDistanceMeters;
    final candidateAlignment = _segmentAlignmentMeters(
      segmentStart: previousStop,
      point: bestCandidate.point,
      segmentEnd: nextStop,
    );
    final candidateStretchRatio = _pathStretchRatio(
      previousStop,
      bestCandidate.point,
      nextStop,
    );
    final isDirectionOutlier = _isDirectionOutlierCandidate(
      snapDistanceMeters: bestCandidate.distanceMeters,
      alignment: candidateAlignment,
      stretchRatio: candidateStretchRatio,
    );

    final shouldMoveToAccessPoint = canUseSnappedRoad &&
        bestCandidate.distanceMeters >= _minSnapDistanceMeters &&
        !isDirectionOutlier;
    final walkDistanceKm =
        shouldMoveToAccessPoint ? bestCandidate.distanceMeters / 1000.0 : 0.0;

    return TransitStationAccessPoint(
      stopCoordinate: stop,
      busAccessCoordinate: shouldMoveToAccessPoint ? bestCandidate.point : stop,
      snappedRoadCoordinate: canUseSnappedRoad ? bestCandidate.point : null,
      isInAlley: shouldMoveToAccessPoint &&
          bestCandidate.distanceMeters >= _alleyDistanceThresholdMeters,
      walkDistanceToAccessPointKm: walkDistanceKm,
      walkTimeToAccessPointMinutes: _estimateWalkingMinutes(walkDistanceKm),
    );
  }

  _NearestRoadCandidate _pickBestCandidate({
    required LatLng stop,
    required LatLng? previousStop,
    required LatLng? nextStop,
    required List<_NearestRoadCandidate> candidates,
  }) {
    var selected = candidates.first;
    var bestScore = double.infinity;

    for (final candidate in candidates) {
      final corridorPenalty = _corridorPenaltyMeters(
        previousStop: previousStop,
        nextStop: nextStop,
        candidate: candidate.point,
      );

      final alignment = _segmentAlignmentMeters(
        segmentStart: previousStop,
        point: candidate.point,
        segmentEnd: nextStop,
      );
      final stretchRatio =
          _pathStretchRatio(previousStop, candidate.point, nextStop);

      var projectionPenalty = 0.0;
      if (alignment.projectionRatio < -0.08) {
        projectionPenalty = (alignment.projectionRatio.abs() + 0.08) * 220;
      } else if (alignment.projectionRatio > 1.08) {
        projectionPenalty = (alignment.projectionRatio - 1.08) * 220;
      }

      final stretchPenalty =
          stretchRatio > 1.35 ? (stretchRatio - 1.35) * 210 : 0.0;

      final lateralPenalty = alignment.lateralDistanceMeters * 0.7;

      final score = candidate.distanceMeters +
          (corridorPenalty * 0.5) +
          lateralPenalty +
          stretchPenalty +
          projectionPenalty;
      if (score < bestScore) {
        bestScore = score;
        selected = candidate;
      }
    }

    return selected;
  }

  double _corridorPenaltyMeters({
    required LatLng? previousStop,
    required LatLng? nextStop,
    required LatLng candidate,
  }) {
    if (previousStop == null || nextStop == null) {
      return 0;
    }

    final direct = _distanceMeters(previousStop, nextStop);
    final throughCandidate = _distanceMeters(previousStop, candidate) +
        _distanceMeters(candidate, nextStop);
    final extra = throughCandidate - direct;

    return extra > 0 ? extra : 0;
  }

  List<TransitStationAccessPoint> _stabilizeDirectionOutlierAccessPoints(
    List<TransitStationAccessPoint> accessPoints,
  ) {
    if (accessPoints.length < 3) {
      return accessPoints;
    }

    final stabilized = List<TransitStationAccessPoint>.from(accessPoints);

    for (var index = 1; index < stabilized.length - 1; index++) {
      final current = stabilized[index];
      final snapDistanceMeters =
          _distanceMeters(current.stopCoordinate, current.busAccessCoordinate);
      if (snapDistanceMeters < _directionOutlierMinSnapMeters) {
        continue;
      }

      final previousPoint = stabilized[index - 1].busAccessCoordinate;
      final nextPoint = stabilized[index + 1].busAccessCoordinate;
      final alignment = _segmentAlignmentMeters(
        segmentStart: previousPoint,
        point: current.busAccessCoordinate,
        segmentEnd: nextPoint,
      );
      final stretchRatio = _pathStretchRatio(
          previousPoint, current.busAccessCoordinate, nextPoint);

      final isOutlier = _isDirectionOutlierCandidate(
        snapDistanceMeters: snapDistanceMeters,
        alignment: alignment,
        stretchRatio: stretchRatio,
      );

      if (!isOutlier) {
        continue;
      }

      stabilized[index] = TransitStationAccessPoint(
        stopCoordinate: current.stopCoordinate,
        busAccessCoordinate: current.stopCoordinate,
        snappedRoadCoordinate: null,
        isInAlley: false,
        walkDistanceToAccessPointKm: 0,
        walkTimeToAccessPointMinutes: 0,
      );
    }

    return stabilized;
  }

  bool _isDirectionOutlierCandidate({
    required double snapDistanceMeters,
    required _SegmentAlignment alignment,
    required double stretchRatio,
  }) {
    if (snapDistanceMeters < _directionOutlierMinSnapMeters) {
      return false;
    }

    final hasLargeLateralDetour =
        alignment.lateralDistanceMeters >= _directionOutlierLateralMeters &&
            stretchRatio >= 1.42;
    final hasStrongStretch = stretchRatio >= _directionOutlierStretchRatio;
    final isOutOfOrder = (alignment.projectionRatio < -0.12 ||
            alignment.projectionRatio > 1.12) &&
        stretchRatio >= 1.35;

    return hasLargeLateralDetour || hasStrongStretch || isOutOfOrder;
  }

  _SegmentAlignment _segmentAlignmentMeters({
    required LatLng? segmentStart,
    required LatLng point,
    required LatLng? segmentEnd,
  }) {
    if (segmentStart == null || segmentEnd == null) {
      return const _SegmentAlignment(
        lateralDistanceMeters: 0,
        projectionRatio: 0.5,
      );
    }

    final a = _distanceMeters(segmentStart, point);
    final b = _distanceMeters(point, segmentEnd);
    final c = _distanceMeters(segmentStart, segmentEnd);
    if (c <= 0.5) {
      return _SegmentAlignment(
        lateralDistanceMeters: a < b ? a : b,
        projectionRatio: 0.5,
      );
    }

    final along = ((a * a) - (b * b) + (c * c)) / (2 * c);
    final clampedAlong = along.clamp(0.0, c);

    double lateralSquared;
    if (along < 0) {
      lateralSquared = a * a;
    } else if (along > c) {
      lateralSquared = b * b;
    } else {
      lateralSquared = (a * a) - (clampedAlong * clampedAlong);
    }
    if (lateralSquared < 0) {
      lateralSquared = 0;
    }

    return _SegmentAlignment(
      lateralDistanceMeters: math.sqrt(lateralSquared),
      projectionRatio: along / c,
    );
  }

  double _pathStretchRatio(
    LatLng? previous,
    LatLng current,
    LatLng? next,
  ) {
    if (previous == null || next == null) {
      return 1;
    }

    final direct = _distanceMeters(previous, next);
    if (direct <= 0.5) {
      return 1;
    }

    final through =
        _distanceMeters(previous, current) + _distanceMeters(current, next);
    return through / direct;
  }

  double _distanceMeters(LatLng a, LatLng b) {
    return _distance.as(LengthUnit.Meter, a, b);
  }

  double _estimateWalkingMinutes(double distanceKm) {
    if (distanceKm <= 0) {
      return 0;
    }

    return (distanceKm / _walkingSpeedKmPerHour) * 60;
  }

  List<LatLng> _dedupeConsecutiveWaypoints(List<LatLng> waypoints) {
    if (waypoints.isEmpty) {
      return const [];
    }

    final deduped = <LatLng>[waypoints.first];
    for (final point in waypoints.skip(1)) {
      final previous = deduped.last;
      if (_distanceMeters(previous, point) >= 3) {
        deduped.add(point);
      }
    }

    return deduped;
  }

  String _buildRouteCacheKey(
    List<LatLng> waypoints, {
    required String profile,
  }) {
    final compact = waypoints
        .map(
          (point) =>
              '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}',
        )
        .join(';');
    return '$_routeCacheSchemaVersion|$profile|$compact';
  }

  Future<List<LatLng>> _getRouteGeometryBatchedWithoutSnapping(
    List<LatLng> drivingWaypoints, {
    int maxWaypointsPerRequest = 25,
  }) async {
    if (drivingWaypoints.length < 2) {
      return drivingWaypoints;
    }

    final safeMaxWaypointsPerRequest =
        maxWaypointsPerRequest < 2 ? 2 : maxWaypointsPerRequest;

    if (drivingWaypoints.length <= safeMaxWaypointsPerRequest) {
      return _getRouteGeometryFromDrivingWaypoints(drivingWaypoints);
    }

    final allRoutePoints = <LatLng>[];
    for (int i = 0;
        i < drivingWaypoints.length - 1;
        i += safeMaxWaypointsPerRequest - 1) {
      final endIndex =
          (i + safeMaxWaypointsPerRequest < drivingWaypoints.length)
              ? i + safeMaxWaypointsPerRequest
              : drivingWaypoints.length;

      final chunk = drivingWaypoints.sublist(i, endIndex);
      final segmentPoints = await _getRouteGeometryFromDrivingWaypoints(chunk);

      if (i == 0) {
        allRoutePoints.addAll(segmentPoints);
      } else {
        allRoutePoints.addAll(segmentPoints.skip(1));
      }
    }

    return allRoutePoints;
  }

  Future<List<LatLng>> _getRouteGeometryFromDrivingWaypoints(
    List<LatLng> waypoints,
  ) async {
    return _getRouteGeometryFromDrivingWaypointsWithHints(
      waypoints,
      useStrictDrivingHints: false,
    );
  }

  Future<List<LatLng>> _getRouteGeometryFromDrivingWaypointsWithHints(
    List<LatLng> waypoints, {
    required bool useStrictDrivingHints,
  }) async {
    if (waypoints.length < 2) {
      return waypoints;
    }

    final cacheProfile = useStrictDrivingHints ? 'driving-strict' : 'driving';
    final cacheKey = _buildRouteCacheKey(waypoints, profile: cacheProfile);
    final cached = _routeGeometryCache[cacheKey];
    if (cached != null &&
        cached.isNotEmpty &&
        !_isSamePointSequence(cached, waypoints)) {
      return cached;
    }

    final inFlight = _routeGeometryInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final requestFuture = () async {
      try {
        AppLogger.info(useStrictDrivingHints
            ? 'Fetching route geometry from OSRM (strict)...'
            : 'Fetching route geometry from OSRM...');

        _recordOsrmRequest('route');
        final response = await _dio.getUri(
          _buildRouteUri(
            waypoints,
            useStrictDrivingHints: useStrictDrivingHints,
          ),
        );
        final routePoints = _extractRoutePoints(response.data);
        if (routePoints != null &&
            !_isSamePointSequence(routePoints, waypoints)) {
          _routeGeometryCache[cacheKey] = routePoints;
          AppLogger.info(
              'Route geometry fetched: ${routePoints.length} points');
          return routePoints;
        }

        if (routePoints != null) {
          AppLogger.warning(
              'Route geometry identical to raw waypoints; skip cache to retry later');
          return routePoints;
        }

        AppLogger.warning('Failed to get route geometry, using waypoints');
        return waypoints;
      } catch (e) {
        _logRouteError(e);
        // Fallback to direct waypoints if routing fails
        return waypoints;
      }
    }();

    _routeGeometryInFlight[cacheKey] = requestFuture;
    try {
      return await requestFuture;
    } finally {
      _routeGeometryInFlight.remove(cacheKey);
    }
  }

  Future<List<LatLng>> getDrivingGeometryPreferMatch(
    List<LatLng> drivingWaypoints, {
    int maxCoordinatesPerRequest = _maxMatchCoordinatesPerRequest,
  }) async {
    if (drivingWaypoints.length < 2) {
      return drivingWaypoints;
    }

    final deduped = _dedupeConsecutiveWaypoints(drivingWaypoints);
    if (deduped.length < 2) {
      return deduped;
    }

    final directionalStable = _filterDirectionalOutlierWaypoints(deduped);
    if (directionalStable.length < 2) {
      return deduped;
    }

    if (directionalStable.length >= _matchRouteFirstThreshold) {
      return _getRouteGeometryBatchedWithoutSnapping(
        directionalStable,
      );
    }

    final now = DateTime.now();
    if (_isMatchTemporarilyDisabled(now)) {
      if (directionalStable.length <= _maxMatchCoordinatesPerRequest) {
        _matchTemporarilyDisabledUntil = null;
      } else {
        return _getRouteGeometryBatchedWithoutSnapping(
          directionalStable,
        );
      }
    }

    final cacheKey =
        _buildRouteCacheKey(directionalStable, profile: 'driving-match');
    final cached = _matchGeometryCache[cacheKey];
    if (cached != null &&
        cached.isNotEmpty &&
        !_isSamePointSequence(cached, directionalStable)) {
      return cached;
    }

    final inFlight = _matchGeometryInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final requestFuture = () async {
      var effectiveMaxCoordinates = maxCoordinatesPerRequest;
      if (effectiveMaxCoordinates > _maxMatchCoordinatesPerRequest) {
        effectiveMaxCoordinates = _maxMatchCoordinatesPerRequest;
      }
      if (effectiveMaxCoordinates < 8) {
        effectiveMaxCoordinates = 8;
      }

      final interpolationStepMeters = directionalStable.length >= 18
          ? 95.0
          : (directionalStable.length >= 10 ? 78.0 : 62.0);
      final interpolated = _interpolateWaypointsForMatching(
        directionalStable,
        stepMeters: interpolationStepMeters,
      );
      final baseRequestPoints = interpolated.length <= effectiveMaxCoordinates
          ? interpolated
          : _compressWaypoints(interpolated, effectiveMaxCoordinates);

      List<LatLng>? matchedPoints;

      if (baseRequestPoints.length > _directMatchThreshold) {
        matchedPoints = await _tryMatchInChunks(
          baseRequestPoints,
          chunkSize: _matchChunkSize,
          overlap: _matchChunkOverlap,
          radiusScale: 0.44,
        );

        if (matchedPoints == null || matchedPoints.length < 2) {
          matchedPoints = await _tryMatchInChunks(
            baseRequestPoints,
            chunkSize: _matchSecondaryChunkSize,
            overlap: _matchSecondaryChunkOverlap,
            radiusScale: 0.36,
          );
        }
      }

      if ((matchedPoints == null || matchedPoints.length < 2) &&
          !_isMatchTemporarilyDisabled(DateTime.now())) {
        var requestPoints = baseRequestPoints.length > _directMatchThreshold
            ? _compressWaypoints(baseRequestPoints, _directMatchThreshold)
            : baseRequestPoints;
        var radiusScale = 0.52;

        for (var attempt = 0; attempt < 3; attempt++) {
          matchedPoints = await _tryMatchCall(
            requestPoints,
            radiusScale: radiusScale,
            logOnError: attempt >= 1,
          );
          if (matchedPoints != null && matchedPoints.length >= 2) {
            break;
          }

          if (requestPoints.length > 6) {
            final nextCap = requestPoints.length > 8 ? 8 : 6;
            requestPoints = _compressWaypoints(requestPoints, nextCap);
          }
          radiusScale *= 0.78;
        }
      }

      if (matchedPoints != null && matchedPoints.length >= 2) {
        final cleaned = _collapseShortDetourLoops(matchedPoints);
        final result = cleaned.length >= 2 ? cleaned : matchedPoints;

        final followsAnchors = _geometryCoversWaypoints(
          result,
          directionalStable,
          maxDeviationMeters: _maxWaypointDeviationFromGeometryMeters,
        );
        if (!followsAnchors) {
          final routedFallback =
              await _getRouteGeometryBatchedWithoutSnapping(
            directionalStable,
          );
          if (!_isSamePointSequence(routedFallback, directionalStable)) {
            _matchGeometryCache[cacheKey] = routedFallback;
          }
          return routedFallback;
        }

        if (!_isSamePointSequence(result, directionalStable)) {
          _matchGeometryCache[cacheKey] = result;
        }
        return result;
      }

      return _getRouteGeometryBatchedWithoutSnapping(
        directionalStable,
      );
    }();

    _matchGeometryInFlight[cacheKey] = requestFuture;
    try {
      return await requestFuture;
    } finally {
      _matchGeometryInFlight.remove(cacheKey);
    }
  }

  List<LatLng> _filterDirectionalOutlierWaypoints(List<LatLng> waypoints) {
    if (waypoints.length < 3) {
      return waypoints;
    }

    final filtered = <LatLng>[waypoints.first];
    for (var index = 1; index < waypoints.length - 1; index++) {
      final previous = filtered.last;
      final current = waypoints[index];
      final next = waypoints[index + 1];

      final prevCurrent = _distanceMeters(previous, current);
      final currentNext = _distanceMeters(current, next);
      final prevNext = _distanceMeters(previous, next);
      if (prevCurrent <= 0.5 || currentNext <= 0.5 || prevNext <= 0.5) {
        filtered.add(current);
        continue;
      }

      final localWindow = prevCurrent <= 420 && currentNext <= 420;
      if (!localWindow) {
        filtered.add(current);
        continue;
      }

      final alignment = _segmentAlignmentMeters(
        segmentStart: previous,
        point: current,
        segmentEnd: next,
      );
      final stretchRatio = (prevCurrent + currentNext) / prevNext;

      final hasLargeLateralDetour =
          alignment.lateralDistanceMeters >= _directionOutlierLateralMeters &&
              stretchRatio >= 1.5;
      final hasStrongStretch = stretchRatio >= 1.85;
      final isOutOfOrder = (alignment.projectionRatio < -0.15 ||
              alignment.projectionRatio > 1.15) &&
          stretchRatio >= 1.4;

      if (hasLargeLateralDetour || hasStrongStretch || isOutOfOrder) {
        continue;
      }

      filtered.add(current);
    }

    filtered.add(waypoints.last);
    return _dedupeConsecutiveWaypoints(filtered);
  }

  // ---------------------------------------------------------------------------
  // Phase 2: Background geometry refinement
  // ---------------------------------------------------------------------------

  /// Schedules background match-based refinement for the given route geometry.
  /// Runs asynchronously after the route has already been returned to the UI.
  void _scheduleGeometryRefinement(
    List<LatLng> routeGeometry,
    List<LatLng> waypoints,
    void Function(List<LatLng> refinedGeometry) onRefined,
  ) {
    refineRouteGeometry(routeGeometry, waypoints).then((refined) {
      if (refined != null && !_isSamePointSequence(refined, routeGeometry)) {
        onRefined(refined);
      }
    }).catchError((_) {
      // Silently ignore — the original route geometry is still valid.
    });
  }

  /// Analyzes [routeGeometry] for segments that are likely on the wrong
  /// parallel road, then uses OSRM match to correct them.
  ///
  /// Smart detection: looks for **consecutive runs** of waypoints that are
  /// all offset from the route by 40m+ (parallel road signal), rather than
  /// checking individual points.
  ///
  /// Returns the improved geometry, or `null` if no improvement was needed.
  Future<List<LatLng>?> refineRouteGeometry(
    List<LatLng> routeGeometry,
    List<LatLng> waypoints,
  ) async {
    if (routeGeometry.length < 2 || waypoints.length < 3) {
      return null;
    }

    final segments = _detectProblematicSegments(routeGeometry, waypoints);
    if (segments.isEmpty) {
      return null;
    }

    // Cap segments so we don't overwhelm OSRM.
    final maxSegments = math.max(
      _hybridBaseMaxLocalMatchPatches,
      math.min(_hybridAbsoluteMaxLocalMatchPatches, waypoints.length ~/ 5),
    );
    final effectiveSegments = segments.length <= maxSegments
        ? segments
        : segments.sublist(0, maxSegments);

    AppLogger.info(
      'Detected ${effectiveSegments.length} problematic segment(s) for match refinement',
    );

    // Fire all match calls in parallel — each is a small, independent request.
    final matchResults = await Future.wait(
      effectiveSegments.map(
        (segment) => _fetchLocalMatchGeometry(segment),
      ),
    );

    // Apply validated patches sequentially (fast, local-only computation).
    var patchedGeometry = routeGeometry;
    var patchedCount = 0;

    for (var i = 0; i < effectiveSegments.length; i++) {
      final localMatch = matchResults[i];
      if (localMatch == null || localMatch.length < 2) {
        continue;
      }

      final segmentWaypoints = effectiveSegments[i];

      final coversAnchors = _geometryCoversWaypoints(
        localMatch,
        segmentWaypoints,
        maxDeviationMeters: _maxWaypointDeviationFromGeometryMeters,
      );
      if (!coversAnchors) {
        continue;
      }

      final merged = _mergeGeometryPatch(
        baseGeometry: patchedGeometry,
        patchGeometry: localMatch,
        fromAnchor: segmentWaypoints.first,
        toAnchor: segmentWaypoints.last,
      );
      if (_isSamePointSequence(merged, patchedGeometry)) {
        continue;
      }

      patchedGeometry = merged;
      patchedCount += 1;
    }

    if (patchedCount <= 0) {
      return null;
    }

    final coversAll = _geometryCoversWaypoints(
      patchedGeometry,
      waypoints,
      maxDeviationMeters: _maxWaypointDeviationFromGeometryMeters,
    );
    if (!coversAll) {
      return null;
    }

    AppLogger.info(
      'Background refinement applied $patchedCount match patches',
    );
    return patchedGeometry;
  }

  /// Smart detection: finds groups of consecutive waypoints that are offset
  /// from the route geometry, indicating the route went on the wrong road.
  ///
  /// Returns a list of waypoint sub-lists, each representing a segment that
  /// should be re-matched.
  ///
  /// Detection rules:
  /// - **Run detection**: 2+ consecutive waypoints with deviation >= 40m
  ///   → strong parallel road signal (e.g. highway vs frontage road)
  /// - **High individual deviation**: single waypoint with deviation >= 120m
  ///   → clearly on the wrong road
  /// - Each segment includes 1 anchor waypoint before and after for context.
  List<List<LatLng>> _detectProblematicSegments(
    List<LatLng> routeGeometry,
    List<LatLng> waypoints,
  ) {
    if (waypoints.length < 3 || routeGeometry.length < 2) {
      return const <List<LatLng>>[];
    }

    // Step 1: Compute deviation of each waypoint from the route.
    final deviations = List<double>.generate(
      waypoints.length,
      (i) => _distancePointToPolylineMeters(waypoints[i], routeGeometry),
    );

    // Step 2: Find runs of consecutive deviating waypoints.
    const minRunDeviation = 40.0; // Minimum deviation to be part of a run
    const minSingleDeviation = 120.0; // Single-point threshold
    const minRunLength = 2; // 2+ consecutive = parallel road signal

    final segments = <List<LatLng>>[];
    var runStart = -1;

    for (var i = 0; i < waypoints.length; i++) {
      final isDeviating = deviations[i] >= minRunDeviation;

      if (isDeviating) {
        if (runStart == -1) runStart = i;
      }

      if (!isDeviating || i == waypoints.length - 1) {
        if (runStart >= 0) {
          final runEnd = isDeviating ? i + 1 : i;
          final runLength = runEnd - runStart;
          final maxDevInRun = deviations
              .sublist(runStart, runEnd)
              .reduce(math.max);

          final isSignificant = runLength >= minRunLength ||
              maxDevInRun >= minSingleDeviation;

          if (isSignificant) {
            // Add 1 anchor waypoint before and after for match context.
            final windowStart = math.max(0, runStart - 1);
            final windowEnd = math.min(waypoints.length, runEnd + 1);
            final segmentWaypoints =
                waypoints.sublist(windowStart, windowEnd);
            if (segmentWaypoints.length >= 2) {
              segments.add(segmentWaypoints);
            }
          }
          runStart = -1;
        }
      }
    }

    // Step 3: Merge overlapping segments.
    if (segments.length <= 1) {
      return segments;
    }

    final merged = <List<LatLng>>[segments.first];
    for (var i = 1; i < segments.length; i++) {
      final prev = merged.last;
      final curr = segments[i];
      // If last point of previous is close to first point of current, merge.
      if (_distanceMeters(prev.last, curr.first) < 50) {
        merged[merged.length - 1] = [
          ...prev,
          ...curr.skip(1),
        ];
      } else {
        merged.add(curr);
      }
    }

    return merged;
  }

  /// Fetches match geometry for a local waypoint window.
  /// Tries match once — if it fails, accepts the route as-is.
  /// Designed to be lightweight and safe to run in parallel.
  Future<List<LatLng>?> _fetchLocalMatchGeometry(
    List<LatLng> localWaypoints,
  ) async {
    // Single match attempt with reasonable radius.  _tryMatchCall already
    // retries internally without bearings if the first try is too strict.
    final localMatch = await _tryMatchCall(
      localWaypoints,
      radiusScale: 0.5,
    );
    if (localMatch != null && localMatch.length >= 2) {
      return localMatch;
    }

    return null;
  }


  int _findNearestPolylineIndex(
    List<LatLng> polyline,
    LatLng anchor, {
    int startIndex = 0,
  }) {
    if (polyline.isEmpty) {
      return -1;
    }

    var safeStartIndex = startIndex;
    if (safeStartIndex < 0) {
      safeStartIndex = 0;
    }
    if (safeStartIndex >= polyline.length) {
      return -1;
    }

    var bestIndex = -1;
    var bestDistance = double.infinity;
    for (var i = safeStartIndex; i < polyline.length; i++) {
      final distance = _distanceMeters(polyline[i], anchor);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  List<LatLng> _mergeGeometryPatch({
    required List<LatLng> baseGeometry,
    required List<LatLng> patchGeometry,
    required LatLng fromAnchor,
    required LatLng toAnchor,
  }) {
    if (baseGeometry.length < 2 || patchGeometry.length < 2) {
      return baseGeometry;
    }

    final startIndex = _findNearestPolylineIndex(baseGeometry, fromAnchor);
    if (startIndex == -1) {
      return baseGeometry;
    }

    final endIndex = _findNearestPolylineIndex(
      baseGeometry,
      toAnchor,
      startIndex: startIndex,
    );
    if (endIndex == -1 || endIndex <= startIndex) {
      return baseGeometry;
    }

    final startDistance = _distanceMeters(baseGeometry[startIndex], fromAnchor);
    final endDistance = _distanceMeters(baseGeometry[endIndex], toAnchor);
    const maxAnchorSnapMeters = _maxWaypointDeviationFromGeometryMeters * 1.4;
    if (startDistance > maxAnchorSnapMeters ||
        endDistance > maxAnchorSnapMeters) {
      return baseGeometry;
    }

    final merged = <LatLng>[];
    merged.addAll(baseGeometry.sublist(0, startIndex + 1));

    var patchStart = 0;
    if (merged.isNotEmpty &&
        _distanceMeters(merged.last, patchGeometry.first) <= 12) {
      patchStart = 1;
    }
    merged.addAll(patchGeometry.skip(patchStart));

    final tail = baseGeometry.sublist(endIndex + 1);
    if (tail.isNotEmpty && merged.isNotEmpty) {
      if (_distanceMeters(merged.last, tail.first) <= 12) {
        merged.addAll(tail.skip(1));
      } else {
        merged.addAll(tail);
      }
    }

    return _dedupeConsecutiveWaypoints(merged);
  }

  bool _geometryCoversWaypoints(
    List<LatLng> geometry,
    List<LatLng> waypoints, {
    required double maxDeviationMeters,
  }) {
    if (geometry.length < 2 || waypoints.isEmpty) {
      return true;
    }

    for (final waypoint in waypoints) {
      final deviationMeters =
          _distancePointToPolylineMeters(waypoint, geometry);
      if (deviationMeters > maxDeviationMeters) {
        return false;
      }
    }

    return true;
  }

  double _distancePointToPolylineMeters(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) {
      return double.infinity;
    }
    if (polyline.length == 1) {
      return _distanceMeters(point, polyline.first);
    }

    var minDistance = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      final candidate = _distancePointToSegmentMeters(
        point: point,
        segmentStart: polyline[i],
        segmentEnd: polyline[i + 1],
      );
      if (candidate < minDistance) {
        minDistance = candidate;
      }
    }

    return minDistance;
  }

  double _distancePointToSegmentMeters({
    required LatLng point,
    required LatLng segmentStart,
    required LatLng segmentEnd,
  }) {
    const metersPerDegreeLat = 110540.0;
    const metersPerDegreeLonAtEquator = 111320.0;

    final averageLatitudeRadians =
        ((segmentStart.latitude + segmentEnd.latitude + point.latitude) / 3) *
            (math.pi / 180);
    final lonScale =
        metersPerDegreeLonAtEquator * math.cos(averageLatitudeRadians).abs();

    const startX = 0.0;
    const startY = 0.0;
    final endX = (segmentEnd.longitude - segmentStart.longitude) * lonScale;
    final endY =
        (segmentEnd.latitude - segmentStart.latitude) * metersPerDegreeLat;
    final pointX = (point.longitude - segmentStart.longitude) * lonScale;
    final pointY =
        (point.latitude - segmentStart.latitude) * metersPerDegreeLat;

    final segmentLengthSquared = ((endX - startX) * (endX - startX)) +
        ((endY - startY) * (endY - startY));
    if (segmentLengthSquared == 0) {
      final dx = pointX - startX;
      final dy = pointY - startY;
      return math.sqrt((dx * dx) + (dy * dy));
    }

    final projection = (((pointX - startX) * (endX - startX)) +
            ((pointY - startY) * (endY - startY))) /
        segmentLengthSquared;
    final t = projection.clamp(0.0, 1.0);

    final closestX = startX + ((endX - startX) * t);
    final closestY = startY + ((endY - startY) * t);
    final dx = pointX - closestX;
    final dy = pointY - closestY;

    return math.sqrt((dx * dx) + (dy * dy));
  }

  Future<List<LatLng>?> _tryMatchCall(
    List<LatLng> points, {
    required double radiusScale,
    bool logOnError = false,
  }) async {
    if (points.length < 2) {
      return null;
    }

    final now = DateTime.now();
    if (_isMatchTemporarilyDisabled(now)) {
      if (points.length <= _maxMatchCoordinatesPerRequest) {
        _matchTemporarilyDisabledUntil = null;
      } else {
        return null;
      }
    }

    if (_shouldSkipMatchRequest(points, radiusScale: radiusScale)) {
      return null;
    }

    try {
      _recordOsrmRequest('match');
      final response = await _dio.getUri(
        _buildMatchUri(
          points,
          radiusScale: radiusScale,
        ),
      );
      final matchedWithBearings = _extractMatchPoints(response.data);
      if (matchedWithBearings != null && matchedWithBearings.length >= 2) {
        return matchedWithBearings;
      }

      // Retry once without directional constraints if matching was too strict.
      _recordOsrmRequest('match');
      final fallbackResponse = await _dio.getUri(
        _buildMatchUri(
          points,
          radiusScale: radiusScale,
          includeBearings: false,
        ),
      );
      return _extractMatchPoints(fallbackResponse.data);
    } catch (e) {
      final isTooBig = _isTooBigMatchError(e);
      if (isTooBig) {
        if (points.length <= 6) {
          _matchTemporarilyDisabledUntil =
              DateTime.now().add(_matchDisableDurationOnTooBig);
        }

        if (logOnError) {
          AppLogger.warning(
            'OSRM match TooBig for ${points.length} points. Retrying with smaller chunks.',
          );
        }
        return null;
      }

      if (logOnError) {
        _logRouteError('OSRM match failed: $e');
      }
      return null;
    }
  }

  bool _isMatchTemporarilyDisabled(DateTime now) {
    final disabledUntil = _matchTemporarilyDisabledUntil;
    if (disabledUntil == null) {
      return false;
    }
    return now.isBefore(disabledUntil);
  }

  bool _shouldSkipMatchRequest(
    List<LatLng> points, {
    required double radiusScale,
  }) {
    if (points.length > _maxMatchCoordinatesPerRequest) {
      return true;
    }

    final radii = _buildMatchRadii(
      points,
      radiusScale: radiusScale,
    );
    var radiusBudget = 0;
    for (final radius in radii) {
      radiusBudget += int.tryParse(radius) ?? 0;
    }

    return radiusBudget > 360;
  }

  Future<List<LatLng>?> _tryMatchInChunks(
    List<LatLng> points, {
    required int chunkSize,
    required int overlap,
    required double radiusScale,
  }) async {
    if (points.length < 2) {
      return null;
    }

    if (_isMatchTemporarilyDisabled(DateTime.now())) {
      return null;
    }

    final merged = <LatLng>[];
    var start = 0;

    while (start < points.length - 1) {
      final end = (start + chunkSize < points.length)
          ? start + chunkSize
          : points.length;
      final chunk = points.sublist(start, end);

      var chunkMatch = await _tryMatchCall(
        chunk,
        radiusScale: radiusScale,
      );

      if ((chunkMatch == null || chunkMatch.length < 2) && chunk.length > 8) {
        final compressedChunk = _compressWaypoints(chunk, 8);
        chunkMatch = await _tryMatchCall(
          compressedChunk,
          radiusScale: radiusScale * 0.72,
          logOnError: true,
        );
      }

      if ((chunkMatch == null || chunkMatch.length < 2) && chunk.length > 6) {
        final miniChunk = _compressWaypoints(chunk, 6);
        chunkMatch = await _tryMatchCall(
          miniChunk,
          radiusScale: radiusScale * 0.55,
          logOnError: true,
        );
      }

      if (chunkMatch == null || chunkMatch.length < 2) {
        return null;
      }

      if (merged.isEmpty) {
        merged.addAll(chunkMatch);
      } else {
        final isConnected = _distanceMeters(merged.last, chunkMatch.first) <= 8;
        merged.addAll(isConnected ? chunkMatch.skip(1) : chunkMatch);
      }

      if (end >= points.length) {
        break;
      }

      start = end - overlap;
      if (start < 0) {
        start = 0;
      }
    }

    return merged.length >= 2 ? merged : null;
  }

  bool _isTooBigMatchError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('toobig') ||
        normalized.contains('radius search size is too large') ||
        normalized.contains('too many trace coordinates')) {
      return true;
    }

    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final code = data['code']?.toString().toLowerCase() ?? '';
        final message = data['message']?.toString().toLowerCase() ?? '';
        if (code == 'toobig' ||
            message.contains('radius search size is too large') ||
            message.contains('too many trace coordinates')) {
          return true;
        }
      }
    }

    return false;
  }

  List<LatLng> _interpolateWaypointsForMatching(
    List<LatLng> waypoints, {
    double stepMeters = 55,
  }) {
    if (waypoints.length < 2) {
      return waypoints;
    }

    final interpolated = <LatLng>[waypoints.first];
    for (var index = 0; index < waypoints.length - 1; index++) {
      final from = waypoints[index];
      final to = waypoints[index + 1];
      final segmentDistanceMeters = _distanceMeters(from, to);

      if (segmentDistanceMeters > stepMeters) {
        final insertCount = (segmentDistanceMeters / stepMeters).floor();
        for (var step = 1; step <= insertCount; step++) {
          final ratio = step / (insertCount + 1);
          final point = LatLng(
            from.latitude + ((to.latitude - from.latitude) * ratio),
            from.longitude + ((to.longitude - from.longitude) * ratio),
          );

          if (_distanceMeters(interpolated.last, point) >= 2) {
            interpolated.add(point);
          }
        }
      }

      if (_distanceMeters(interpolated.last, to) >= 2) {
        interpolated.add(to);
      }
    }

    return interpolated;
  }

  List<LatLng> _compressWaypoints(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) {
      return points;
    }

    final safeMaxPoints = maxPoints < 2 ? 2 : maxPoints;
    final compressed = <LatLng>[points.first];
    final interiorSlots = safeMaxPoints - 2;

    for (var slot = 1; slot <= interiorSlots; slot++) {
      final ratio = slot / (interiorSlots + 1);
      final index = (ratio * (points.length - 1)).round();
      final boundedIndex = index < 1
          ? 1
          : (index > points.length - 2 ? points.length - 2 : index);
      final point = points[boundedIndex];
      if (_distanceMeters(compressed.last, point) >= 2) {
        compressed.add(point);
      }
    }

    if (_distanceMeters(compressed.last, points.last) >= 2) {
      compressed.add(points.last);
    }

    return compressed;
  }

  Uri _buildMatchUri(
    List<LatLng> coordinates, {
    double radiusScale = 1.0,
    bool includeBearings = true,
  }) {
    final coordinatePath = coordinates
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');

    final radiuses = _buildMatchRadii(
      coordinates,
      radiusScale: radiusScale,
    ).join(';');

    final queryParams = <String, String>{
      'overview': 'full',
      'geometries': 'geojson',
      'gaps': 'ignore',
      'tidy': 'true',
      'radiuses': radiuses,
    };

    if (includeBearings && coordinates.length >= 2) {
      queryParams['bearings'] = _buildMatchBearings(coordinates).join(';');
    }

    return Uri.parse('$_osrmMatchBaseUrl$coordinatePath').replace(
      queryParameters: queryParams,
    );
  }

  List<String> _buildMatchBearings(List<LatLng> points) {
    if (points.length < 2) {
      return List.filled(points.length, '');
    }

    final bearings = <String>[];
    for (var index = 0; index < points.length; index++) {
      if (index == 0) {
        final heading = _bearingDegrees(points[index], points[index + 1]);
        bearings.add('${heading.round()},70');
        continue;
      }

      if (index == points.length - 1) {
        final heading = _bearingDegrees(points[index - 1], points[index]);
        bearings.add('${heading.round()},70');
        continue;
      }

      final previous = points[index - 1];
      final current = points[index];
      final next = points[index + 1];

      final incoming = _bearingDegrees(previous, current);
      final outgoing = _bearingDegrees(current, next);
      final lookahead = _bearingDegrees(previous, next);
      final turnDelta = _bearingDeltaDegrees(incoming, outgoing);

      final range = turnDelta <= 25 ? 55 : (turnDelta <= 55 ? 72 : 95);
      bearings.add('${lookahead.round()},$range');
    }

    return bearings;
  }

  double _bearingDegrees(LatLng from, LatLng to) {
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);
    final deltaLon = _toRadians(to.longitude - from.longitude);

    final y = math.sin(deltaLon) * math.cos(lat2);
    final x = (math.cos(lat1) * math.sin(lat2)) -
        (math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon));
    final raw = math.atan2(y, x) * (180 / math.pi);

    return (raw + 360) % 360;
  }

  double _bearingDeltaDegrees(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  List<String> _buildMatchRadii(
    List<LatLng> points, {
    required double radiusScale,
  }) {
    if (points.length < 3) {
      return List.filled(points.length, _formatRadiusMeters(18 * radiusScale));
    }

    final radii = <String>[];
    for (var index = 0; index < points.length; index++) {
      if (index == 0 || index == points.length - 1) {
        radii.add(_formatRadiusMeters(20 * radiusScale));
        continue;
      }

      final previous = points[index - 1];
      final current = points[index];
      final next = points[index + 1];

      final prevCurrent = _distanceMeters(previous, current);
      final currentNext = _distanceMeters(current, next);
      final prevNext = _distanceMeters(previous, next);

      final ratio = prevNext <= 1
          ? double.infinity
          : (prevCurrent + currentNext) / prevNext;
      final isLikelyAlleyDetour = prevCurrent <= 220 &&
          currentNext <= 220 &&
          prevNext <= 140 &&
          ratio >= 1.9;

      final radiusMeters = isLikelyAlleyDetour ? 26 : 16;
      radii.add(_formatRadiusMeters(radiusMeters * radiusScale));
    }

    radii[0] = _formatRadiusMeters(20 * radiusScale);
    radii[radii.length - 1] = _formatRadiusMeters(20 * radiusScale);

    return radii;
  }

  String _formatRadiusMeters(double rawMeters) {
    final clamped = rawMeters.clamp(8.0, 45.0);
    return clamped.round().toString();
  }

  List<LatLng> _collapseShortDetourLoops(
    List<LatLng> points, {
    double closureMeters = 24,
    double minLoopPathMeters = 140,
    int maxWindow = 160,
  }) {
    if (points.length < 4) {
      return points;
    }

    final simplified = List<LatLng>.from(points);
    var start = 0;
    while (start < simplified.length - 3) {
      var traversed = 0.0;
      var collapsed = false;

      final maxEnd = (start + maxWindow < simplified.length)
          ? start + maxWindow
          : simplified.length - 1;
      for (var end = start + 1; end <= maxEnd; end++) {
        traversed += _distanceMeters(simplified[end - 1], simplified[end]);
        if (traversed < minLoopPathMeters || end - start < 3) {
          continue;
        }

        final closure = _distanceMeters(simplified[start], simplified[end]);
        if (closure <= closureMeters) {
          simplified.removeRange(start + 1, end);
          start = start > 0 ? start - 1 : 0;
          collapsed = true;
          break;
        }
      }

      if (!collapsed) {
        start += 1;
      }
    }

    return simplified;
  }

  bool _isSamePointSequence(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) {
      return false;
    }

    for (var index = 0; index < a.length; index++) {
      final pointA = a[index];
      final pointB = b[index];
      if ((pointA.latitude - pointB.latitude).abs() > 0.000001 ||
          (pointA.longitude - pointB.longitude).abs() > 0.000001) {
        return false;
      }
    }

    return true;
  }

  List<LatLng>? _extractMatchPoints(dynamic responseData) {
    if (responseData is! Map<String, dynamic> ||
        responseData['code'] != 'Ok' ||
        responseData['matchings'] is! List) {
      return null;
    }

    final matchings = responseData['matchings'] as List;
    if (matchings.isEmpty) {
      return null;
    }

    final merged = <LatLng>[];
    for (final matching in matchings) {
      if (matching is! Map<String, dynamic> ||
          matching['geometry'] is! Map<String, dynamic>) {
        continue;
      }

      final geometry = matching['geometry'] as Map<String, dynamic>;
      if (geometry['coordinates'] is! List) {
        continue;
      }

      final coordinates = geometry['coordinates'] as List;
      final points = coordinates
          .whereType<List>()
          .where((coord) => coord.length >= 2)
          .map((coord) {
        final lon = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();

      if (points.isEmpty) {
        continue;
      }

      if (merged.isEmpty) {
        merged.addAll(points);
      } else {
        final isConnected = _distanceMeters(merged.last, points.first) <= 3;
        merged.addAll(isConnected ? points.skip(1) : points);
      }
    }

    return merged.length >= 2 ? merged : null;
  }

  Uri _buildRouteUri(
    List<LatLng> waypoints, {
    required bool useStrictDrivingHints,
  }) {
    final coordinates = waypoints
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');

    final queryParams = <String, String>{
      'overview': 'full',
      'geometries': 'geojson',
    };

    if (useStrictDrivingHints) {
      queryParams['approaches'] =
          List.filled(waypoints.length, 'curb').join(';');
      queryParams['continue_straight'] = 'true';
    }

    return Uri.parse('$_osrmBaseUrl$coordinates').replace(
      queryParameters: queryParams,
    );
  }

  Uri _buildWalkingRouteUri(LatLng from, LatLng to) {
    final coordinates =
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    return Uri.parse('$_osrmWalkingBaseUrl$coordinates').replace(
      queryParameters: const {
        'overview': 'full',
        'geometries': 'geojson',
      },
    );
  }

  List<LatLng>? _extractRoutePoints(dynamic responseData) {
    if (responseData is! Map<String, dynamic> ||
        responseData['code'] != 'Ok' ||
        responseData['routes'] is! List ||
        (responseData['routes'] as List).isEmpty) {
      return null;
    }

    final route = (responseData['routes'] as List).first;
    if (route is! Map<String, dynamic> ||
        route['geometry'] is! Map<String, dynamic>) {
      return null;
    }

    final geometry = route['geometry'] as Map<String, dynamic>;
    if (geometry['coordinates'] is! List) {
      return null;
    }

    final coordinates = geometry['coordinates'] as List;

    return coordinates
        .whereType<List>()
        .where((coord) => coord.length >= 2)
        .map((coord) {
      final lon = (coord[0] as num).toDouble();
      final lat = (coord[1] as num).toDouble();
      return LatLng(lat, lon);
    }).toList();
  }

  Future<List<LatLng>> getDrivingGeometryWithoutSnapping(
    List<LatLng> drivingWaypoints, {
    int maxWaypointsPerRequest = 25,
  }) async {
    return _getRouteGeometryBatchedWithoutSnapping(
      drivingWaypoints,
      maxWaypointsPerRequest: maxWaypointsPerRequest,
    );
  }

  /// Get route geometry with multiple segments (for long routes)
  /// Splits into chunks to avoid API limits
  Future<List<LatLng>> getRouteGeometryBatched(
    List<LatLng> waypoints, {
    int maxWaypointsPerRequest = 25,
  }) async {
    final result = await buildTransitGeometryWithAccessPoints(
      waypoints,
      maxWaypointsPerRequest: maxWaypointsPerRequest,
    );
    return result.transitGeometry;
  }
}
