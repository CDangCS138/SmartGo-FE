import 'package:injectable/injectable.dart';
import 'package:smartgo/presentation/blocs/route/route_bloc.dart';
import 'package:smartgo/presentation/blocs/route/route_event.dart';
import 'package:smartgo/presentation/blocs/station/station_bloc.dart';
import 'package:smartgo/presentation/blocs/station/station_event.dart';
import 'package:smartgo/core/logging/app_logger.dart';

/// Service to preload application data on startup
@lazySingleton
class PreloadService {
  final RouteBloc routeBloc;
  final StationBloc stationBloc;

  PreloadService({
    required this.routeBloc,
    required this.stationBloc,
  });

  /// Preload all routes (162 routes)
  Future<void> preloadRoutes() async {
    try {
      AppLogger.info('Preloading all routes...');
      // Load all 162 routes in one go
      routeBloc.add(const FetchAllRoutesEvent(
        page: 1,
        limit: 200, // Load more than 162 to ensure we get all
      ));
      AppLogger.info('Route preload initiated');
    } catch (e) {
      AppLogger.error('Failed to preload routes: $e');
    }
  }

  /// Preload all stations (5000 stations)
  Future<void> preloadStations() async {
    try {
      AppLogger.info('Preloading all stations...');
      stationBloc.add(const FetchAllStationsEvent(
        page: 1,
        limit: 5000,
        refresh: true,
      ));
      AppLogger.info('Station preload initiated');
    } catch (e) {
      AppLogger.error('Failed to preload stations: $e');
    }
  }

  /// Preload all necessary data
  Future<void> preloadAll() async {
    await Future.wait([
      preloadRoutes(),
      preloadStations(),
    ]);
  }
}
