import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/errors/exceptions.dart';
import 'package:smartgo/core/errors/failures.dart';
import 'package:smartgo/data/datasources/route_remote_data_source.dart';
import 'package:smartgo/data/models/path_finding_model.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/domain/entities/path_finding.dart';
import 'package:smartgo/domain/repositories/route_repository.dart';

@LazySingleton(as: RouteRepository)
class RouteRepositoryImpl implements RouteRepository {
  final RouteRemoteDataSource remoteDataSource;
  RouteRepositoryImpl({required this.remoteDataSource});
  @override
  Future<Either<Failure, List<BusRoute>>> getAllRoutes({
    int page = 1,
    int limit = 10,
    RouteDirection? direction,
  }) async {
    try {
      final response = await remoteDataSource.getAllRoutes(
        page: page,
        limit: limit,
        direction: direction,
      );
      return Right(response.data.routes);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, BusRoute>> getRouteById({
    required String id,
    RouteDirection? direction,
  }) async {
    try {
      final response = await remoteDataSource.getRouteById(
        id: id,
        direction: direction,
      );
      return Right(response.data);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> getTotalRoutes() async {
    try {
      final response = await remoteDataSource.getAllRoutes(
        page: 1,
        limit: 1,
      );
      return Right(response.data.total);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
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
  }) async {
    try {
      StationCodePair? stationCode;
      CoordinatesPair? coordinates;
      if (fromStationCode != null && toStationCode != null) {
        stationCode = StationCodePair(
          from: fromStationCode,
          to: toStationCode,
        );
      }
      if (fromLatitude != null &&
          fromLongitude != null &&
          toLatitude != null &&
          toLongitude != null) {
        coordinates = CoordinatesPair(
          from: LocationCoordinates(
            latitude: fromLatitude,
            longitude: fromLongitude,
          ),
          to: LocationCoordinates(
            latitude: toLatitude,
            longitude: toLongitude,
          ),
        );
      }
      final request = PathRequest(
        stationCode: stationCode,
        coordinates: coordinates,
        criteria: criteria,
        numPaths: numPaths,
        maxTransfers: maxTransfers,
        timeOfDay: timeOfDay,
        congestionAware: congestionAware,
      );
      final response = await remoteDataSource.findPath(request);
      return Right(response.paths);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }
}
