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
  static const int _maxMatchCoordinatesPerRequest = 40;
  static const int _directMatchThreshold = 24;
  static const int _matchChunkSize = 20;
  static const int _matchChunkOverlap = 3;
  static const double _minSnapDistanceMeters = 8;
  static const double _alleyDistanceThresholdMeters = 35;
  static const double _maxSnapDistanceMeters = 280;
  static const double _walkingSpeedKmPerHour = 5;
  static const int _nearestRequestBatchSize = 4;
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
      final fastModeBatchSize =
          maxWaypointsPerRequest < _fastModeMaxWaypointsPerRequest
              ? maxWaypointsPerRequest
              : _fastModeMaxWaypointsPerRequest;
      final geometry = await _getRouteGeometryBatchedWithoutSnapping(
        dedupedWaypoints,
        maxWaypointsPerRequest: fastModeBatchSize,
      );

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

    final drivingWaypoints = accessPoints
        .map((accessPoint) => accessPoint.busAccessCoordinate)
        .toList(growable: false);
    final dedupedDrivingWaypoints =
        _dedupeConsecutiveWaypoints(drivingWaypoints);

    var geometry = await getDrivingGeometryPreferMatch(
      dedupedDrivingWaypoints,
    );
    if (_isSamePointSequence(geometry, dedupedDrivingWaypoints)) {
      geometry = await _getRouteGeometryBatchedWithoutSnapping(
        dedupedDrivingWaypoints,
        maxWaypointsPerRequest: maxWaypointsPerRequest,
      );
    }

    return TransitGeometryResult(
      stationAccessPoints: accessPoints,
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
    final shouldMoveToAccessPoint = canUseSnappedRoad &&
        bestCandidate.distanceMeters >= _minSnapDistanceMeters;
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

      final score = candidate.distanceMeters + (corridorPenalty * 0.45);
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
    return '$profile|$compact';
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
    if (waypoints.length < 2) {
      return waypoints;
    }

    final cacheKey = _buildRouteCacheKey(waypoints, profile: 'driving');
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
        AppLogger.info('Fetching route geometry from OSRM...');

        _recordOsrmRequest('route');
        final response = await _dio
            .getUri(_buildRouteUri(waypoints, useStrictDrivingHints: false));
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

    final now = DateTime.now();
    if (_isMatchTemporarilyDisabled(now)) {
      return deduped;
    }

    final cacheKey = _buildRouteCacheKey(deduped, profile: 'driving-match');
    final cached = _matchGeometryCache[cacheKey];
    if (cached != null &&
        cached.isNotEmpty &&
        !_isSamePointSequence(cached, deduped)) {
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
      if (effectiveMaxCoordinates > 32) {
        effectiveMaxCoordinates = 32;
      }
      if (effectiveMaxCoordinates < 12) {
        effectiveMaxCoordinates = 12;
      }

      final interpolationStepMeters =
          deduped.length >= 18 ? 95.0 : (deduped.length >= 10 ? 78.0 : 62.0);
      final interpolated = _interpolateWaypointsForMatching(
        deduped,
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
      }

      if ((matchedPoints == null || matchedPoints.length < 2) &&
          !_isMatchTemporarilyDisabled(DateTime.now())) {
        var requestPoints = baseRequestPoints.length > _directMatchThreshold
            ? _compressWaypoints(baseRequestPoints, 24)
            : baseRequestPoints;
        var radiusScale = 0.56;

        for (var attempt = 0; attempt < 2; attempt++) {
          if (_isMatchTemporarilyDisabled(DateTime.now())) {
            break;
          }

          matchedPoints = await _tryMatchCall(
            requestPoints,
            radiusScale: radiusScale,
            logOnError: attempt == 1,
          );
          if (matchedPoints != null && matchedPoints.length >= 2) {
            break;
          }

          if (attempt == 0 && requestPoints.length > 16) {
            requestPoints = _compressWaypoints(requestPoints, 16);
            radiusScale *= 0.75;
          }
        }
      }

      if (matchedPoints != null && matchedPoints.length >= 2) {
        final cleaned = _collapseShortDetourLoops(matchedPoints);
        final result = cleaned.length >= 2 ? cleaned : matchedPoints;
        if (!_isSamePointSequence(result, deduped)) {
          _matchGeometryCache[cacheKey] = result;
        }
        return result;
      }

      return deduped;
    }();

    _matchGeometryInFlight[cacheKey] = requestFuture;
    try {
      return await requestFuture;
    } finally {
      _matchGeometryInFlight.remove(cacheKey);
    }
  }

  Future<List<LatLng>?> _tryMatchCall(
    List<LatLng> points, {
    required double radiusScale,
    bool logOnError = false,
  }) async {
    if (points.length < 2) {
      return null;
    }

    if (_isMatchTemporarilyDisabled(DateTime.now())) {
      return null;
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
      return _extractMatchPoints(response.data);
    } catch (e) {
      final isTooBig = _isTooBigMatchError(e);
      if (isTooBig) {
        _matchTemporarilyDisabledUntil =
            DateTime.now().add(_matchDisableDurationOnTooBig);
      }

      if (logOnError || !isTooBig) {
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
    if (points.length > 24) {
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

      if ((chunkMatch == null || chunkMatch.length < 2) && chunk.length > 14) {
        final compressedChunk = _compressWaypoints(chunk, 16);
        chunkMatch = await _tryMatchCall(
          compressedChunk,
          radiusScale: radiusScale * 0.72,
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
  }) {
    final coordinatePath = coordinates
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');

    final radiuses = _buildMatchRadii(
      coordinates,
      radiusScale: radiusScale,
    ).join(';');

    return Uri.parse('$_osrmMatchBaseUrl$coordinatePath').replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'gaps': 'ignore',
        'tidy': 'true',
        'radiuses': radiuses,
      },
    );
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
