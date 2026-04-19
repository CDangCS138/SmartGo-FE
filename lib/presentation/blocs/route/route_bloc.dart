import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/domain/repositories/route_repository.dart';
import 'package:smartgo/presentation/blocs/route/route_event.dart';
import 'package:smartgo/presentation/blocs/route/route_state.dart';

@lazySingleton
class RouteBloc extends Bloc<RouteEvent, RouteState> {
  final RouteRepository repository;
  static const int _defaultLimit = 200;
  int _currentPage = 1;
  int _totalCount = 0;
  RouteDirection? _currentDirection;
  String _currentRouteCode = '';
  List<BusRoute> _allRoutes = [];
  RouteBloc({required this.repository}) : super(const RouteInitial()) {
    on<FetchAllRoutesEvent>(_onFetchAllRoutes);
    on<FetchRouteByIdEvent>(_onFetchRouteById);
    on<RefreshRoutesEvent>(_onRefreshRoutes);
    on<LoadMoreRoutesEvent>(_onLoadMoreRoutes);
    on<FindPathEvent>(_onFindPath);
  }
  Future<void> _onFetchAllRoutes(
    FetchAllRoutesEvent event,
    Emitter<RouteState> emit,
  ) async {
    emit(const RouteLoading());
    _currentDirection = event.direction;
    _currentRouteCode = event.routeCode.trim();

    final result = await repository.getAllRoutes(
      page: event.page,
      limit: event.limit,
      direction: _currentDirection,
      routeCode: _currentRouteCode,
    );
    await result.fold(
      (failure) async {
        emit(RouteError(message: failure.message));
      },
      (routes) async {
        _currentPage = event.page;
        _allRoutes = routes;
        if (_shouldUseSummaryTotal()) {
          final totalResult = await repository.getTotalRoutes();
          totalResult.fold(
            (failure) => _totalCount = routes.length,
            (total) => _totalCount = total,
          );
        } else {
          _totalCount = routes.length;
        }
        final hasMore = routes.length >= event.limit;
        emit(RouteLoaded(
          routes: routes,
          currentPage: _currentPage,
          totalCount: _totalCount,
          hasMorePages: hasMore,
        ));
      },
    );
  }

  Future<void> _onFetchRouteById(
    FetchRouteByIdEvent event,
    Emitter<RouteState> emit,
  ) async {
    emit(const RouteLoading());
    final result = await repository.getRouteById(
      id: event.id,
      direction: event.direction,
    );
    await result.fold(
      (failure) async {
        emit(RouteError(message: failure.message));
      },
      (route) async {
        emit(RouteDetailLoaded(route: route));
      },
    );
  }

  Future<void> _onRefreshRoutes(
    RefreshRoutesEvent event,
    Emitter<RouteState> emit,
  ) async {
    _currentPage = 1;
    _allRoutes = [];
    _currentDirection = event.direction ?? _currentDirection;
    if (event.routeCode != null) {
      _currentRouteCode = event.routeCode!.trim();
    }

    emit(const RouteLoading());
    final result = await repository.getAllRoutes(
      page: 1,
      limit: _defaultLimit,
      direction: _currentDirection,
      routeCode: _currentRouteCode,
    );
    await result.fold(
      (failure) async {
        emit(RouteError(message: failure.message));
      },
      (routes) async {
        _allRoutes = routes;
        _currentPage = 1;
        if (_shouldUseSummaryTotal()) {
          final totalResult = await repository.getTotalRoutes();
          totalResult.fold(
            (failure) => _totalCount = routes.length,
            (total) => _totalCount = total,
          );
        } else {
          _totalCount = routes.length;
        }
        final hasMore = routes.length >= _defaultLimit;
        emit(RouteLoaded(
          routes: routes,
          currentPage: _currentPage,
          totalCount: _totalCount,
          hasMorePages: hasMore,
        ));
      },
    );
  }

  Future<void> _onLoadMoreRoutes(
    LoadMoreRoutesEvent event,
    Emitter<RouteState> emit,
  ) async {
    if (state is RouteLoaded) {
      final currentState = state as RouteLoaded;
      if (!currentState.hasMorePages) {
        return;
      }
      emit(RouteLoadingMore(
        currentRoutes: currentState.routes,
        currentPage: currentState.currentPage,
      ));
      final nextPage = _currentPage + 1;
      final result = await repository.getAllRoutes(
        page: nextPage,
        limit: _defaultLimit,
        direction: _currentDirection,
        routeCode: _currentRouteCode,
      );
      await result.fold(
        (failure) async {
          emit(RouteError(message: failure.message));
        },
        (newRoutes) async {
          _currentPage = nextPage;
          _allRoutes = [..._allRoutes, ...newRoutes];
          final hasMore = newRoutes.length >= _defaultLimit;
          emit(RouteLoaded(
            routes: _allRoutes,
            currentPage: _currentPage,
            totalCount: _totalCount,
            hasMorePages: hasMore,
          ));
        },
      );
    }
  }

  Future<void> _onFindPath(
    FindPathEvent event,
    Emitter<RouteState> emit,
  ) async {
    emit(const PathFindingLoading());
    final result = await repository.findPath(
      fromStationCode: event.fromStationCode,
      toStationCode: event.toStationCode,
      fromLatitude: event.fromLatitude,
      fromLongitude: event.fromLongitude,
      toLatitude: event.toLatitude,
      toLongitude: event.toLongitude,
      criteria: event.criteria,
      numPaths: event.numPaths,
      maxTransfers: event.maxTransfers,
      timeOfDay: event.timeOfDay,
      congestionAware: event.congestionAware,
    );
    await result.fold(
      (failure) async {
        emit(PathFindingError(message: failure.message));
      },
      (paths) async {
        emit(PathsFound(paths: paths));
      },
    );
  }

  bool _shouldUseSummaryTotal() {
    return _currentRouteCode.isEmpty &&
        (_currentDirection == null || _currentDirection == RouteDirection.both);
  }

  /// Singleton — do not close. The app-level BlocProvider.value or any
  /// accidentally-created BlocProvider(create:...) will call close() on
  /// dispose; overriding it here prevents the singleton stream from being
  /// shut down.
  @override
  Future<void> close() async {
    super.close();
  }
}
