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
  final Map<String, List<LatLng>> _routeGeometryCache = {};
  final Map<String, List<LatLng>> _matchGeometryCache = {};
  final Map<String, List<LatLng>> _walkingGeometryCache = {};
  final Map<String, DateTime> _nearestFailureBackoff = {};
  DateTime? _nearestTemporarilyDisabledUntil;
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
  static const int _maxMatchCoordinatesPerRequest = 100;
  static const double _minSnapDistanceMeters = 8;
  static const double _alleyDistanceThresholdMeters = 35;
  static const double _maxSnapDistanceMeters = 280;
  static const double _walkingSpeedKmPerHour = 5;
  static const int _nearestRequestBatchSize = 4;
  static const Duration _nearestFailureBackoffDuration = Duration(minutes: 3);
  static const Duration _nearestFailureBurstWindow = Duration(seconds: 20);
  static const int _nearestFailureBurstThreshold = 3;
  static const Duration _nearestDisableDuration = Duration(minutes: 2);
  static const Duration _failureLogThrottle = Duration(seconds: 8);

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

    final geometry = await _getRouteGeometryBatchedWithoutSnapping(
      dedupedDrivingWaypoints,
      maxWaypointsPerRequest: maxWaypointsPerRequest,
    );

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

    try {
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

    final failedAt = _nearestFailureBackoff[key];
    if (failedAt != null) {
      if (now.difference(failedAt) < _nearestFailureBackoffDuration) {
        return const [];
      }
      _nearestFailureBackoff.remove(key);
    }

    try {
      final response =
          await _dio.getUri(_buildNearestUri(stop, number: number));
      final data = response.data;
      if (data is! Map<String, dynamic> || data['code'] != 'Ok') {
        _recordNearestFailure(key, 'Invalid nearest response payload');
        return const [];
      }

      final waypoints = data['waypoints'];
      if (waypoints is! List) {
        _recordNearestFailure(key, 'Nearest response missing waypoints list');
        return const [];
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
      return const [];
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

    if (drivingWaypoints.length <= maxWaypointsPerRequest) {
      return _getRouteGeometryFromDrivingWaypoints(drivingWaypoints);
    }

    final allRoutePoints = <LatLng>[];
    for (int i = 0;
        i < drivingWaypoints.length - 1;
        i += maxWaypointsPerRequest - 1) {
      final endIndex = (i + maxWaypointsPerRequest < drivingWaypoints.length)
          ? i + maxWaypointsPerRequest
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
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      AppLogger.info('Fetching route geometry from OSRM...');

      final strictResponse = await _dio
          .getUri(_buildRouteUri(waypoints, useStrictDrivingHints: true));
      final strictRoutePoints = _extractRoutePoints(strictResponse.data);
      if (strictRoutePoints != null) {
        _routeGeometryCache[cacheKey] = strictRoutePoints;
        AppLogger.info(
            'Route geometry fetched with curb/continue_straight: ${strictRoutePoints.length} points');
        return strictRoutePoints;
      }

      AppLogger.warning(
          'Strict OSRM route not found, retrying without curb/continue_straight');

      final fallbackResponse = await _dio
          .getUri(_buildRouteUri(waypoints, useStrictDrivingHints: false));
      final fallbackRoutePoints = _extractRoutePoints(fallbackResponse.data);
      if (fallbackRoutePoints != null) {
        _routeGeometryCache[cacheKey] = fallbackRoutePoints;
        AppLogger.info(
            'Route geometry fetched (fallback): ${fallbackRoutePoints.length} points');
        return fallbackRoutePoints;
      }

      AppLogger.warning('Failed to get route geometry, using waypoints');
      _routeGeometryCache[cacheKey] = waypoints;
      return waypoints;
    } catch (e) {
      _logRouteError(e);
      // Fallback to direct waypoints if routing fails
      _routeGeometryCache[cacheKey] = waypoints;
      return waypoints;
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

    final cacheKey = _buildRouteCacheKey(deduped, profile: 'driving-match');
    final cached = _matchGeometryCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final interpolated = _interpolateWaypointsForMatching(deduped);
    final requestPoints = interpolated.length <= maxCoordinatesPerRequest
        ? interpolated
        : _compressWaypoints(interpolated, maxCoordinatesPerRequest);

    try {
      final response = await _dio.getUri(_buildMatchUri(requestPoints));
      final matchedPoints = _extractMatchPoints(response.data);
      if (matchedPoints != null && matchedPoints.length >= 2) {
        _matchGeometryCache[cacheKey] = matchedPoints;
        return matchedPoints;
      }
    } catch (e) {
      _logRouteError('OSRM match failed: $e');
    }

    _matchGeometryCache[cacheKey] = deduped;
    return deduped;
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

  Uri _buildMatchUri(List<LatLng> coordinates) {
    final coordinatePath = coordinates
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');

    final radiuses = List.filled(coordinates.length, '35').join(';');

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
