import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/maps/app_tile_layer.dart';
import 'package:smartgo/core/services/route_geometry_service.dart';
import 'package:smartgo/core/services/storage_service.dart';
import 'package:smartgo/data/datasources/user_favorites_remote_data_source.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/domain/entities/station.dart';
import 'package:smartgo/domain/repositories/route_repository.dart';
import 'package:smartgo/presentation/blocs/auth/auth_bloc.dart';
import 'package:smartgo/presentation/blocs/auth/auth_state.dart';
import 'package:smartgo/presentation/blocs/station/station_bloc.dart';
import 'package:smartgo/presentation/blocs/station/station_event.dart';
import 'package:smartgo/presentation/blocs/station/station_state.dart';
import 'package:smartgo/presentation/screens/route/route_ticket_payment_screen.dart';
import 'package:smartgo/presentation/widgets/loading_indicator.dart';
import 'package:smartgo/presentation/screens/home/widgets/home_navigation_bar.dart';

class RouteDetailScreen extends StatefulWidget {
  final BusRoute route;
  final String? routeCode;

  const RouteDetailScreen({
    super.key,
    required this.route,
    this.routeCode,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _forwardMapController = MapController();
  final MapController _backwardMapController = MapController();
  final Distance _distance = const Distance();
  final RouteGeometryService _routeGeometryService =
      getIt<RouteGeometryService>();
  final RouteRepository _routeRepository = getIt<RouteRepository>();
  late final UserFavoritesRemoteDataSource _favoritesDataSource;
  late final StorageService _storageService;
  late final String _favoriteRouteId;
  bool _isFavorite = false;
  bool _isUpdatingFavorite = false;
  bool _isSyncingFavorite = false;

  late BusRoute _route;
  BusRoute? _forwardRoute;
  BusRoute? _backwardRoute;
  bool _isLoadingRoute = false;

  List<Station> _forwardStations = [];
  List<Station> _backwardStations = [];
  bool _isLoadingStations = false;

  // Cache for route geometries
  List<LatLng>? _forwardRouteGeometry;
  List<LatLng>? _backwardRouteGeometry;

  @override
  void initState() {
    super.initState();
    _route = widget.route;
    _favoriteRouteId = widget.route.id;
    _favoritesDataSource =
        UserFavoritesRemoteDataSource(client: getIt<http.Client>());
    _storageService = getIt<StorageService>();
    _seedDirectionRoutesFromCurrent();
    _tabController = TabController(length: 3, vsync: this);
    if (_forwardCodes.isEmpty || _backwardCodes.isEmpty) {
      final routeCode = _resolveRouteCodeForRouteFetch();
      if (routeCode.isNotEmpty) {
        _fetchRouteByRouteCode(routeCode);
      } else {
        _loadStations();
      }
    } else {
      _loadStations();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFavoriteFromAuth(context.read<AuthBloc>().state);
  }

  void _syncFavoriteFromAuth(AuthState state) {
    if (state is AuthAuthenticated) {
      _loadFavoriteFromUser(state);
      return;
    }

    if (_isFavorite) {
      setState(() {
        _isFavorite = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isUpdatingFavorite) {
      return;
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      _showSnack('Vui lòng đăng nhập để lưu yêu thích', isError: true);
      return;
    }

    List<String> currentRouteIds = const [];
    List<String> currentStationIds = const [];
    final nextRouteIds = <String>{};
    bool wasFavorite = false;

    setState(() {
      _isUpdatingFavorite = true;
    });

    try {
      final accessToken = _resolveAccessToken(authState);
      final user = await _favoritesDataSource.getUserById(
        userId: authState.user.id,
        accessToken: accessToken,
      );
      currentRouteIds = user.favoriteRouteIds;
      currentStationIds = user.favoriteStationIds;
      nextRouteIds
        ..clear()
        ..addAll(currentRouteIds);
      wasFavorite = nextRouteIds.contains(_favoriteRouteId);

      if (wasFavorite) {
        nextRouteIds.remove(_favoriteRouteId);
      } else {
        nextRouteIds.add(_favoriteRouteId);
      }

      if (mounted) {
        setState(() {
          _isFavorite = !wasFavorite;
        });
      }
      await _favoritesDataSource.updateFavorites(
        userId: authState.user.id,
        favoriteRouteIds: nextRouteIds.toList(),
        favoriteStationIds: currentStationIds,
        accessToken: accessToken,
      );
      if (!mounted) {
        return;
      }
      _showSnack(
        wasFavorite ? 'Đã bỏ tuyến yêu thích' : 'Đã lưu tuyến yêu thích',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isFavorite = wasFavorite;
      });
      _showSnack('Không cập nhật được yêu thích: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingFavorite = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteFromUser(AuthAuthenticated authState) async {
    if (_isSyncingFavorite) {
      return;
    }

    _isSyncingFavorite = true;
    try {
      final accessToken = _resolveAccessToken(authState);
      final user = await _favoritesDataSource.getUserById(
        userId: authState.user.id,
        accessToken: accessToken,
      );
      final isFavorite = user.favoriteRouteIds.contains(_favoriteRouteId);
      if (mounted && isFavorite != _isFavorite) {
        setState(() {
          _isFavorite = isFavorite;
        });
      }
    } catch (_) {
      // Ignore sync errors.
    } finally {
      _isSyncingFavorite = false;
    }
  }

  String? _resolveAccessToken(AuthAuthenticated authState) {
    if (authState.accessToken.isNotEmpty) {
      return authState.accessToken;
    }
    return _storageService.getAuthToken();
  }

  void _showSnack(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.error : scheme.inverseSurface,
      ),
    );
  }

  void _seedDirectionRoutesFromCurrent() {
    if (_route.routeForwardCodes.isNotEmpty) {
      _forwardRoute = _route;
    }
    if (_route.routeBackwardCodes.isNotEmpty) {
      _backwardRoute = _route;
    }
  }

  Map<String, String> get _forwardCodes {
    if (_forwardRoute != null && _forwardRoute!.routeForwardCodes.isNotEmpty) {
      return _forwardRoute!.routeForwardCodes;
    }
    return _route.routeForwardCodes;
  }

  Map<String, String> get _backwardCodes {
    if (_backwardRoute != null &&
        _backwardRoute!.routeBackwardCodes.isNotEmpty) {
      return _backwardRoute!.routeBackwardCodes;
    }
    return _route.routeBackwardCodes;
  }

  String _resolveRouteCodeForRouteFetch() {
    final explicit = widget.routeCode?.trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }

    final code = _route.routeCode.trim();
    if (code.isNotEmpty) {
      return code;
    }

    return '';
  }

  Future<void> _fetchRouteByRouteCode(String routeCode) async {
    setState(() {
      _isLoadingRoute = true;
    });

    final result = await _routeRepository.getAllRoutes(
      page: 1,
      limit: 200,
      routeCode: routeCode,
    );
    if (!mounted) {
      return;
    }

    result.fold(
      (failure) {
        setState(() {
          _isLoadingRoute = false;
        });
        _loadStations();
      },
      (routes) {
        final matched = routes.where((route) {
          return route.routeCode.trim() == routeCode;
        }).toList();

        if (matched.isEmpty) {
          setState(() {
            _isLoadingRoute = false;
          });
          _loadStations();
          return;
        }

        BusRoute? forward;
        BusRoute? backward;
        BusRoute? base;

        for (final route in matched) {
          base ??= route;
          final hasForward = route.routeForwardCodes.isNotEmpty;
          final hasBackward = route.routeBackwardCodes.isNotEmpty;

          if (hasForward && !hasBackward) {
            forward ??= route;
          } else if (hasBackward && !hasForward) {
            backward ??= route;
          }
        }

        base ??= forward ?? backward;

        if (base != null) {
          if (base.routeForwardCodes.isNotEmpty) {
            forward ??= base;
          }
          if (base.routeBackwardCodes.isNotEmpty) {
            backward ??= base;
          }
        }

        setState(() {
          if (forward != null) {
            _forwardRoute = forward;
          }
          if (backward != null) {
            _backwardRoute = backward;
          }
          if (base != null) {
            _route = base;
          }
          _isLoadingRoute = false;
        });
        _loadStations();
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadStations() async {
    // Check if stations are already preloaded from StationBloc
    final currentState = context.read<StationBloc>().state;
    if (currentState is StationLoaded && currentState.stations.isNotEmpty) {
      // Use preloaded data directly
      _syncStations(currentState.stations);
      // Load route geometries after stations are matched
      _loadRouteGeometries();
      return;
    }

    // Otherwise fetch from API
    setState(() {
      _isLoadingStations = true;
    });
    context.read<StationBloc>().add(const FetchAllStationsEvent(limit: 5000));
  }

  void _syncStations(List<Station> stations) {
    setState(() {
      _forwardStations = _matchStationsWithCodes(
        _forwardCodes,
        stations,
      );
      _backwardStations = _matchStationsWithCodes(
        _backwardCodes,
        stations,
      );
      _isLoadingStations = false;
    });
  }

  List<Station> _matchStationsWithCodes(
    Map<String, String> codes,
    List<Station> allStations,
  ) {
    final matchedStations = <Station>[];

    // Preserve order from the route codes
    for (final code in codes.keys) {
      try {
        // Match by stationCode (list API) or by id (detail API with stationIds)
        final station = allStations.firstWhere(
          (s) => s.stationCode == code || s.id == code,
        );
        matchedStations.add(station);
      } catch (e) {
        // Station not found, skip
        continue;
      }
    }

    return matchedStations;
  }

  Future<void> _loadRouteGeometries() async {
    if (!mounted) {
      return;
    }

    final forwardGeometry = await _loadDirectionGeometry(_forwardStations);
    final backwardGeometry = await _loadDirectionGeometry(_backwardStations);

    if (!mounted) {
      return;
    }

    setState(() {
      _forwardRouteGeometry = forwardGeometry;
      _backwardRouteGeometry = backwardGeometry;
    });
  }

  Future<List<LatLng>?> _loadDirectionGeometry(List<Station> stations) async {
    if (stations.length < 2) {
      return null;
    }

    final waypoints = _buildDisplayWaypoints(stations);
    if (waypoints.length < 2) {
      return null;
    }

    // Match + interpolation often follows the main road better than plain route.
    final matchedGeometry =
        await _routeGeometryService.getDrivingGeometryPreferMatch(
      waypoints,
      maxCoordinatesPerRequest: 36,
    );
    if (!_isSamePointList(matchedGeometry, waypoints)) {
      return matchedGeometry;
    }

    // One fallback route request only.
    final fallbackWaypoints = _buildMainRoadAnchors(waypoints);
    final singleCallGeometry =
        await _routeGeometryService.getDrivingGeometryWithoutSnapping(
      fallbackWaypoints,
      maxWaypointsPerRequest: fallbackWaypoints.length,
    );
    return singleCallGeometry;
  }

  List<LatLng> _buildDisplayWaypoints(List<Station> stations) {
    final raw = stations
        .map((station) => LatLng(station.latitude, station.longitude))
        .toList(growable: false);

    if (raw.length <= 2) {
      return raw;
    }

    final filtered = <LatLng>[raw.first];
    for (var index = 1; index < raw.length - 1; index++) {
      final previous = filtered.last;
      final current = raw[index];
      final next = raw[index + 1];

      final prevCurrent = _distance.as(LengthUnit.Meter, previous, current);
      final currentNext = _distance.as(LengthUnit.Meter, current, next);
      final prevNext = _distance.as(LengthUnit.Meter, previous, next);
      final deviation = _distancePointToSegmentMeters(
        point: current,
        segmentStart: previous,
        segmentEnd: next,
      );

      final isMinorAlleyDetour =
          prevCurrent <= 140 && currentNext <= 140 && prevNext <= 240;
      final isNearMainCorridor = deviation <= 45;
      final detourRatio = prevNext <= 1
          ? double.infinity
          : (prevCurrent + currentNext) / prevNext;
      final isLoopIntoAlley = prevCurrent <= 220 &&
          currentNext <= 220 &&
          prevNext <= 120 &&
          detourRatio >= 1.95;

      if ((isMinorAlleyDetour && isNearMainCorridor) || isLoopIntoAlley) {
        continue;
      }

      filtered.add(current);
    }
    filtered.add(raw.last);

    return _dedupeWaypoints(filtered, minDistanceMeters: 8);
  }

  List<LatLng> _buildMainRoadAnchors(List<LatLng> waypoints) {
    if (waypoints.length <= 2) {
      return waypoints;
    }

    final anchors = <LatLng>[waypoints.first];
    for (var index = 1; index < waypoints.length - 1; index++) {
      final previous = anchors.last;
      final current = waypoints[index];
      final next = waypoints[index + 1];

      final prevCurrent = _distance.as(LengthUnit.Meter, previous, current);
      final currentNext = _distance.as(LengthUnit.Meter, current, next);
      final prevNext = _distance.as(LengthUnit.Meter, previous, next);

      final ratio = prevNext <= 1
          ? double.infinity
          : (prevCurrent + currentNext) / prevNext;
      final isLikelyBranch = prevCurrent <= 260 &&
          currentNext <= 260 &&
          prevNext <= 160 &&
          ratio >= 1.85;

      if (!isLikelyBranch) {
        anchors.add(current);
      }
    }
    anchors.add(waypoints.last);

    return _dedupeWaypoints(anchors, minDistanceMeters: 20);
  }

  List<LatLng> _dedupeWaypoints(
    List<LatLng> waypoints, {
    required double minDistanceMeters,
  }) {
    if (waypoints.isEmpty) {
      return const <LatLng>[];
    }

    final deduped = <LatLng>[waypoints.first];
    for (final point in waypoints.skip(1)) {
      final previous = deduped.last;
      final distanceMeters = _distance.as(LengthUnit.Meter, previous, point);
      if (distanceMeters >= minDistanceMeters) {
        deduped.add(point);
      }
    }
    return deduped;
  }

  double _distancePointToSegmentMeters({
    required LatLng point,
    required LatLng segmentStart,
    required LatLng segmentEnd,
  }) {
    const metersPerDegreeLat = 110540.0;
    const metersPerDegreeLonAtEquator = 111320.0;

    final averageLatitudeRadians =
        ((segmentStart.latitude + segmentEnd.latitude + point.latitude) / 3) *
            (math.pi / 180);
    final lonScale =
        metersPerDegreeLonAtEquator * math.cos(averageLatitudeRadians).abs();

    const startX = 0.0;
    const startY = 0.0;
    final endX = (segmentEnd.longitude - segmentStart.longitude) * lonScale;
    final endY =
        (segmentEnd.latitude - segmentStart.latitude) * metersPerDegreeLat;
    final pointX = (point.longitude - segmentStart.longitude) * lonScale;
    final pointY =
        (point.latitude - segmentStart.latitude) * metersPerDegreeLat;

    final segmentLengthSquared = ((endX - startX) * (endX - startX)) +
        ((endY - startY) * (endY - startY));
    if (segmentLengthSquared == 0) {
      final dx = pointX - startX;
      final dy = pointY - startY;
      return math.sqrt((dx * dx) + (dy * dy));
    }

    final projection = (((pointX - startX) * (endX - startX)) +
            ((pointY - startY) * (endY - startY))) /
        segmentLengthSquared;
    final t = projection.clamp(0.0, 1.0);

    final closestX = startX + ((endX - startX) * t);
    final closestY = startY + ((endY - startY) * t);
    final dx = pointX - closestX;
    final dy = pointY - closestY;

    return math.sqrt((dx * dx) + (dy * dy));
  }

  bool _isSamePointList(List<LatLng> first, List<LatLng> second) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      final pointA = first[index];
      final pointB = second[index];
      if ((pointA.latitude - pointB.latitude).abs() > 0.000001 ||
          (pointA.longitude - pointB.longitude).abs() > 0.000001) {
        return false;
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<StationBloc, StationState>(
          listener: (context, state) {
            if (state is StationLoaded) {
              _syncStations(state.stations);

              // Load route geometries after stations are loaded
              _loadRouteGeometries();
            }
          },
        ),
        BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            _syncFavoriteFromAuth(state);
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
        body: _isLoadingRoute
            ? const LoadingIndicator()
            : Column(
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 20,
                      right: 20,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x0F0F172A),
                          blurRadius: 0,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFFF1F5F9)),
                                    ),
                                    child: const Icon(Icons.arrow_back,
                                        size: 16, color: Color(0xFF334155)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Chi tiết tuyến',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8))),
                                    Text(
                                      'Tuyến ${_route.routeCode}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 17,
                                          color: Color(0xFF0F172A)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: const Color(0xFFF1F5F9)),
                              ),
                              child: _isUpdatingFavorite
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: _isFavorite
                                          ? 'Bỏ tuyến yêu thích'
                                          : 'Lưu tuyến yêu thích',
                                      onPressed: _toggleFavorite,
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                              width: 40, height: 40),
                                      icon: Icon(
                                        _isFavorite
                                            ? Icons.bookmark_rounded
                                            : Icons.bookmark_outline_rounded,
                                        size: 16,
                                        color: _isFavorite
                                            ? const Color(0xFF0D9488)
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            dividerColor: Colors.transparent,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: const Color(0xFF0D9488),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0D9488)
                                      .withValues(alpha: 0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor: const Color(0xFF64748B),
                            labelStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            tabs: const [
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 16),
                                    SizedBox(width: 6),
                                    Text('Thông tin')
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.arrow_forward_rounded, size: 16),
                                    SizedBox(width: 6),
                                    Text('Chiều đi')
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.arrow_back_rounded, size: 16),
                                    SizedBox(width: 6),
                                    Text('Chiều về')
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildInfoTab(),
                        _buildDirectionTab(
                          _forwardStations,
                          'forward',
                          (_forwardRoute ?? _route).startPoint,
                          (_forwardRoute ?? _route).endPoint,
                          mapController: _forwardMapController,
                          routeGeometry: _forwardRouteGeometry,
                        ),
                        _buildDirectionTab(
                          _backwardStations,
                          'return',
                          (_backwardRoute ?? _route).startPoint,
                          (_backwardRoute ?? _route).endPoint,
                          mapController: _backwardMapController,
                          routeGeometry: _backwardRouteGeometry,
                        ),
                      ],
                    ),
                  ),
                  // Buy ticket
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: ElevatedButton(
                          onPressed:
                              _isLoadingRoute ? null : _onBuyTicketPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 4,
                            shadowColor:
                                const Color(0xFF0D9488).withValues(alpha: 0.25),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.attach_money_rounded, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Mua vé tuyến này',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _onBuyTicketPressed() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RouteTicketPaymentScreen(route: _route),
      ),
    );
  }

  Color _getRouteColor(String code) {
    final colors = [
      const Color(0xFF0F9B8E), // teal
      const Color(0xFF2563EB), // blue
      const Color(0xFFF59E0B), // amber
      const Color(0xFF8B5CF6), // purple
      const Color(0xFFEC4899), // pink
    ];
    final hash = code.hashCode;
    return colors[hash % colors.length];
  }

  Widget _buildInfoTab() {
    final routeColor = _getRouteColor(_route.routeCode);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Hero Card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(height: 6, width: double.infinity, color: routeColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: routeColor,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _route.routeCode,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _route.routeName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 16),
                      // Endpoints pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFCCFBF1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                            color: const Color(0xFF0D9488),
                                            width: 2),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(_route.startPoint,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF334155))),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                    width: 32,
                                    height: 1,
                                    color: const Color(0xFFCBD5E1)),
                                const Icon(Icons.arrow_forward_rounded,
                                    size: 16, color: Color(0xFF94A3B8)),
                                Container(
                                    width: 32,
                                    height: 1,
                                    color: const Color(0xFFCBD5E1)),
                              ],
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF1F2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.place_rounded,
                                        size: 16, color: Color(0xFFF43F5E)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(_route.endPoint,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF334155))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Station count
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SỐ LƯỢNG TRẠM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDFA),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_forwardCodes.length}',
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F766E)),
                            ),
                            const Text('trạm · Chiều đi',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF0D9488))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_backwardCodes.length}',
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF334155)),
                            ),
                            const Text('trạm · Chiều về',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // General Information
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'THÔNG TIN CHUNG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildInfoRow(Icons.directions_bus_rounded,
                        'Loại phương tiện', _route.vehicleType),
                    _buildInfoRow(Icons.business_rounded, 'Nhà vận hành',
                        _route.operatorName),
                    _buildInfoRow(Icons.phone_rounded, 'Số điện thoại',
                        _route.phoneNumber),
                    _buildInfoRow(Icons.schedule_rounded, 'Giờ hoạt động',
                        '${_route.operatingTime.from} - ${_route.operatingTime.to}'),
                    _buildInfoRow(
                        Icons.repeat_rounded, 'Tần suất', _route.frequency),
                    _buildInfoRow(Icons.timer_outlined, 'Thời gian chuyến',
                        _route.tripTime),
                    _buildInfoRow(Icons.calendar_today_rounded,
                        'Số chuyến / ngày', '${_route.numTrips} chuyến'),
                    _buildInfoRow(Icons.straighten_rounded, 'Tổng quãng đường',
                        '${_route.totalDistance.toStringAsFixed(1)} km'),
                    _buildInfoRow(Icons.attach_money_rounded, 'Giá vé',
                        _route.baseFare.join(' - ')),
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionTab(
    List<Station> stations,
    String direction,
    String fromStr,
    String toStr, {
    required MapController mapController,
    List<LatLng>? routeGeometry,
  }) {
    if (_isLoadingStations) {
      return const LoadingIndicator();
    }

    if (stations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 64, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text('Chưa có thông tin trạm cho chiều này',
                style: TextStyle(color: Color(0xFF64748B))),
          ],
        ),
      );
    }

    // Calculate bounds
    final latitudes = stations.map((s) => s.latitude);
    final longitudes = stations.map((s) => s.longitude);

    final centerLat = (latitudes.reduce((a, b) => a + b)) / latitudes.length;
    final centerLon = (longitudes.reduce((a, b) => a + b)) / longitudes.length;

    final polylinePoints = routeGeometry ??
        stations.map((s) => LatLng(s.latitude, s.longitude)).toList();

    final routeColor = _getRouteColor(_route.routeCode);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Direction Header
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: routeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    direction == 'forward'
                        ? Icons.arrow_forward_rounded
                        : Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        direction == 'forward' ? 'Chiều đi' : 'Chiều về',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                      Text(
                        '$fromStr → $toStr',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${stations.length} trạm',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),

          // Mini Map
          Container(
            height: 280,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            clipBehavior: Clip.antiAlias,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: LatLng(centerLat, centerLon),
                initialZoom: 13.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                ),
              ),
              children: [
                AppTileLayer.standard(),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: polylinePoints,
                      strokeWidth: 5.0,
                      color: Colors.white,
                    ),
                    Polyline(
                      points: polylinePoints,
                      strokeWidth: 3.5,
                      color: routeColor,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    ...stations.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final station = entry.value;
                      final isFirst = idx == 0;
                      final isLast = idx == stations.length - 1;
                      return Marker(
                        point: LatLng(station.latitude, station.longitude),
                        child: GestureDetector(
                          onTap: () => _animateMapToStation(
                            mapController,
                            station,
                            idx + 1,
                          ),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  isFirst || isLast ? routeColor : Colors.white,
                              border: Border.all(
                                color: routeColor,
                                width: 2,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              isLast ? '✓' : '${idx + 1}',
                              style: TextStyle(
                                fontSize: isLast ? 14 : 11,
                                fontWeight: FontWeight.w600,
                                color: isFirst || isLast
                                    ? Colors.white
                                    : routeColor,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),

          // Timeline
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: stations.asMap().entries.map((entry) {
                final idx = entry.key;
                final station = entry.value;
                final isFirst = idx == 0;
                final isLast = idx == stations.length - 1;

                return InkWell(
                  onTap: () => _animateMapToStation(
                    mapController,
                    station,
                    idx + 1,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Timeline Indicator
                      SizedBox(
                        width: 48,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 8,
                              child: Container(
                                width: 2,
                                color: isFirst
                                    ? Colors.transparent
                                    : const Color(0xFFF1F5F9),
                              ),
                            ),
                            Container(
                              width: 28,
                              height: 28,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: isFirst || isLast
                                    ? routeColor
                                    : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: isFirst || isLast
                                  ? Icon(
                                      isFirst
                                          ? Icons.circle
                                          : Icons.place_rounded,
                                      size: isFirst ? 10 : 14,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      '${idx + 1}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                            ),
                            SizedBox(
                              height: 8,
                              child: Container(
                                width: 2,
                                color: isLast
                                    ? Colors.transparent
                                    : const Color(0xFFF1F5F9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Content
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            border: isLast
                                ? null
                                : const Border(
                                    bottom:
                                        BorderSide(color: Color(0xFFF8FAFC)),
                                  ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  station.stationName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isFirst || isLast
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isFirst || isLast
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                              if (isFirst || isLast)
                                Container(
                                  margin:
                                      const EdgeInsets.only(right: 16, left: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: routeColor,
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    isFirst ? 'ĐI' : 'ĐẾN',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _animateMapToStation(
    MapController mapController,
    Station station,
    int order,
  ) {
    // Animate map to station
    mapController.move(
      LatLng(station.latitude, station.longitude),
      15.0,
    );
    // Show station info
    _showStationInfo(station, order);
  }

  void _showStationInfo(Station station, int order) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navOverlap = HomeNavigationBar.isVisible.value
        ? kBottomNavigationBarHeight + bottomInset
        : bottomInset;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: navOverlap),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCCFBF1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$order',
                            style: const TextStyle(
                              color: Color(0xFF0D9488),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                station.stationName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                station.stationCode,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Address
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 18,
                            color: Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              station.fullAddress,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF475569),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // GPS Coordinates
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.gps_fixed_rounded,
                            size: 18,
                            color: Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${station.latitude.toStringAsFixed(6)}, ${station.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: const Color(0xFF0D9488)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
