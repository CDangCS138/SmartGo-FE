import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:latlong2/latlong.dart';
import '../logging/app_logger.dart';

/// Service to get actual route geometry from routing engines
@lazySingleton
class RouteGeometryService {
  final Dio _dio;

  RouteGeometryService(this._dio);

  /// Get route geometry using OSRM (free, no API key needed)
  /// Returns list of LatLng points that follow actual roads
  Future<List<LatLng>> getRouteGeometry(List<LatLng> waypoints) async {
    if (waypoints.length < 2) {
      return waypoints;
    }

    try {
      // Build OSRM API URL
      // Format: http://router.project-osrm.org/route/v1/driving/lon1,lat1;lon2,lat2;...
      final coordinates = waypoints
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');

      final url =
          'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson';

      AppLogger.info('Fetching route geometry from OSRM...');

      final response = await _dio.get(url);

      if (response.statusCode == 200 && response.data['code'] == 'Ok') {
        final routes = response.data['routes'] as List;
        if (routes.isNotEmpty) {
          final geometry = routes[0]['geometry'];
          final coordinates = geometry['coordinates'] as List;

          // Convert GeoJSON coordinates [lon, lat] to LatLng
          final routePoints = coordinates
              .map((coord) => LatLng(
                    coord[1] as double, // latitude
                    coord[0] as double, // longitude
                  ))
              .toList();

          AppLogger.info(
              'Route geometry fetched: ${routePoints.length} points');
          return routePoints;
        }
      }

      AppLogger.warning('Failed to get route geometry, using waypoints');
      return waypoints;
    } catch (e) {
      AppLogger.error('Error fetching route geometry: $e');
      // Fallback to direct waypoints if routing fails
      return waypoints;
    }
  }

  /// Get route geometry with multiple segments (for long routes)
  /// Splits into chunks to avoid API limits
  Future<List<LatLng>> getRouteGeometryBatched(
    List<LatLng> waypoints, {
    int maxWaypointsPerRequest = 25,
  }) async {
    if (waypoints.length <= maxWaypointsPerRequest) {
      return getRouteGeometry(waypoints);
    }

    final allRoutePoints = <LatLng>[];

    // Split into chunks
    for (int i = 0; i < waypoints.length - 1; i += maxWaypointsPerRequest - 1) {
      final endIndex = (i + maxWaypointsPerRequest < waypoints.length)
          ? i + maxWaypointsPerRequest
          : waypoints.length;

      final chunk = waypoints.sublist(i, endIndex);
      final segmentPoints = await getRouteGeometry(chunk);

      if (i == 0) {
        allRoutePoints.addAll(segmentPoints);
      } else {
        // Skip first point to avoid duplicates
        allRoutePoints.addAll(segmentPoints.skip(1));
      }
    }

    return allRoutePoints;
  }
}
