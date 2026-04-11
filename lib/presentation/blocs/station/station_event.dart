import 'package:equatable/equatable.dart';

abstract class StationEvent extends Equatable {
  const StationEvent();
  @override
  List<Object?> get props => [];
}

class FetchAllStationsEvent extends StationEvent {
  final int page;
  final int limit;
  final bool refresh;
  const FetchAllStationsEvent({
    this.page = 1,
    this.limit = 5000,
    this.refresh = false,
  });
  @override
  List<Object?> get props => [page, limit, refresh];
}

class FetchStationByIdEvent extends StationEvent {
  final String id;
  const FetchStationByIdEvent(this.id);
  @override
  List<Object?> get props => [id];
}

class FetchStationsInBoundsEvent extends StationEvent {
  final double northLat;
  final double southLat;
  final double eastLng;
  final double westLng;
  const FetchStationsInBoundsEvent({
    required this.northLat,
    required this.southLat,
    required this.eastLng,
    required this.westLng,
  });
  @override
  List<Object?> get props => [northLat, southLat, eastLng, westLng];
}

class ClearSelectedStationEvent extends StationEvent {
  const ClearSelectedStationEvent();
}
