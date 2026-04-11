import 'package:dartz/dartz.dart';
import 'package:smartgo/core/errors/failures.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/domain/entities/path_finding.dart';

abstract class RouteRepository {
  Future<Either<Failure, List<BusRoute>>> getAllRoutes({
    int page = 1,
    int limit = 200,
    RouteDirection? direction,
  });
  Future<Either<Failure, BusRoute>> getRouteById({
    required String id,
    RouteDirection? direction,
  });
  Future<Either<Failure, int>> getTotalRoutes();
  Future<Either<Failure, List<PathResult>>> findPath({
    String? fromStationCode,
    String? toStationCode,
    double? fromLatitude,
    double? fromLongitude,
    double? toLatitude,
    double? toLongitude,
    required String criteria,
    int numPaths = 3,
    int maxTransfers = 3,
    int? timeOfDay,
    bool congestionAware = true,
  });
}
