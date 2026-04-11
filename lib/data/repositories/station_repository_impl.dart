import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/exceptions.dart';
import '../../core/errors/failures.dart';
import '../../domain/entities/station.dart';
import '../../domain/repositories/station_repository.dart';
import '../datasources/station_remote_data_source.dart';

@LazySingleton(as: StationRepository)
class StationRepositoryImpl implements StationRepository {
  final StationRemoteDataSource remoteDataSource;
  StationRepositoryImpl({required this.remoteDataSource});
  @override
  Future<Either<Failure, List<Station>>> getAllStations({
    int page = 1,
    int limit = 5000,
  }) async {
    try {
      final stations = await remoteDataSource.getAllStations(
        page: page,
        limit: limit,
      );
      return Right(stations);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, Station>> getStationById(String id) async {
    try {
      final station = await remoteDataSource.getStationById(id);
      return Right(station);
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Station>>> getStationsInBounds({
    required double northLat,
    required double southLat,
    required double eastLng,
    required double westLng,
  }) async {
    try {
      final stations = await remoteDataSource.getAllStations(limit: 5000);
      final filteredStations = stations.where((station) {
        return station.latitude <= northLat &&
            station.latitude >= southLat &&
            station.longitude <= eastLng &&
            station.longitude >= westLng;
      }).toList();
      return Right(filteredStations);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }
}
