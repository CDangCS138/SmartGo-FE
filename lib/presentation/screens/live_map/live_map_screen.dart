import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/platform/geolocation.dart';
import '../../../core/routes/app_routes.dart';
import '../../../domain/entities/station.dart';
import '../../blocs/station/station_bloc.dart';
import '../../blocs/station/station_event.dart';
import '../../blocs/station/station_state.dart';
import '../../widgets/loading_indicator.dart';
import '../station/station_detail_screen.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  ColorScheme? _cachedScheme;

  LatLng _currentPosition = const LatLng(10.8231, 106.6297);
  LatLng? _userLocation;

  List<Marker> _markers = [];
  List<Station> _backendStations = [];
  Station? _selectedStation; // Track selected station for highlighting

  bool _isLoading = false;
  double _currentZoom = 13.0;
  double _lastZoomForMarkerUpdate =
      13.0; // Track zoom to avoid unnecessary rebuilds

  List<Station> _searchResults = [];
  Timer? _debounceTimer;
  Timer? _zoomDebounceTimer; // Debounce for zoom-based marker updates

  static const double _minZoomForStations = 13.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Accessing inherited widgets (Theme/MediaQuery/etc.) should happen here
    // (or in build), not during initState-triggered work.
    _cachedScheme = Theme.of(context).colorScheme;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    _getUserLocation();
    _loadStationsFromBackend();

    _mapController.mapEventStream.listen((event) {
      if (!mounted) return;
      if (event is MapEventMove) {
        _currentZoom = event.camera.zoom;
        // Debounce marker updates to avoid excessive rebuilds during pan/zoom
        _zoomDebounceTimer?.cancel();
        _zoomDebounceTimer = Timer(const Duration(milliseconds: 150), () {
          if (mounted) _updateMarkersBasedOnZoom();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _zoomDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    final position = await getCurrentGeoPosition(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 10),
    );
    if (!mounted || position == null) return;

    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _userLocation = point;
      _currentPosition = point;
    });
    _mapController.move(point, 14);
  }

  void _loadStationsFromBackend() {
    if (!mounted) return;
    // Check if stations are already preloaded from StationBloc
    final currentState = context.read<StationBloc>().state;
    if (currentState is StationLoaded && currentState.stations.isNotEmpty) {
      setState(() {
        _backendStations = currentState.stations;
        _isLoading = false;
      });
      // Defer marker creation until after the first build so Theme is available.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateMarkersBasedOnZoom();
      });
      return;
    }
    // Otherwise fetch from API
    setState(() => _isLoading = true);
    context.read<StationBloc>().add(
          const FetchAllStationsEvent(
            page: 1,
            limit: 5000,
            refresh: true,
          ),
        );
  }

  void _updateMarkersBasedOnZoom() {
    // Only update markers when zoom crosses the threshold to minimize rebuilds
    final nowAboveThreshold = _currentZoom >= _minZoomForStations;
    final wasAboveThreshold = _lastZoomForMarkerUpdate >= _minZoomForStations;

    if (nowAboveThreshold != wasAboveThreshold ||
        (nowAboveThreshold && _markers.isEmpty)) {
      _lastZoomForMarkerUpdate = _currentZoom;
      if (nowAboveThreshold) {
        _updateBackendMarkers();
      } else {
        setState(() => _markers = []);
      }
    }
  }

  void _updateBackendMarkers() {
    if (!mounted || _backendStations.isEmpty) return;
    final scheme = _cachedScheme;
    if (scheme == null) return;

    setState(() {
      _markers = _backendStations.map((station) {
        final isSelected = _selectedStation?.stationCode == station.stationCode;
        return Marker(
          width: isSelected ? 40.0 : 28.0,
          height: isSelected ? 40.0 : 28.0,
          point: LatLng(
            station.latitude,
            station.longitude,
          ),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => _showStationDetail(station),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? Colors.orange : scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: isSelected ? 6 : 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: isSelected ? 20 : 14,
              ),
            ),
          ),
        );
      }).toList();
    });
  }

  void _showStationDetail(Station station) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StationDetailScreen(station: station),
    );
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();

    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchBackendStations(query);
    });
  }

  void _searchBackendStations(String query) {
    final results = _backendStations
        .where((station) =>
            station.stationName.toLowerCase().contains(query.toLowerCase()) ||
            station.stationCode.toLowerCase().contains(query.toLowerCase()))
        .take(10)
        .toList();

    setState(() {
      _searchResults = results;
    });
  }

  void _selectStation(Station station) {
    final position = LatLng(
      station.latitude,
      station.longitude,
    );

    setState(() {
      _searchController.clear();
      _searchResults = [];
      _selectedStation = station; // Highlight the selected station
    });

    _updateBackendMarkers(); // Rebuild markers with selected highlight
    // Zoom to level 18 - beyond disableClusteringAtZoom (17) to show individual marker
    _mapController.move(position, 18);
    _showStationDetail(station);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocListener<StationBloc, StationState>(
      listener: (context, state) {
        if (!mounted) return;
        if (state is StationLoading) {
          setState(() => _isLoading = true);
          return;
        }
        if (state is StationLoaded) {
          setState(() {
            _backendStations = state.stations;
            _isLoading = false;
          });
          _updateMarkersBasedOnZoom();
          return;
        }
        if (state is StationError) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${state.message}')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bản đồ trực tuyến'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppRoutes.home),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go(AppRoutes.settings),
            ),
          ],
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition,
                initialZoom: _currentZoom,
                // Removed onPositionChanged - mapEventStream handles zoom tracking
                // This eliminates duplicate setState calls during pan/zoom
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.smartgo.app',
                ),
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius:
                        20, // Smaller radius to avoid clustering distinct but close stations
                    size: const Size(40, 40),
                    alignment: Alignment.center,
                    disableClusteringAtZoom:
                        17, // Show all individual markers at higher zoom
                    zoomToBoundsOnClick:
                        true, // Zoom to show all markers in cluster when tapped
                    spiderfyCluster:
                        true, // Enable spiderfy to show all stations in tight clusters
                    markers: _markers,
                    onClusterTap: (clusterNode) {
                      // Zoom in to expand the cluster
                      final center = clusterNode.bounds.center;
                      final currentZoom = _mapController.camera.zoom;
                      _mapController.move(
                        LatLng(center.latitude, center.longitude),
                        currentZoom + 2, // Zoom in by 2 levels
                      );
                    },
                    builder: (context, markers) {
                      return Container(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            markers.length.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_userLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _userLocation!,
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.onPrimary,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                color: scheme.surface,
                elevation: 1,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Tìm trạm...',
                        prefixIcon: Icon(Icons.search, color: scheme.primary),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchResults = []);
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    if (_searchResults.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                          border: Border(
                            top: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final station = _searchResults[index];
                            return ListTile(
                              leading: Icon(
                                Icons.location_on,
                                color: scheme.primary,
                              ),
                              title: Text(station.stationName),
                              subtitle: Text(station.stationCode),
                              onTap: () => _selectStation(station),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: scheme.scrim.withValues(alpha: 0.25),
                child: const Center(child: LoadingIndicator()),
              ),
            Positioned(
              right: 16,
              bottom: 100,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'zoom_in',
                    backgroundColor: scheme.surface,
                    onPressed: () {
                      _mapController.move(
                        _mapController.camera.center,
                        _currentZoom + 1,
                      );
                    },
                    child: Icon(Icons.add, color: scheme.primary),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom_out',
                    backgroundColor: scheme.surface,
                    onPressed: () {
                      _mapController.move(
                        _mapController.camera.center,
                        _currentZoom - 1,
                      );
                    },
                    child: Icon(Icons.remove, color: scheme.primary),
                  ),
                  const SizedBox(height: 8),
                  if (_userLocation != null)
                    FloatingActionButton.small(
                      heroTag: 'my_location',
                      backgroundColor: scheme.surface,
                      onPressed: () {
                        _mapController.move(_userLocation!, 14);
                      },
                      child: Icon(Icons.my_location, color: scheme.primary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
