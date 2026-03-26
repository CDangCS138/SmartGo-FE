import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/services/route_geometry_service.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/domain/entities/station.dart';
import 'package:smartgo/domain/repositories/route_repository.dart';
import 'package:smartgo/presentation/blocs/station/station_bloc.dart';
import 'package:smartgo/presentation/blocs/station/station_event.dart';
import 'package:smartgo/presentation/blocs/station/station_state.dart';
import 'package:smartgo/presentation/screens/route/route_ticket_payment_screen.dart';
import 'package:smartgo/presentation/widgets/loading_indicator.dart';

class RouteDetailScreen extends StatefulWidget {
  final BusRoute route;

  const RouteDetailScreen({
    super.key,
    required this.route,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();
  final RouteGeometryService _routeGeometryService =
      getIt<RouteGeometryService>();
  final RouteRepository _routeRepository = getIt<RouteRepository>();

  late BusRoute _route;
  bool _isLoadingRoute = false;

  List<Station> _forwardStations = [];
  List<Station> _backwardStations = [];
  bool _isLoadingStations = false;

  // Cache for route geometries
  List<LatLng>? _forwardRouteGeometry;
  List<LatLng>? _backwardRouteGeometry;
  bool _isLoadingGeometry = false;

  @override
  void initState() {
    super.initState();
    _route = widget.route;
    _tabController = TabController(length: 3, vsync: this);
    if (_route.routeForwardCodes.isEmpty && _route.routeBackwardCodes.isEmpty) {
      _fetchFullRoute();
    } else {
      _loadStations();
    }
  }

  Future<void> _fetchFullRoute() async {
    setState(() {
      _isLoadingRoute = true;
    });
    final result = await _routeRepository.getRouteById(id: _route.id);
    result.fold(
      (failure) {
        setState(() {
          _isLoadingRoute = false;
        });
        // Fall back to loading stations with the original route data
        _loadStations();
      },
      (fullRoute) {
        setState(() {
          _route = fullRoute;
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
      setState(() {
        _forwardStations = _matchStationsWithCodes(
          _route.routeForwardCodes,
          currentState.stations,
        );
        _backwardStations = _matchStationsWithCodes(
          _route.routeBackwardCodes,
          currentState.stations,
        );
        _isLoadingStations = false;
      });
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
    setState(() {
      _isLoadingGeometry = true;
    });

    // Load forward route geometry
    if (_forwardStations.isNotEmpty) {
      final forwardWaypoints =
          _forwardStations.map((s) => LatLng(s.latitude, s.longitude)).toList();

      if (forwardWaypoints.length >= 2) {
        _forwardRouteGeometry = await _routeGeometryService
            .getRouteGeometryBatched(forwardWaypoints);
      }
    }

    // Load backward route geometry
    if (_backwardStations.isNotEmpty) {
      final backwardWaypoints = _backwardStations
          .map((s) => LatLng(s.latitude, s.longitude))
          .toList();

      if (backwardWaypoints.length >= 2) {
        _backwardRouteGeometry = await _routeGeometryService
            .getRouteGeometryBatched(backwardWaypoints);
      }
    }

    setState(() {
      _isLoadingGeometry = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocListener<StationBloc, StationState>(
      listener: (context, state) {
        if (state is StationLoaded) {
          setState(() {
            _forwardStations = _matchStationsWithCodes(
              _route.routeForwardCodes,
              state.stations,
            );
            _backwardStations = _matchStationsWithCodes(
              _route.routeBackwardCodes,
              state.stations,
            );
            _isLoadingStations = false;
          });

          // Load route geometries after stations are loaded
          _loadRouteGeometries();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Tuyến ${_route.routeCode}'),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: scheme.primary,
            labelColor: scheme.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,
            tabs: const [
              Tab(text: 'Thông tin', icon: Icon(Icons.info_outline)),
              Tab(text: 'Chiều đi', icon: Icon(Icons.arrow_forward)),
              Tab(text: 'Chiều về', icon: Icon(Icons.arrow_back)),
            ],
          ),
        ),
        body: _isLoadingRoute
            ? const LoadingIndicator()
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(),
                  _buildRouteMapTab(
                    _forwardStations,
                    'Chiều đi: ${_route.startPoint} → ${_route.endPoint}',
                    scheme.tertiary,
                    routeGeometry: _forwardRouteGeometry,
                  ),
                  _buildRouteMapTab(
                    _backwardStations,
                    'Chiều về: ${_route.endPoint} → ${_route.startPoint}',
                    scheme.primary,
                    routeGeometry: _backwardRouteGeometry,
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isLoadingRoute ? null : _onBuyTicketPressed,
              icon: const Icon(Icons.confirmation_num_outlined),
              label: const Text(
                'Mua vé tuyến này',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
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

  Widget _buildInfoTab() {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route header
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _route.routeCode,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _route.routeName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Route endpoints
          _buildSectionTitle('Điểm đầu/cuối'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.radio_button_checked,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _route.startPoint,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: scheme.onSurfaceVariant),
                Expanded(
                  child: Column(
                    children: [
                      Icon(Icons.location_on, color: scheme.error),
                      const SizedBox(height: 8),
                      Text(
                        _route.endPoint,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Station count
          _buildSectionTitle('Số lượng trạm'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStationCount(
                'Chiều đi',
                _route.routeForwardCodes.length,
                scheme.tertiary,
              ),
              _buildStationCount(
                'Chiều về',
                _route.routeBackwardCodes.length,
                scheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // General Information
          _buildSectionTitle('Thông tin chung'),
          _buildInfoRow(
            Icons.directions_bus,
            'Loại phương tiện',
            _route.vehicleType,
          ),
          _buildInfoRow(
            Icons.business,
            'Nhà vận hành',
            _route.operatorName,
          ),
          _buildInfoRow(
            Icons.phone,
            'Số điện thoại',
            _route.phoneNumber,
            Colors.blue,
          ),
          _buildInfoRow(
            Icons.schedule,
            'Giờ hoạt động',
            '${_route.operatingTime.from} - ${_route.operatingTime.to}',
          ),
          _buildInfoRow(
            Icons.timer,
            'Tần suất',
            _route.frequency,
          ),
          _buildInfoRow(
            Icons.access_time,
            'Thời gian chuyến',
            _route.tripTime,
          ),
          _buildInfoRow(
            Icons.repeat,
            'Số chuyến/ngày',
            _route.numTrips.toString(),
          ),
          _buildInfoRow(
            Icons.straighten,
            'Tổng quãng đường',
            '${_route.totalDistance.toStringAsFixed(1)} km',
          ),
          _buildInfoRow(
            Icons.attach_money,
            'Giá vé',
            _route.baseFare.join(' - '),
            Colors.green,
          ),
          _buildInfoRow(
            Icons.accessible,
            'Hỗ trợ xe lăn',
            _route.isWheelchairAccessible ? 'Có' : 'Không',
            _route.isWheelchairAccessible ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteMapTab(
    List<Station> stations,
    String title,
    Color routeColor, {
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
            Icon(Icons.warning_amber, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text('Không có thông tin trạm cho tuyến này'),
          ],
        ),
      );
    }

    // Calculate bounds
    final latitudes = stations.map((s) => s.latitude);
    final longitudes = stations.map((s) => s.longitude);

    final centerLat = (latitudes.reduce((a, b) => a + b)) / latitudes.length;
    final centerLon = (longitudes.reduce((a, b) => a + b)) / longitudes.length;

    // Use actual route geometry if available, otherwise use direct waypoints
    final polylinePoints = routeGeometry ??
        stations.map((s) => LatLng(s.latitude, s.longitude)).toList();

    // Create markers
    final markers = stations.asMap().entries.map((entry) {
      final index = entry.key;
      final station = entry.value;
      final isFirst = index == 0;
      final isLast = index == stations.length - 1;

      return Marker(
        point: LatLng(station.latitude, station.longitude),
        width: 30,
        height: 30,
        child: GestureDetector(
          onTap: () => _showStationInfo(station, index + 1),
          child: Container(
            decoration: BoxDecoration(
              color: isFirst
                  ? Colors.green
                  : isLast
                      ? Colors.red
                      : routeColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: routeColor.withValues(alpha: 0.1),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: routeColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${stations.length} trạm',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              if (_isLoadingGeometry)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Đang tải đường đi thực tế...',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(centerLat, centerLon),
              initialZoom: 13.0,
              minZoom: 10.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smartgo.app',
              ),
              PolylineLayer(
                polylines: [
                  // Border polyline (outline)
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 6.0,
                    color: Colors.white,
                  ),
                  // Main route polyline
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 4.0,
                    color: routeColor,
                    borderStrokeWidth: 2.0,
                    borderColor: routeColor.withValues(alpha: 0.3),
                  ),
                ],
              ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.3),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: stations.length,
            itemBuilder: (context, index) {
              final station = stations[index];
              final isFirst = index == 0;
              final isLast = index == stations.length - 1;

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: isFirst
                      ? Colors.green
                      : isLast
                          ? Colors.red
                          : routeColor,
                  radius: 16,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(
                  station.stationName,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  station.stationCode,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.center_focus_strong, size: 20),
                  onPressed: () {
                    _mapController.move(
                      LatLng(
                        station.latitude,
                        station.longitude,
                      ),
                      15.0,
                    );
                  },
                ),
                onTap: () => _showStationInfo(station, index + 1),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showStationInfo(Station station, int order) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary,
                  child: Text(
                    '$order',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        station.stationCode,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.location_on, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(station.fullAddress)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${station.latitude.toStringAsFixed(7)}, '
                  '${station.longitude.toStringAsFixed(7)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: scheme.primary,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      [Color? iconColor]) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor ?? scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationCount(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'trạm',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
