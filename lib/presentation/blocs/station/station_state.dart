import 'package:equatable/equatable.dart';
import '../../../domain/entities/station.dart';

abstract class StationState extends Equatable {
  const StationState();
  @override
  List<Object?> get props => [];
}

class StationInitial extends StationState {
  const StationInitial();
}

class StationLoading extends StationState {
  const StationLoading();
}

class StationLoaded extends StationState {
  final List<Station> stations;
  final int currentPage;
  final bool hasMore;
  const StationLoaded({
    required this.stations,
    this.currentPage = 1,
    this.hasMore = true,
  });
  @override
  List<Object?> get props => [stations, currentPage, hasMore];
  StationLoaded copyWith({
    List<Station>? stations,
    int? currentPage,
    bool? hasMore,
  }) {
    return StationLoaded(
      stations: stations ?? this.stations,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class StationDetailLoading extends StationState {
  const StationDetailLoading();
}

class StationDetailLoaded extends StationState {
  final Station station;
  const StationDetailLoaded(this.station);
  @override
  List<Object?> get props => [station];
}

class StationError extends StationState {
  final String message;
  const StationError(this.message);
  @override
  List<Object?> get props => [message];
}
