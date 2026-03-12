import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../domain/repositories/station_repository.dart';
import 'station_event.dart';
import 'station_state.dart';

@lazySingleton
class StationBloc extends Bloc<StationEvent, StationState> {
  final StationRepository repository;
  StationBloc({required this.repository}) : super(const StationInitial()) {
    on<FetchAllStationsEvent>(_onFetchAllStations);
    on<FetchStationByIdEvent>(_onFetchStationById);
    on<FetchStationsInBoundsEvent>(_onFetchStationsInBounds);
    on<ClearSelectedStationEvent>(_onClearSelectedStation);
  }
  Future<void> _onFetchAllStations(
    FetchAllStationsEvent event,
    Emitter<StationState> emit,
  ) async {
    if (event.refresh || state is! StationLoaded) {
      emit(const StationLoading());
    }
    final result = await repository.getAllStations(
      page: event.page,
      limit: event.limit,
    );
    await result.fold(
      (failure) async {
        emit(StationError(failure.message));
      },
      (stations) async {
        if (state is StationLoaded && !event.refresh) {
          final currentState = state as StationLoaded;
          final allStations = [...currentState.stations, ...stations];
          emit(StationLoaded(
            stations: allStations,
            currentPage: event.page,
            hasMore: stations.length >= event.limit,
          ));
        } else {
          emit(StationLoaded(
            stations: stations,
            currentPage: event.page,
            hasMore: stations.length >= event.limit,
          ));
        }
      },
    );
  }

  Future<void> _onFetchStationById(
    FetchStationByIdEvent event,
    Emitter<StationState> emit,
  ) async {
    emit(const StationDetailLoading());
    final result = await repository.getStationById(event.id);
    await result.fold(
      (failure) async {
        emit(StationError(failure.message));
      },
      (station) async {
        emit(StationDetailLoaded(station));
      },
    );
  }

  Future<void> _onFetchStationsInBounds(
    FetchStationsInBoundsEvent event,
    Emitter<StationState> emit,
  ) async {
    emit(const StationLoading());
    final result = await repository.getStationsInBounds(
      northLat: event.northLat,
      southLat: event.southLat,
      eastLng: event.eastLng,
      westLng: event.westLng,
    );
    await result.fold(
      (failure) async {
        emit(StationError(failure.message));
      },
      (stations) async {
        emit(StationLoaded(
          stations: stations,
          currentPage: 1,
          hasMore: false,
        ));
      },
    );
  }

  Future<void> _onClearSelectedStation(
    ClearSelectedStationEvent event,
    Emitter<StationState> emit,
  ) async {
    if (state is StationDetailLoaded) {
      emit(const StationInitial());
    }
  }

  /// Singleton — do not close. Prevents any BlocProvider(create:...) from
  /// shutting down the singleton stream when the provider is disposed.
  @override
  Future<void> close() async {}
}
