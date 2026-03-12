import 'package:equatable/equatable.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/domain/entities/path_finding.dart';

abstract class RouteState extends Equatable {
  const RouteState();
  @override
  List<Object?> get props => [];
}

class RouteInitial extends RouteState {
  const RouteInitial();
}

class RouteLoading extends RouteState {
  const RouteLoading();
}

class RouteLoaded extends RouteState {
  final List<BusRoute> routes;
  final int currentPage;
  final int totalCount;
  final bool hasMorePages;
  const RouteLoaded({
    required this.routes,
    required this.currentPage,
    required this.totalCount,
    required this.hasMorePages,
  });
  @override
  List<Object?> get props => [routes, currentPage, totalCount, hasMorePages];
  RouteLoaded copyWith({
    List<BusRoute>? routes,
    int? currentPage,
    int? totalCount,
    bool? hasMorePages,
  }) {
    return RouteLoaded(
      routes: routes ?? this.routes,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasMorePages: hasMorePages ?? this.hasMorePages,
    );
  }
}

class RouteLoadingMore extends RouteState {
  final List<BusRoute> currentRoutes;
  final int currentPage;
  const RouteLoadingMore({
    required this.currentRoutes,
    required this.currentPage,
  });
  @override
  List<Object?> get props => [currentRoutes, currentPage];
}

class RouteDetailLoaded extends RouteState {
  final BusRoute route;
  const RouteDetailLoaded({required this.route});
  @override
  List<Object?> get props => [route];
}

class RouteError extends RouteState {
  final String message;
  const RouteError({required this.message});
  @override
  List<Object?> get props => [message];
}

class PathFindingLoading extends RouteState {
  const PathFindingLoading();
}

class PathsFound extends RouteState {
  final List<PathResult> paths;
  const PathsFound({required this.paths});
  @override
  List<Object?> get props => [paths];
}

class PathFindingError extends RouteState {
  final String message;
  const PathFindingError({required this.message});
  @override
  List<Object?> get props => [message];
}
