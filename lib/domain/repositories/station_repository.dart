import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../entities/station.dart';

abstract class StationRepository {
  Future<Either<Failure, List<Station>>> getAllStations({
    int page = 1,
    int limit = 5000,
  });
  Future<Either<Failure, Station>> getStationById(String id);
  Future<Either<Failure, List<Station>>> getStationsInBounds({
    required double northLat,
    required double southLat,
    required double eastLng,
    required double westLng,
  });
}
