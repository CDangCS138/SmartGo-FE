import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/errors/failures.dart';
import 'package:smartgo/domain/entities/path_finding.dart';
import 'package:smartgo/domain/repositories/route_repository.dart';

@injectable
class FindPathUseCase {
  final RouteRepository repository;
  FindPathUseCase(this.repository);
  Future<Either<Failure, List<PathResult>>> call({
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
    return await repository.findPath(
      fromStationCode: fromStationCode,
      toStationCode: toStationCode,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      criteria: criteria,
      numPaths: numPaths,
      maxTransfers: maxTransfers,
      timeOfDay: timeOfDay,
      congestionAware: congestionAware,
    );
  }

  Future<Either<Failure, List<PathResult>>> findFastest({
    String? fromStationCode,
    String? toStationCode,
    double? fromLatitude,
    double? fromLongitude,
    double? toLatitude,
    double? toLongitude,
    int numPaths = 3,
    int maxTransfers = 3,
    int? timeOfDay,
  }) {
    return call(
      fromStationCode: fromStationCode,
      toStationCode: toStationCode,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      criteria: 'TIME',
      numPaths: numPaths,
      maxTransfers: maxTransfers,
      timeOfDay: timeOfDay,
    );
  }

  Future<Either<Failure, List<PathResult>>> findCheapest({
    String? fromStationCode,
    String? toStationCode,
    double? fromLatitude,
    double? fromLongitude,
    double? toLatitude,
    double? toLongitude,
    int numPaths = 3,
    int maxTransfers = 3,
    int? timeOfDay,
  }) {
    return call(
      fromStationCode: fromStationCode,
      toStationCode: toStationCode,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      criteria: 'COST',
      numPaths: numPaths,
      maxTransfers: maxTransfers,
      timeOfDay: timeOfDay,
    );
  }

  Future<Either<Failure, List<PathResult>>> findShortest({
    String? fromStationCode,
    String? toStationCode,
    double? fromLatitude,
    double? fromLongitude,
    double? toLatitude,
    double? toLongitude,
    int numPaths = 3,
    int maxTransfers = 3,
    int? timeOfDay,
  }) {
    return call(
      fromStationCode: fromStationCode,
      toStationCode: toStationCode,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      criteria: 'DISTANCE',
      numPaths: numPaths,
      maxTransfers: maxTransfers,
      timeOfDay: timeOfDay,
    );
  }

  Future<Either<Failure, List<PathResult>>> findBalanced({
    String? fromStationCode,
    String? toStationCode,
    double? fromLatitude,
    double? fromLongitude,
    double? toLatitude,
    double? toLongitude,
    int numPaths = 3,
    int maxTransfers = 3,
    int? timeOfDay,
  }) {
    return call(
      fromStationCode: fromStationCode,
      toStationCode: toStationCode,
      fromLatitude: fromLatitude,
      fromLongitude: fromLongitude,
      toLatitude: toLatitude,
      toLongitude: toLongitude,
      criteria: 'BALANCED',
      numPaths: numPaths,
      maxTransfers: maxTransfers,
      timeOfDay: timeOfDay,
    );
  }
}
