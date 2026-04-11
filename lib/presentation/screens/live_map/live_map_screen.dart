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
import '../../widgets/tts_icon_button.dart';
import '../../widgets/voice_input_icon_button.dart';
import '../station/station_detail_screen.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  static const int _stationPageSize = 5000;

  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  StreamSubscription<MapEvent>? _mapEventSubscription;

  LatLng _currentPosition = const LatLng(10.8231, 106.6297);
  LatLng? _userLocation;

  List<Station> _backendStations = [];
  List<Station> _nearbyStations = [];
  Station? _selectedStation;

  bool _isLoading = false;
  bool _isLoadingLocation = false;
  bool _showNearbyOnly = false;
  double _nearbyRadiusKm = 1.0;
  double _currentZoom = 13;

  List<Station> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    _ensureUserLocation();
    _loadStationsFromBackend();

    _mapEventSubscription = _mapController.mapEventStream.listen((event) {
      if (!mounted) {
        return;
      }
      if (event is MapEventMove || event is MapEventMoveEnd) {
        _currentZoom = event.camera.zoom;
      }
    });
  }

  @override
  void dispose() {
    _mapEventSubscription?.cancel();
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _moveMapSafely(LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _zoomBy(double delta) {
    try {
      final camera = _mapController.camera;
      final nextZoom = (camera.zoom + delta).clamp(10.0, 19.0);
      _mapController.move(camera.center, nextZoom);
    } catch (_) {
      // Ignore if map is not ready yet.
    }
  }

  List<Station> get _visibleStations {
    if (_showNearbyOnly) {
      return _nearbyStations;
    }
    return _backendStations;
  }

  Future<bool> _ensureUserLocation() async {
    if (!mounted) {
      return false;
    }

    setState(() => _isLoadingLocation = true);
    try {
      var position = await getCurrentGeoPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
      );

      // On web, first request right after granting permission can return null.
      if (position == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        position = await getCurrentGeoPosition(
          enableHighAccuracy: false,
          timeout: const Duration(seconds: 10),
        );
      }

      if (!mounted || position == null) {
        if (mounted) {
          setState(() => _isLoadingLocation = false);
        }
        return false;
      }

      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _userLocation = point;
        _currentPosition = point;
        _isLoadingLocation = false;
      });
      _moveMapSafely(point, 14);
      return true;
    } catch (_) {
      if (!mounted) {
        return false;
      }
      setState(() => _isLoadingLocation = false);
      return false;
    }
  }

  Future<void> _focusOnCurrentLocation() async {
    if (_isLoadingLocation) {
      return;
    }

    if (_userLocation == null) {
      final acquired = await _ensureUserLocation();
      if (!acquired && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Chưa lấy được vị trí. Hãy chờ vài giây rồi thử lại.'),
          ),
        );
      }
    }

    if (!mounted) {
      return;
    }

    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có tọa độ hiện tại. Vui lòng thử lại.'),
        ),
      );
      return;
    }

    _moveMapSafely(_userLocation!, 15);
  }

  void _applyNearbyFilter() {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng bật vị trí hiện tại trước.')),
      );
      return;
    }

    final center = _userLocation!;
    const distance = Distance();
    final filtered = _backendStations.where((station) {
      final km = distance.as(
        LengthUnit.Kilometer,
        center,
        LatLng(station.latitude, station.longitude),
      );
      return km <= _nearbyRadiusKm;
    }).toList();

    setState(() {
      _nearbyStations = filtered;
      _showNearbyOnly = true;
      _selectedStation = null;
    });

    _moveMapSafely(center, 14);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Tìm thấy ${filtered.length} trạm trong ${_nearbyRadiusKm.toStringAsFixed(_nearbyRadiusKm < 1 ? 1 : 0)}km'),
      ),
    );
  }

  Future<void> _showNearbyDialog() async {
    await _focusOnCurrentLocation();
    if (!mounted || _userLocation == null) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trạm gần tôi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chọn bán kính hiển thị:'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [0.5, 1.0, 2.0, 3.0].map((radius) {
                final label = radius < 1
                    ? '${(radius * 1000).toInt()}m'
                    : '${radius.toInt()}km';
                return ChoiceChip(
                  label: Text(label),
                  selected: _nearbyRadiusKm == radius,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() => _nearbyRadiusKm = radius);
                    Navigator.of(context).pop();
                    _applyNearbyFilter();
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          if (_showNearbyOnly)
            TextButton(
              onPressed: () {
                setState(() {
                  _showNearbyOnly = false;
                  _nearbyStations = [];
                });
                Navigator.of(context).pop();
              },
              child: const Text('Hiện tất cả'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _loadStationsFromBackend() {
    if (!mounted) {
      return;
    }

    final currentState = context.read<StationBloc>().state;
    if (currentState is StationLoaded && currentState.stations.isNotEmpty) {
      setState(() {
        _backendStations = currentState.stations;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    context.read<StationBloc>().add(
          const FetchAllStationsEvent(
            page: 1,
            limit: _stationPageSize,
            refresh: true,
          ),
        );
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
      _selectedStation = station;
    });

    // Zoom to level 18 - beyond disableClusteringAtZoom (17) to show individual marker
    _moveMapSafely(position, 18);
    _showStationDetail(station);
  }

  List<Marker> _buildStationMarkers(ColorScheme scheme) {
    final source = _visibleStations;
    if (source.isEmpty) {
      return const [];
    }
    return source.map((station) {
      final isSelected = _selectedStation?.stationCode == station.stationCode;
      return Marker(
        width: isSelected ? 40.0 : 28.0,
        height: isSelected ? 40.0 : 28.0,
        point: LatLng(station.latitude, station.longitude),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => _showStationDetail(station),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.primary,
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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stationMarkers = _buildStationMarkers(scheme);

    return BlocListener<StationBloc, StationState>(
      listener: (context, state) {
        if (!mounted) return;
        if (state is StationLoading) {
          setState(() => _isLoading = true);
          return;
        }
        if (state is StationLoaded) {
          List<Station> refreshedNearby = _nearbyStations;
          if (_showNearbyOnly && _userLocation != null) {
            const distance = Distance();
            refreshedNearby = state.stations.where((station) {
              final km = distance.as(
                LengthUnit.Kilometer,
                _userLocation!,
                LatLng(station.latitude, station.longitude),
              );
              return km <= _nearbyRadiusKm;
            }).toList();
          }

          setState(() {
            _backendStations = state.stations;
            _nearbyStations = refreshedNearby;
            _isLoading = false;
          });
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
            if (_showNearbyOnly)
              IconButton(
                icon: const Icon(Icons.filter_alt_off),
                tooltip: 'Hiện tất cả trạm',
                onPressed: () => setState(() {
                  _showNearbyOnly = false;
                  _nearbyStations = [];
                }),
              ),
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
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.smartgo.app',
                ),
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 60,
                    size: const Size(40, 40),
                    alignment: Alignment.center,
                    disableClusteringAtZoom: 17,
                    zoomToBoundsOnClick: true,
                    spiderfyCluster: true,
                    markers: stationMarkers,
                    onClusterTap: (clusterNode) {
                      // Zoom in to expand the cluster
                      final center = clusterNode.bounds.center;
                      try {
                        final currentZoom = _mapController.camera.zoom;
                        _moveMapSafely(
                          LatLng(center.latitude, center.longitude),
                          (currentZoom + 2).clamp(10.0, 19.0),
                        );
                      } catch (_) {
                        _moveMapSafely(
                          LatLng(center.latitude, center.longitude),
                          15,
                        );
                      }
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
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                          maxWidth: 140,
                        ),
                        suffixIcon: SizedBox(
                          width: _searchController.text.isNotEmpty ? 132 : 88,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              VoiceInputIconButton(
                                controller: _searchController,
                                tooltip: 'Nhập từ khóa tìm trạm bằng giọng nói',
                                stopTooltip: 'Dừng nhập giọng nói',
                                onTextChanged: (_) => setState(() {}),
                              ),
                              TtsIconButton(
                                controller: _searchController,
                                tooltip: 'Đọc từ khóa tìm trạm',
                                emptyMessage: 'Bạn chưa nhập tên trạm để đọc.',
                              ),
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchResults = []);
                                  },
                                ),
                            ],
                          ),
                        ),
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
            if (_showNearbyOnly)
              Positioned(
                top: 92,
                left: 16,
                child: Chip(
                  avatar: const Icon(Icons.near_me, size: 18),
                  label: Text(
                    'Bán kính ${_nearbyRadiusKm < 1 ? '${(_nearbyRadiusKm * 1000).toInt()}m' : '${_nearbyRadiusKm.toInt()}km'}: ${_nearbyStations.length} trạm',
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 100,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'zoom_in',
                    backgroundColor: scheme.surface,
                    onPressed: () => _zoomBy(1),
                    child: Icon(Icons.add, color: scheme.primary),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom_out',
                    backgroundColor: scheme.surface,
                    onPressed: () => _zoomBy(-1),
                    child: Icon(Icons.remove, color: scheme.primary),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'my_location',
                    backgroundColor: scheme.surface,
                    onPressed: _focusOnCurrentLocation,
                    child: _isLoadingLocation
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        : Icon(Icons.my_location, color: scheme.primary),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'nearby_stations',
                    backgroundColor:
                        _showNearbyOnly ? scheme.primary : scheme.surface,
                    onPressed: _showNearbyDialog,
                    child: Icon(
                      Icons.near_me,
                      color:
                          _showNearbyOnly ? scheme.onPrimary : scheme.primary,
                    ),
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
