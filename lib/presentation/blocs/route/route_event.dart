import 'package:equatable/equatable.dart';
import 'package:smartgo/domain/entities/route.dart';

abstract class RouteEvent extends Equatable {
  const RouteEvent();
  @override
  List<Object?> get props => [];
}

class FetchAllRoutesEvent extends RouteEvent {
  final int page;
  final int limit;
  final RouteDirection? direction;
  const FetchAllRoutesEvent({
    this.page = 1,
    this.limit = 10,
    this.direction,
  });
  @override
  List<Object?> get props => [page, limit, direction];
}

class FetchRouteByIdEvent extends RouteEvent {
  final String id;
  final RouteDirection? direction;
  const FetchRouteByIdEvent({
    required this.id,
    this.direction,
  });
  @override
  List<Object?> get props => [id, direction];
}

class RefreshRoutesEvent extends RouteEvent {
  const RefreshRoutesEvent();
}

class LoadMoreRoutesEvent extends RouteEvent {
  const LoadMoreRoutesEvent();
}

class FindPathEvent extends RouteEvent {
  final String? fromStationCode;
  final String? toStationCode;
  final double? fromLatitude;
  final double? fromLongitude;
  final double? toLatitude;
  final double? toLongitude;
  final String criteria;
  final int numPaths;
  final int maxTransfers;
  final int? timeOfDay;
  final bool congestionAware;
  // Timestamp to force Bloc to process each event as unique
  final int timestamp;

  FindPathEvent({
    this.fromStationCode,
    this.toStationCode,
    this.fromLatitude,
    this.fromLongitude,
    this.toLatitude,
    this.toLongitude,
    required this.criteria,
    this.numPaths = 3,
    this.maxTransfers = 3,
    this.timeOfDay,
    this.congestionAware = true,
    int? timestamp,
  })  : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch,
        assert(
          (fromStationCode != null && toStationCode != null) ||
              (fromLatitude != null &&
                  fromLongitude != null &&
                  toLatitude != null &&
                  toLongitude != null),
          'Either station codes or coordinates must be provided',
        );
  @override
  List<Object?> get props => [
        timestamp,
        fromStationCode,
        toStationCode,
        fromLatitude,
        fromLongitude,
        toLatitude,
        toLongitude,
        criteria,
        numPaths,
        maxTransfers,
        timeOfDay,
        congestionAware,
      ];
}
