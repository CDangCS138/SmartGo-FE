import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/di/injection.dart';
import '../../../core/platform/sse_client.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_sizes.dart';
import '../../../data/datasources/bus_simulation_remote_data_source.dart';
import '../../../data/models/bus_simulation_models.dart';
import '../../../domain/entities/route.dart';
import '../../../domain/entities/station.dart';
import '../../blocs/route/route_bloc.dart';
import '../../blocs/route/route_event.dart';
import '../../blocs/route/route_state.dart';
import '../../blocs/station/station_bloc.dart';
import '../../blocs/station/station_event.dart';
import '../../blocs/station/station_state.dart';

class BusSimulationScreen extends StatefulWidget {
  final String? initialRouteId;
  final String? initialTripId;
  final String? initialStationId;

  const BusSimulationScreen({
    super.key,
    this.initialRouteId,
    this.initialTripId,
    this.initialStationId,
  });

  @override
  State<BusSimulationScreen> createState() => _BusSimulationScreenState();
}

class _BusSimulationScreenState extends State<BusSimulationScreen>
    with SingleTickerProviderStateMixin {
  static const LatLng _defaultMapCenter = LatLng(10.8231, 106.6297);

  final http.Client _client = http.Client();
  final MapController _mapController = MapController();

  late final StorageService _storageService;
  late final BusSimulationRemoteDataSource _dataSource;
  late final TabController _tabController;

  final TextEditingController _liveSearchController = TextEditingController();
  final TextEditingController _tripsSearchController = TextEditingController();
  final TextEditingController _stationEtaSearchController =
      TextEditingController();

  String _liveSearchQuery = '';
  String _tripsSearchQuery = '';
  String _stationEtaSearchQuery = '';

  String? _selectedRouteId;
  String? _selectedStationId;

  bool _didAutoSelectRoute = false;
  bool _shouldAutoCenterMap = true;

  bool _isTripsLoading = false;
  bool _isLiveLoading = false;
  bool _isStationEtaLoading = false;

  String? _tripsError;
  String? _liveError;
  String? _stationEtaError;

  List<BusSimulationTrip> _trips = const <BusSimulationTrip>[];
  List<BusSimulationPosition> _livePositions = const <BusSimulationPosition>[];
  List<UpcomingBusAtStation> _stationEtas = const <UpcomingBusAtStation>[];

  DateTime? _tripsUpdatedAt;
  DateTime? _liveUpdatedAt;
  DateTime? _stationEtaUpdatedAt;

  bool _routeRealtimeEnabled = false;
  String _routeRealtimeMode = 'idle';
  Timer? _routePollingTimer;
  SseClient? _routeSseClient;
  StreamSubscription<String>? _routeSseSubscription;

  bool _stationRealtimeEnabled = false;
  String _stationRealtimeMode = 'idle';
  Timer? _stationPollingTimer;
  SseClient? _stationSseClient;
  StreamSubscription<String>? _stationSseSubscription;

  @override
  void initState() {
    super.initState();
    _storageService = getIt<StorageService>();
    _dataSource = BusSimulationRemoteDataSource(client: _client);

    _selectedRouteId = _normalizeId(widget.initialRouteId);
    _selectedStationId = _normalizeId(widget.initialStationId);

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChanged);

    _liveSearchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _liveSearchQuery = _liveSearchController.text.trim().toLowerCase();
      });
    });

    _tripsSearchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _tripsSearchQuery = _tripsSearchController.text.trim().toLowerCase();
      });
    });

    _stationEtaSearchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _stationEtaSearchQuery =
            _stationEtaSearchController.text.trim().toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSeedDataLoaded();
      if (widget.initialTripId != null &&
          widget.initialTripId!.trim().isNotEmpty) {
        _openTripDetail(widget.initialTripId!.trim());
      }
    });
  }

  @override
  void dispose() {
    _stopAllRealtime(updateState: false);

    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();

    _liveSearchController.dispose();
    _tripsSearchController.dispose();
    _stationEtaSearchController.dispose();

    _client.close();
    super.dispose();
  }

  void _ensureSeedDataLoaded() {
    final routeBloc = context.read<RouteBloc>();
    final stationBloc = context.read<StationBloc>();

    final routeState = routeBloc.state;
    if (routeState is! RouteLoaded &&
        routeState is! RouteLoading &&
        routeState is! RouteLoadingMore) {
      routeBloc.add(const FetchAllRoutesEvent(page: 1, limit: 200));
    }

    final stationState = stationBloc.state;
    if (stationState is! StationLoaded && stationState is! StationLoading) {
      stationBloc.add(const FetchAllStationsEvent(page: 1, limit: 5000));
    }
  }

  void _handleTabChanged() {
    if (!mounted || _tabController.indexIsChanging) {
      return;
    }

    // Live tab => auto realtime for buses
    if (_tabController.index == 0) {
      _startRouteRealtimeForLiveTab();
    } else {
      _stopRouteRealtime();
    }

    // Stations tab => auto realtime for selected station
    if (_tabController.index == 2 && _selectedStationId != null) {
      _startStationRealtimeForSelectedStation();
    } else if (_tabController.index != 2) {
      _stopStationRealtime();
    }
  }

  String? _normalizeId(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _activeRouteId() {
    return _normalizeId(_selectedRouteId);
  }

  String? _readToken() {
    final token = _storageService.getAuthToken();
    if (token == null || token.trim().isEmpty) {
      return null;
    }
    return token.trim();
  }

  void _showToast(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onRouteSelected(
    BusRoute route, {
    bool forceReload = false,
  }) async {
    if (!forceReload && _selectedRouteId == route.id) {
      return;
    }

    setState(() {
      _selectedRouteId = route.id;
      _selectedStationId = null;

      _trips = const <BusSimulationTrip>[];
      _livePositions = const <BusSimulationPosition>[];
      _stationEtas = const <UpcomingBusAtStation>[];

      _tripsError = null;
      _liveError = null;
      _stationEtaError = null;

      _tripsUpdatedAt = null;
      _liveUpdatedAt = null;
      _stationEtaUpdatedAt = null;

      _shouldAutoCenterMap = true;
    });

    _stopRouteRealtime();
    _stopStationRealtime();

    // As requested: load route schedule first when opening/changing route.
    await _loadTripsForSelectedRoute();

    if (_tabController.index == 0) {
      await _startRouteRealtimeForLiveTab();
    }
  }

  BusRoute _resolvePreferredRoute(List<BusRoute> routes) {
    if (_selectedRouteId != null) {
      for (final route in routes) {
        if (route.id == _selectedRouteId) {
          return route;
        }
      }
    }

    for (final route in routes) {
      if (route.status == RouteStatus.active) {
        return route;
      }
    }

    return routes.first;
  }

  void _bootstrapRouteSelectionIfNeeded(List<BusRoute> routes) {
    if (_didAutoSelectRoute || routes.isEmpty) {
      return;
    }

    final preferred = _resolvePreferredRoute(routes);
    _didAutoSelectRoute = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _onRouteSelected(preferred, forceReload: true);
    });
  }

  Future<void> _loadTripsForSelectedRoute({bool silent = false}) async {
    final routeId = _activeRouteId();
    if (routeId == null) {
      if (!silent) {
        setState(() {
          _tripsError = 'Không có tuyến để tải danh sách chuyến trong ngày.';
        });
      }
      return;
    }

    if (!silent) {
      setState(() {
        _isTripsLoading = true;
        _tripsError = null;
      });
    }

    try {
      final trips = await _dataSource.getRouteTrips(
        routeId: routeId,
        accessToken: _readToken(),
      );

      trips.sort((a, b) {
        final ta = a.departureTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.departureTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _trips = trips;
        _tripsUpdatedAt = DateTime.now();
        _isTripsLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isTripsLoading = false;
        _tripsError = error.toString();
      });
    }
  }

  Future<void> _loadLivePositionsForSelectedRoute({bool silent = false}) async {
    final routeId = _activeRouteId();
    if (routeId == null) {
      if (!silent) {
        setState(() {
          _liveError = 'Không có tuyến để theo dõi vị trí thời gian thực.';
        });
      }
      return;
    }

    if (!silent) {
      setState(() {
        _isLiveLoading = true;
        _liveError = null;
      });
    }

    try {
      final positions = await _dataSource.getRoutePositions(
        routeId: routeId,
        accessToken: _readToken(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _livePositions = positions;
        _liveUpdatedAt = DateTime.now();
        _isLiveLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLiveLoading = false;
        _liveError = error.toString();
      });
    }
  }

  Future<void> _loadStationEtaForSelectedStation({bool silent = false}) async {
    final stationId = _selectedStationId;
    if (stationId == null || stationId.trim().isEmpty) {
      if (!silent) {
        setState(() {
          _stationEtaError = 'Vui lòng chọn trạm để xem xe sắp tới.';
        });
      }
      return;
    }

    if (!silent) {
      setState(() {
        _isStationEtaLoading = true;
        _stationEtaError = null;
      });
    }

    try {
      final values = await _dataSource.getStationEta(
        stationId: stationId,
        accessToken: _readToken(),
      );

      values.sort((a, b) {
        final ta = a.eta.eta ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.eta.eta ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _stationEtas = values;
        _stationEtaUpdatedAt = DateTime.now();
        _isStationEtaLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isStationEtaLoading = false;
        _stationEtaError = error.toString();
      });
    }
  }

  Future<void> _onStationSelected(String stationId) async {
    final normalized = stationId.trim();
    if (normalized.isEmpty || normalized == _selectedStationId) {
      return;
    }

    setState(() {
      _selectedStationId = normalized;
      _stationEtaError = null;
    });

    _stopStationRealtime();
    await _loadStationEtaForSelectedStation();

    if (_tabController.index == 2) {
      await _startStationRealtimeForSelectedStation();
    }
  }

  Future<void> _startRouteRealtimeForLiveTab() async {
    final routeId = _activeRouteId();
    if (routeId == null || _routeRealtimeEnabled) {
      return;
    }

    if (kIsWeb) {
      final token = _readToken();
      if (token != null) {
        final uri = _dataSource.routePositionsStreamUri(
          routeId: routeId,
          token: token,
        );

        final sseClient = createSseClient();
        _routeSseClient = sseClient;

        setState(() {
          _routeRealtimeEnabled = true;
          _routeRealtimeMode = 'sse';
        });

        _routeSseSubscription = sseClient.connect(uri).listen(
          (payload) {
            try {
              final next = _dataSource.parseRoutePositionsEvent(payload);
              if (!mounted) {
                return;
              }

              setState(() {
                _livePositions = next;
                _liveUpdatedAt = DateTime.now();
                _liveError = null;
              });
            } catch (_) {
              // Ignore malformed stream packet.
            }
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            _startRoutePollingFallback(routeId, showNotice: true);
          },
        );

        await _loadLivePositionsForSelectedRoute(silent: true);
        return;
      }
    }

    _startRoutePollingFallback(routeId, showNotice: false);
  }

  void _startRoutePollingFallback(
    String routeId, {
    required bool showNotice,
  }) {
    _stopRouteRealtime();

    setState(() {
      _routeRealtimeEnabled = true;
      _routeRealtimeMode = 'polling';
    });

    _routePollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted) {
          return;
        }
        _loadLivePositionsForSelectedRoute(silent: true);
      },
    );

    _loadLivePositionsForSelectedRoute(silent: true);

    if (showNotice) {
      _showToast(
        'Kết nối trực tiếp chưa ổn định, ứng dụng sẽ tự cập nhật vị trí mỗi vài giây.',
      );
    }
  }

  void _stopRouteRealtime({bool updateState = true}) {
    _routePollingTimer?.cancel();
    _routePollingTimer = null;

    _routeSseSubscription?.cancel();
    _routeSseSubscription = null;

    _routeSseClient?.close();
    _routeSseClient = null;

    if (updateState && mounted) {
      setState(() {
        _routeRealtimeEnabled = false;
        _routeRealtimeMode = 'idle';
      });
    } else {
      _routeRealtimeEnabled = false;
      _routeRealtimeMode = 'idle';
    }
  }

  Future<void> _startStationRealtimeForSelectedStation() async {
    final stationId = _selectedStationId;
    if (stationId == null ||
        stationId.trim().isEmpty ||
        _stationRealtimeEnabled) {
      return;
    }

    if (kIsWeb) {
      final token = _readToken();
      if (token != null) {
        final uri = _dataSource.stationEtaStreamUri(
          stationId: stationId,
          token: token,
        );

        final sseClient = createSseClient();
        _stationSseClient = sseClient;

        setState(() {
          _stationRealtimeEnabled = true;
          _stationRealtimeMode = 'sse';
        });

        _stationSseSubscription = sseClient.connect(uri).listen(
          (payload) {
            try {
              final next = _dataSource.parseStationEtaEvent(payload);
              next.sort((a, b) {
                final ta = a.eta.eta ?? DateTime.fromMillisecondsSinceEpoch(0);
                final tb = b.eta.eta ?? DateTime.fromMillisecondsSinceEpoch(0);
                return ta.compareTo(tb);
              });

              if (!mounted) {
                return;
              }

              setState(() {
                _stationEtas = next;
                _stationEtaUpdatedAt = DateTime.now();
                _stationEtaError = null;
              });
            } catch (_) {
              // Ignore malformed stream packet.
            }
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            _startStationPollingFallback(stationId, showNotice: true);
          },
        );

        await _loadStationEtaForSelectedStation(silent: true);
        return;
      }
    }

    _startStationPollingFallback(stationId, showNotice: false);
  }

  void _startStationPollingFallback(
    String stationId, {
    required bool showNotice,
  }) {
    _stopStationRealtime();

    setState(() {
      _stationRealtimeEnabled = true;
      _stationRealtimeMode = 'polling';
    });

    _stationPollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted) {
          return;
        }
        _loadStationEtaForSelectedStation(silent: true);
      },
    );

    _loadStationEtaForSelectedStation(silent: true);

    if (showNotice) {
      _showToast(
        'Kết nối trực tiếp tại trạm chưa ổn định, ứng dụng sẽ tự cập nhật xe đến mỗi vài giây.',
      );
    }
  }

  void _stopStationRealtime({bool updateState = true}) {
    _stationPollingTimer?.cancel();
    _stationPollingTimer = null;

    _stationSseSubscription?.cancel();
    _stationSseSubscription = null;

    _stationSseClient?.close();
    _stationSseClient = null;

    if (updateState && mounted) {
      setState(() {
        _stationRealtimeEnabled = false;
        _stationRealtimeMode = 'idle';
      });
    } else {
      _stationRealtimeEnabled = false;
      _stationRealtimeMode = 'idle';
    }
  }

  void _stopAllRealtime({bool updateState = true}) {
    _stopRouteRealtime(updateState: updateState);
    _stopStationRealtime(updateState: updateState);
  }

  Future<void> _openRoutePicker(List<BusRoute> routes) async {
    if (routes.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return ListView.separated(
          itemCount: routes.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final route = routes[index];
            final selected = route.id == _selectedRouteId;
            return ListTile(
              leading: Icon(
                Icons.directions_bus_filled_rounded,
                color: selected ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text('Tuyến ${route.routeCode}'),
              subtitle: Text('${route.startPoint} -> ${route.endPoint}'),
              trailing: selected ? const Icon(Icons.check_rounded) : null,
              onTap: () {
                Navigator.of(context).pop();
                _onRouteSelected(route);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openTripDetail(
    String tripId, {
    BusSimulationPosition? seedPosition,
  }) async {
    final normalized = tripId.trim();
    if (normalized.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _TripDetailSheet(
          tripId: normalized,
          token: _readToken(),
          dataSource: _dataSource,
          initialPosition: seedPosition,
        );
      },
    );
  }

  List<BusRoute> _extractRoutes(RouteState state) {
    if (state is RouteLoaded) {
      return state.routes;
    }
    if (state is RouteLoadingMore) {
      return state.currentRoutes;
    }
    return const <BusRoute>[];
  }

  List<Station> _extractStations(StationState state) {
    if (state is StationLoaded) {
      return state.stations;
    }
    return const <Station>[];
  }

  BusRoute? _selectedRoute(List<BusRoute> routes) {
    final id = _activeRouteId();
    if (id == null) {
      return null;
    }

    for (final route in routes) {
      if (route.id == id) {
        return route;
      }
    }

    return null;
  }

  BusSimulationStatus _overallStatus() {
    if (_livePositions
        .any((item) => item.status == BusSimulationStatus.running)) {
      return BusSimulationStatus.running;
    }

    if (_trips.any((item) => item.status == BusSimulationStatus.running)) {
      return BusSimulationStatus.running;
    }

    if (_trips.any((item) => item.status == BusSimulationStatus.scheduled)) {
      return BusSimulationStatus.scheduled;
    }

    if (_trips.isNotEmpty &&
        _trips.every((item) => item.status == BusSimulationStatus.completed)) {
      return BusSimulationStatus.completed;
    }

    return BusSimulationStatus.unknown;
  }

  List<Station> _orderedRouteStations(
    BusRoute? route,
    List<Station> allStations,
  ) {
    if (route == null) {
      return const <Station>[];
    }

    final byId = <String, Station>{
      for (final station in allStations) station.id: station,
    };
    final byCode = <String, Station>{
      for (final station in allStations) station.stationCode: station,
    };

    final collected = <Station>[];
    final seen = <String>{};

    if (_trips.isNotEmpty && _trips.first.stationIds.isNotEmpty) {
      for (final id in _trips.first.stationIds) {
        final station = byId[id];
        if (station != null && seen.add(station.id)) {
          collected.add(station);
        }
      }
    }

    if (collected.isEmpty && route.routeForwardCodes.isNotEmpty) {
      for (final code in route.routeForwardCodes.keys) {
        final station = byCode[code];
        if (station != null && seen.add(station.id)) {
          collected.add(station);
        }
      }
    }

    if (collected.isEmpty && route.routeBackwardCodes.isNotEmpty) {
      for (final code in route.routeBackwardCodes.keys) {
        final station = byCode[code];
        if (station != null && seen.add(station.id)) {
          collected.add(station);
        }
      }
    }

    return collected;
  }

  List<LatLng> _routePolylinePoints(
    BusRoute? route,
    List<Station> allStations,
  ) {
    final fromStations = _orderedRouteStations(route, allStations)
        .map((station) => LatLng(station.latitude, station.longitude))
        .toList();

    if (fromStations.length >= 2) {
      return fromStations;
    }

    for (final position in _livePositions) {
      if (position.stationEtas.isEmpty) {
        continue;
      }

      final sorted = [...position.stationEtas]
        ..sort((a, b) => a.stationIndex.compareTo(b.stationIndex));
      final points =
          sorted.map((eta) => LatLng(eta.latitude, eta.longitude)).toList();

      if (points.length >= 2) {
        return points;
      }
    }

    return const <LatLng>[];
  }

  List<_MapStationMarkerData> _mapStationMarkers(
    BusRoute? route,
    List<Station> allStations,
  ) {
    final ordered = _orderedRouteStations(route, allStations);
    if (ordered.isNotEmpty) {
      return ordered
          .map(
            (station) => _MapStationMarkerData(
              key: station.id,
              name: station.stationName,
              point: LatLng(station.latitude, station.longitude),
            ),
          )
          .toList();
    }

    final map = <String, _MapStationMarkerData>{};
    for (final position in _livePositions) {
      for (final eta in position.stationEtas) {
        final key = eta.stationId.isNotEmpty
            ? eta.stationId
            : '${eta.latitude}-${eta.longitude}-${eta.stationIndex}';
        map[key] = _MapStationMarkerData(
          key: key,
          name: eta.stationName,
          point: LatLng(eta.latitude, eta.longitude),
        );
      }
    }

    return map.values.toList();
  }

  List<BusSimulationPosition> _liveBusesForMap() {
    final running = _livePositions
        .where((item) => item.status == BusSimulationStatus.running)
        .toList();

    if (running.isNotEmpty) {
      return running;
    }

    return _livePositions;
  }

  List<BusSimulationPosition> _liveBusesForList() {
    final query = _liveSearchQuery;

    final source = _liveBusesForMap();
    final filtered = source.where((item) {
      if (query.isEmpty) {
        return true;
      }

      return item.tripId.toLowerCase().contains(query) ||
          item.routeCode.toLowerCase().contains(query) ||
          item.routeName.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) => a.remainingMinutes.compareTo(b.remainingMinutes));
    return filtered;
  }

  List<BusSimulationTrip> _filteredTrips() {
    final query = _tripsSearchQuery;
    final result = _trips.where((item) {
      if (query.isEmpty) {
        return true;
      }

      return item.tripId.toLowerCase().contains(query) ||
          item.routeCode.toLowerCase().contains(query) ||
          item.routeName.toLowerCase().contains(query);
    }).toList();

    result.sort((a, b) {
      final ta = a.departureTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.departureTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    return result;
  }

  List<Station> _stationCandidates(List<Station> allStations, BusRoute? route) {
    final ordered = _orderedRouteStations(route, allStations);
    if (ordered.isNotEmpty) {
      return ordered;
    }

    return allStations
        .where((station) => station.status == StationStatus.ACTIVE)
        .take(120)
        .toList();
  }

  List<UpcomingBusAtStation> _filteredStationEtas() {
    final query = _stationEtaSearchQuery;
    final result = _stationEtas.where((item) {
      if (query.isEmpty) {
        return true;
      }

      return item.tripId.toLowerCase().contains(query) ||
          item.routeCode.toLowerCase().contains(query) ||
          item.routeName.toLowerCase().contains(query) ||
          item.eta.stationName.toLowerCase().contains(query);
    }).toList();

    result.sort((a, b) => a.eta.minutesAway.compareTo(b.eta.minutesAway));
    return result;
  }

  LatLng _mapCenter(
    List<BusSimulationPosition> buses,
    List<_MapStationMarkerData> stations,
  ) {
    if (buses.isNotEmpty) {
      return LatLng(buses.first.latitude, buses.first.longitude);
    }

    if (stations.isNotEmpty) {
      return stations.first.point;
    }

    return _defaultMapCenter;
  }

  void _autoCenterMap(LatLng center) {
    if (!_shouldAutoCenterMap) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      try {
        _mapController.move(center, 13.5);
        _shouldAutoCenterMap = false;
      } catch (_) {
        // Ignore transient map controller errors.
      }
    });
  }

  Color _statusColor(BusSimulationStatus status, ColorScheme scheme) {
    switch (status) {
      case BusSimulationStatus.running:
        return AppColors.busRunning;
      case BusSimulationStatus.scheduled:
        return AppColors.busScheduled;
      case BusSimulationStatus.completed:
        return AppColors.busCompleted;
      case BusSimulationStatus.unknown:
        return scheme.outline;
    }
  }

  String _statusLabel(BusSimulationStatus status) {
    switch (status) {
      case BusSimulationStatus.running:
        return 'ĐANG CHẠY';
      case BusSimulationStatus.scheduled:
        return 'LÊN LỊCH';
      case BusSimulationStatus.completed:
        return 'HOÀN THÀNH';
      case BusSimulationStatus.unknown:
        return 'KHÔNG RÕ';
    }
  }

  String _fmtDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');

    return '$dd/$mm/$yy $hh:$min';
  }

  String _fmtClock(DateTime? value) {
    if (value == null) {
      return '--:--:--';
    }

    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$min:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final routeState = context.watch<RouteBloc>().state;
    final stationState = context.watch<StationBloc>().state;

    final routes = _extractRoutes(routeState);
    final stations = _extractStations(stationState);

    _bootstrapRouteSelectionIfNeeded(routes);

    final selectedRoute = _selectedRoute(routes);
    final overallStatus = _overallStatus();

    final directionText = selectedRoute == null
        ? 'Đang tải dữ liệu tuyến...'
        : '${selectedRoute.startPoint} -> ${selectedRoute.endPoint}';

    final mapBuses = _liveBusesForMap();
    final mapStations = _mapStationMarkers(selectedRoute, stations);
    final mapCenter = _mapCenter(mapBuses, mapStations);
    _autoCenterMap(mapCenter);

    final mapPolylines = _routePolylinePoints(selectedRoute, stations);

    final mapHeight = (MediaQuery.of(context).size.height * 0.54)
        .clamp(340.0, 520.0)
        .toDouble();

    return MultiBlocListener(
      listeners: [
        BlocListener<RouteBloc, RouteState>(
          listener: (context, state) {
            if (state is RouteError) {
              setState(() {
                if (_trips.isEmpty) {
                  _tripsError = state.message;
                }
                if (_livePositions.isEmpty) {
                  _liveError = state.message;
                }
              });
              return;
            }

            if (state is! RouteLoaded) {
              return;
            }

            if (state.routes.isEmpty) {
              setState(() {
                if (_trips.isEmpty) {
                  _tripsError =
                      'Không có dữ liệu tuyến để tải danh sách chuyến.';
                }
                if (_livePositions.isEmpty) {
                  _liveError = 'Không có dữ liệu tuyến để hiển thị vị trí xe.';
                }
              });
              return;
            }

            if (_didAutoSelectRoute) {
              return;
            }

            final preferred = _resolvePreferredRoute(state.routes);

            _didAutoSelectRoute = true;
            _onRouteSelected(preferred, forceReload: true);
          },
        ),
        BlocListener<StationBloc, StationState>(
          listener: (context, state) {
            if (state is! StationError) {
              return;
            }

            setState(() {
              if (_stationEtas.isEmpty) {
                _stationEtaError = state.message;
              }
            });
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.home);
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tuyến ${selectedRoute?.routeCode ?? '--'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                directionText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            if (routes.length > 1)
              IconButton(
                onPressed: () => _openRoutePicker(routes),
                icon: const Icon(Icons.swap_horiz_rounded),
                tooltip: 'Đổi tuyến',
              ),
            Padding(
              padding: const EdgeInsets.only(right: AppSizes.sm),
              child: _StatusChip(
                label: _statusLabel(overallStatus),
                color:
                    _statusColor(overallStatus, Theme.of(context).colorScheme),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: mapHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md,
                  AppSizes.sm,
                  AppSizes.md,
                  AppSizes.sm,
                ),
                child: _buildMapPanel(
                  buses: mapBuses,
                  stations: mapStations,
                  center: mapCenter,
                  polylinePoints: mapPolylines,
                ),
              ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Trực tiếp'),
                  Tab(text: 'Chuyến'),
                  Tab(text: 'Trạm'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLiveTab(),
                  _buildTripsTab(),
                  _buildStationsTab(stations, selectedRoute),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPanel({
    required List<BusSimulationPosition> buses,
    required List<_MapStationMarkerData> stations,
    required LatLng center,
    required List<LatLng> polylinePoints,
  }) {
    final showLoading = _isLiveLoading && buses.isEmpty && stations.isEmpty;
    final showError = _liveError != null && buses.isEmpty && stations.isEmpty;

    if (showLoading) {
      return _StateCard.loading(label: 'Đang cập nhật vị trí xe...');
    }

    if (showError) {
      return _StateCard.error(
        title: 'Không tải được bản đồ thời gian thực',
        message: _liveError!,
      );
    }

    final markers = <Marker>[];

    for (final station in stations) {
      final selected = station.key == _selectedStationId;
      markers.add(
        Marker(
          width: selected ? 36 : 28,
          height: selected ? 36 : 28,
          point: station.point,
          child: Tooltip(
            message: station.name,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.busStationMarker,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: selected ? 3 : 2,
                ),
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: selected ? 18 : 14,
              ),
            ),
          ),
        ),
      );
    }

    for (final bus in buses) {
      final busColor = _statusColor(bus.status, Theme.of(context).colorScheme);
      markers.add(
        Marker(
          width: 42,
          height: 42,
          point: LatLng(bus.latitude, bus.longitude),
          child: GestureDetector(
            onTap: () => _openTripDetail(bus.tripId, seedPosition: bus),
            child: Container(
              decoration: BoxDecoration(
                color: busColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_bus_filled_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13.5,
              minZoom: 10,
              maxZoom: 18.5,
              onPositionChanged: (_, __) {
                _shouldAutoCenterMap = false;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smartgo.app',
              ),
              if (polylinePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: polylinePoints,
                      color: Theme.of(context).colorScheme.primary,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
        Positioned(
          left: AppSizes.sm,
          top: AppSizes.sm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm,
              vertical: AppSizes.xs,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cập nhật ${_fmtClock(_liveUpdatedAt)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _routeRealtimeEnabled
                      ? (_routeRealtimeMode == 'sse'
                          ? 'Đang theo dõi trực tiếp'
                          : 'Đang tự động làm mới')
                      : 'Đã tạm dừng cập nhật',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTab() {
    final buses = _liveBusesForList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.md),
      children: [
        _buildSearchField(
          controller: _liveSearchController,
          hintText: 'Tìm xe theo chuyến/tuyến',
          prefixIcon: Icons.search_rounded,
        ),
        const SizedBox(height: AppSizes.sm),
        _buildMetaLine(
          left: '${buses.length} xe đang hiển thị',
          right: 'Cập nhật ${_fmtClock(_liveUpdatedAt)}',
        ),
        const SizedBox(height: AppSizes.sm),
        if (_isLiveLoading && buses.isEmpty)
          _StateCard.loading(label: 'Đang cập nhật danh sách xe...')
        else if (_liveError != null && buses.isEmpty)
          _StateCard.error(
            title: 'Không lấy được danh sách xe thời gian thực',
            message: _liveError!,
          )
        else if (buses.isEmpty)
          _StateCard.empty(
            title: 'Không có xe đang chạy',
            message: 'Hiện tại chưa có chuyến ĐANG CHẠY trong khung giờ này.',
          )
        else
          ...buses.map(_buildLiveBusCard),
      ],
    );
  }

  Widget _buildLiveBusCard(BusSimulationPosition bus) {
    final status = _statusLabel(bus.status);
    final statusColor = _statusColor(bus.status, Theme.of(context).colorScheme);
    final progress = bus.progressToNextStation.clamp(0, 1).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => _openTripDetail(bus.tripId, seedPosition: bus),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bus.routeCode,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusChip(label: status, color: statusColor),
                ],
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Còn lại ${bus.remainingMinutes.toStringAsFixed(1)} phút',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripsTab() {
    final trips = _filteredTrips();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.md),
      children: [
        _buildSearchField(
          controller: _tripsSearchController,
          hintText: 'Tìm theo chuyến / tuyến',
          prefixIcon: Icons.search_rounded,
        ),
        const SizedBox(height: AppSizes.sm),
        _buildMetaLine(
          left: '${trips.length} chuyến trong ngày',
          right: 'Cập nhật ${_fmtClock(_tripsUpdatedAt)}',
        ),
        const SizedBox(height: AppSizes.sm),
        if (_isTripsLoading)
          _StateCard.loading(label: 'Đang tải lịch chạy trong ngày...')
        else if (_tripsError != null)
          _StateCard.error(
            title: 'Không tải được danh sách chuyến',
            message: _tripsError!,
          )
        else if (trips.isEmpty)
          _StateCard.empty(
            title: 'Không có dữ liệu chuyến',
            message: 'Danh sách chuyến trong ngày hiện đang trống.',
          )
        else
          ...trips.map(_buildTripCard),
      ],
    );
  }

  Widget _buildTripCard(BusSimulationTrip trip) {
    final statusColor =
        _statusColor(trip.status, Theme.of(context).colorScheme);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => _openTripDetail(trip.tripId),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${trip.routeCode} • ${trip.routeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _StatusChip(
                    label: _statusLabel(trip.status),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              _InfoLine(
                label: 'Khởi hành',
                value: _fmtDateTime(trip.departureTime),
              ),
              _InfoLine(
                label: 'Đến dự kiến',
                value: _fmtDateTime(trip.expectedArrivalTime),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationsTab(List<Station> allStations, BusRoute? route) {
    final stationCandidates = _stationCandidates(allStations, route);
    final etas = _filteredStationEtas();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.md),
      children: [
        if (stationCandidates.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue:
                stationCandidates.any((s) => s.id == _selectedStationId)
                    ? _selectedStationId
                    : null,
            decoration: const InputDecoration(
              labelText: 'Chọn trạm',
            ),
            items: stationCandidates
                .map(
                  (station) => DropdownMenuItem<String>(
                    value: station.id,
                    child:
                        Text('${station.stationCode} - ${station.stationName}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              _onStationSelected(value);
            },
          )
        else
          _StateCard.empty(
            title: 'Không có trạm trong tuyến',
            message: 'Không tìm thấy danh sách trạm cho tuyến hiện tại.',
          ),
        const SizedBox(height: AppSizes.sm),
        _buildSearchField(
          controller: _stationEtaSearchController,
          hintText: 'Tìm tuyến/chuyến sắp tới',
          prefixIcon: Icons.search_rounded,
        ),
        const SizedBox(height: AppSizes.sm),
        _buildMetaLine(
          left: '${etas.length} xe sắp tới',
          right:
              '${_stationRealtimeEnabled ? (_stationRealtimeMode == 'sse' ? 'Đang theo dõi trực tiếp' : 'Đang tự động làm mới') : 'Đã tạm dừng cập nhật'} | Cập nhật ${_fmtClock(_stationEtaUpdatedAt)}',
        ),
        const SizedBox(height: AppSizes.sm),
        if (_isStationEtaLoading)
          _StateCard.loading(label: 'Đang tải danh sách xe sắp tới...')
        else if (_stationEtaError != null)
          _StateCard.error(
            title: 'Không tải được ETA của trạm',
            message: _stationEtaError!,
          )
        else if (_selectedStationId == null)
          _StateCard.empty(
            title: 'Chưa chọn trạm',
            message: 'Hãy chọn một trạm để xem xe sẽ đến trong 90 phút tới.',
          )
        else if (etas.isEmpty)
          _StateCard.empty(
            title: 'Không có xe sắp đến',
            message: 'Không có dữ liệu ETA trong cửa sổ 90 phút tới.',
          )
        else
          ...etas.map(_buildStationEtaCard),
      ],
    );
  }

  Widget _buildStationEtaCard(UpcomingBusAtStation item) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => _openTripDetail(item.tripId),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.routeCode} • ${item.routeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      'ETA ${_fmtDateTime(item.eta.eta)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.sm,
                  vertical: AppSizes.xs,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${item.eta.minutesAway.toStringAsFixed(1)}m',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(prefixIcon),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
      ),
    );
  }

  Widget _buildMetaLine({
    required String left,
    required String right,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          right,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _TripDetailSheet extends StatefulWidget {
  final String tripId;
  final String? token;
  final BusSimulationRemoteDataSource dataSource;
  final BusSimulationPosition? initialPosition;

  const _TripDetailSheet({
    required this.tripId,
    required this.token,
    required this.dataSource,
    required this.initialPosition,
  });

  @override
  State<_TripDetailSheet> createState() => _TripDetailSheetState();
}

class _TripDetailSheetState extends State<_TripDetailSheet> {
  BusSimulationPosition? _position;
  String? _error;
  bool _isLoading = false;

  DateTime? _updatedAt;
  bool _realtimeEnabled = false;
  String _realtimeMode = 'idle';

  Timer? _pollingTimer;
  SseClient? _sseClient;
  StreamSubscription<String>? _sseSubscription;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _updatedAt = widget.initialPosition != null ? DateTime.now() : null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSnapshot();
      _startRealtime();
    });
  }

  @override
  void dispose() {
    _stopRealtime(updateState: false);
    super.dispose();
  }

  Future<void> _loadSnapshot({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final value = await widget.dataSource.getTripPosition(
        tripId: widget.tripId,
        accessToken: widget.token,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _position = value;
        _updatedAt = DateTime.now();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _startRealtime() async {
    if (_realtimeEnabled) {
      return;
    }

    if (kIsWeb && widget.token != null && widget.token!.trim().isNotEmpty) {
      final uri = widget.dataSource.tripPositionStreamUri(
        tripId: widget.tripId,
        token: widget.token!.trim(),
      );

      final sseClient = createSseClient();
      _sseClient = sseClient;

      setState(() {
        _realtimeEnabled = true;
        _realtimeMode = 'sse';
      });

      _sseSubscription = sseClient.connect(uri).listen(
        (payload) {
          try {
            final next = widget.dataSource.parseTripPositionEvent(payload);
            if (!mounted) {
              return;
            }
            setState(() {
              _position = next;
              _updatedAt = DateTime.now();
              _error = null;
            });
          } catch (_) {
            // Ignore malformed packet.
          }
        },
        onError: (_) {
          if (!mounted) {
            return;
          }
          _startPollingFallback();
        },
      );

      return;
    }

    _startPollingFallback();
  }

  void _startPollingFallback() {
    _stopRealtime();

    setState(() {
      _realtimeEnabled = true;
      _realtimeMode = 'polling';
    });

    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted) {
          return;
        }
        _loadSnapshot(silent: true);
      },
    );

    _loadSnapshot(silent: true);
  }

  void _stopRealtime({bool updateState = true}) {
    _pollingTimer?.cancel();
    _pollingTimer = null;

    _sseSubscription?.cancel();
    _sseSubscription = null;

    _sseClient?.close();
    _sseClient = null;

    if (updateState && mounted) {
      setState(() {
        _realtimeEnabled = false;
        _realtimeMode = 'idle';
      });
    } else {
      _realtimeEnabled = false;
      _realtimeMode = 'idle';
    }
  }

  Color _statusColor(BusSimulationStatus status) {
    switch (status) {
      case BusSimulationStatus.running:
        return AppColors.busRunning;
      case BusSimulationStatus.scheduled:
        return AppColors.busScheduled;
      case BusSimulationStatus.completed:
        return AppColors.busCompleted;
      case BusSimulationStatus.unknown:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _statusLabel(BusSimulationStatus status) {
    switch (status) {
      case BusSimulationStatus.running:
        return 'ĐANG CHẠY';
      case BusSimulationStatus.scheduled:
        return 'LÊN LỊCH';
      case BusSimulationStatus.completed:
        return 'HOÀN THÀNH';
      case BusSimulationStatus.unknown:
        return 'KHÔNG RÕ';
    }
  }

  String _fmtDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');

    return '$dd/$mm ${local.year} $hh:$min:$ss';
  }

  String _fmtClock(DateTime? value) {
    if (value == null) {
      return '--:--:--';
    }

    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$min:$ss';
  }

  String _resolveStationName(
      BusSimulationPosition position, String? stationId) {
    if (stationId == null || stationId.trim().isEmpty) {
      return '-';
    }

    for (final eta in position.stationEtas) {
      if (eta.stationId == stationId) {
        return eta.stationName;
      }
    }

    return 'Đang cập nhật tên trạm';
  }

  @override
  Widget build(BuildContext context) {
    final value = _position;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusXl),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.md,
          AppSizes.md,
          AppSizes.md,
          AppSizes.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chi tiết chuyến',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: AppSizes.xs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.8),
                  ),
                  child: Text(
                    _realtimeEnabled
                        ? (_realtimeMode == 'sse'
                            ? 'Đang theo dõi trực tiếp'
                            : 'Đang tự động làm mới')
                        : 'Đã tạm dừng cập nhật',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xs),
            const SizedBox(height: AppSizes.sm),
            if (_isLoading && value == null)
              const Padding(
                padding: EdgeInsets.all(AppSizes.lg),
                child: CircularProgressIndicator(),
              )
            else if (_error != null && value == null)
              _StateCard.error(
                title: 'Không tải được chi tiết chuyến',
                message: _error!,
              )
            else if (value == null)
              _StateCard.empty(
                title: 'Chưa có dữ liệu chuyến',
                message: 'Vui lòng thử lại sau.',
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${value.routeCode} • ${value.routeName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          _StatusChip(
                            label: _statusLabel(value.status),
                            color: _statusColor(value.status),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.sm),
                      _InfoLine(
                        label: 'Trạm hiện tại',
                        value:
                            _resolveStationName(value, value.currentStationId),
                      ),
                      _InfoLine(
                        label: 'Trạm kế tiếp',
                        value: _resolveStationName(value, value.nextStationId),
                      ),
                      _InfoLine(
                        label: 'Tiến độ đến trạm kế tiếp',
                        value:
                            '${(value.progressToNextStation * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      ),
                      const SizedBox(height: AppSizes.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: value.progressToNextStation
                              .clamp(0, 1)
                              .toDouble(),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      _InfoLine(
                        label: 'Đã chạy',
                        value:
                            '${value.elapsedMinutes.toStringAsFixed(1)} phút',
                      ),
                      _InfoLine(
                        label: 'Còn lại',
                        value:
                            '${value.remainingMinutes.toStringAsFixed(1)} phút',
                      ),
                      _InfoLine(
                        label: 'Cập nhật',
                        value: _fmtClock(_updatedAt),
                      ),
                      _InfoLine(
                        label: 'Khởi hành',
                        value: _fmtDateTime(value.departureTime),
                      ),
                      _InfoLine(
                        label: 'Đến dự kiến',
                        value: _fmtDateTime(value.expectedArrivalTime),
                      ),
                      const SizedBox(height: AppSizes.md),
                      const Text(
                        'ETA đến từng trạm',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSizes.xs),
                      if (value.stationEtas.isEmpty)
                        const Text('Không có ETA chi tiết cho chuyến này.')
                      else
                        ...value.stationEtas.map(
                          (eta) => Container(
                            margin: const EdgeInsets.only(bottom: AppSizes.xs),
                            padding: const EdgeInsets.all(AppSizes.sm),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppSizes.radiusMd),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        eta.stationName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'ETA: ${_fmtDateTime(eta.eta)}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${eta.minutesAway.toStringAsFixed(1)}m',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final Widget child;

  const _StateCard._({required this.child});

  _StateCard.loading({required String label})
      : this._(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppSizes.sm),
                Text(label),
              ],
            ),
          ),
        );

  _StateCard.empty({
    required String title,
    required String message,
  }) : this._(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              children: [
                const Icon(Icons.inbox_outlined, size: 36),
                const SizedBox(height: AppSizes.sm),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

  _StateCard.error({
    required String title,
    required String message,
  }) : this._(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded, size: 36),
                const SizedBox(height: AppSizes.sm),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Center(child: child),
    );
  }
}

class _MapStationMarkerData {
  final String key;
  final String name;
  final LatLng point;

  const _MapStationMarkerData({
    required this.key,
    required this.name,
    required this.point,
  });
}
