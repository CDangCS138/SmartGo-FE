import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/services/text_to_speech_service.dart';
import 'package:smartgo/core/services/route_geometry_service.dart';
import 'package:smartgo/presentation/blocs/route/route_bloc.dart';
import 'package:smartgo/presentation/blocs/route/route_event.dart';
import 'package:smartgo/presentation/blocs/route/route_state.dart';
import 'package:smartgo/presentation/blocs/station/station_bloc.dart';
import 'package:smartgo/presentation/blocs/station/station_event.dart';
import 'package:smartgo/presentation/blocs/station/station_state.dart';
import 'package:smartgo/domain/entities/station.dart';
import 'package:smartgo/domain/entities/path_finding.dart';
import 'package:smartgo/presentation/widgets/loading_indicator.dart';
import 'package:smartgo/presentation/widgets/tts_icon_button.dart';
import 'package:smartgo/presentation/widgets/voice_input_icon_button.dart';

/// Enum for input mode
enum InputMode {
  map,
  address,
  busStop,
}

/// Nominatim result for address search
class NominatimResult {
  final String displayName;
  final double lat;
  final double lon;

  NominatimResult({
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}

class PathFindingDemoScreen extends StatefulWidget {
  const PathFindingDemoScreen({super.key});

  @override
  State<PathFindingDemoScreen> createState() => _PathFindingDemoScreenState();
}

class _PathFindingDemoScreenState extends State<PathFindingDemoScreen> {
  final MapController _mapController = MapController();

  // Map state
  LatLng? _fromPoint;
  LatLng? _toPoint;
  Station? _fromStation;
  Station? _toStation;

  // UI state
  InputMode _inputMode = InputMode.busStop;
  RoutingCriteria _selectedCriteria = RoutingCriteria.BALANCED;
  bool _showResults = false;
  bool _showFullRouteDetail = false;
  int? _selectedPathIndex;
  int _maxTransfers = 3;
  List<Station> _stations = [];
  List<PathResult>? _paths;
  bool _isLoading = false;
  bool _isSpeakingRouteGuide = false;

  // Route geometry service and cache
  final RouteGeometryService _routeGeometryService =
      getIt<RouteGeometryService>();
  List<LatLng>? _routeGeometry;
  bool _isLoadingGeometry = false;

  // Address search
  final TextEditingController _fromAddressController = TextEditingController();
  final TextEditingController _toAddressController = TextEditingController();
  List<NominatimResult> _fromAddressResults = [];
  List<NominatimResult> _toAddressResults = [];
  bool _isSearchingAddress = false;
  Timer? _fromAddressDebounce;
  Timer? _toAddressDebounce;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  @override
  void dispose() {
    TextToSpeechService.instance.stop();
    _fromAddressController.dispose();
    _toAddressController.dispose();
    _fromAddressDebounce?.cancel();
    _toAddressDebounce?.cancel();
    super.dispose();
  }

  void _loadStations() {
    // Check if stations are already preloaded from StationBloc
    final currentState = context.read<StationBloc>().state;
    if (currentState is StationLoaded && currentState.stations.isNotEmpty) {
      // Use preloaded data directly
      setState(() {
        _stations = currentState.stations;
      });
      return;
    }
    // Otherwise fetch from API
    context.read<StationBloc>().add(const FetchAllStationsEvent(limit: 5000));
  }

  void _showInfo(String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: scheme.inverseSurface,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: scheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatCostForSpeech(double value) {
    final rounded = value.round();
    final grouped = rounded.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
    return '$grouped đồng';
  }

  String _buildAccessibilityRouteGuidance(PathResult path) {
    final startName = path.stations.isNotEmpty
        ? path.stations.first.stationName
        : (_fromStation?.stationName ?? 'điểm xuất phát');
    final endName = path.stations.isNotEmpty
        ? path.stations.last.stationName
        : (_toStation?.stationName ?? 'điểm đến');

    final buffer = StringBuffer();
    buffer.writeln('SmartGo xin gửi hướng dẫn di chuyển chi tiết.');
    buffer.writeln('Bạn đi từ $startName đến $endName.');
    buffer.writeln(
      'Tổng thời gian dự kiến ${path.formattedTime}, quãng đường ${path.formattedDistance}, chi phí ${path.formattedCost}.',
    );

    if (path.numberOfTransfers <= 0) {
      buffer.writeln('Lộ trình này không cần chuyển tuyến.');
    } else {
      buffer.writeln(
          'Lộ trình này có ${path.numberOfTransfers} lần chuyển tuyến.');
    }

    if (path.segments.isEmpty) {
      buffer.writeln('Hiện chưa có dữ liệu từng bước chi tiết.');
    } else {
      buffer.writeln('Các bước di chuyển như sau.');
      for (var i = 0; i < path.segments.length; i++) {
        final segment = path.segments[i];
        final duration = segment.time > 0
            ? '${segment.time.toStringAsFixed(0)} phút'
            : 'chưa có thời gian ước tính';
        final distance = '${segment.distance.toStringAsFixed(1)} ki lô mét';
        final cost = segment.cost > 0
            ? 'chi phí khoảng ${_formatCostForSpeech(segment.cost)}'
            : 'không phát sinh thêm chi phí';

        buffer.writeln(
          'Bước ${i + 1}. Đi tuyến ${segment.routeCode}, ${segment.routeName}. Từ ${segment.from} đến ${segment.to}. Quãng đường $distance, thời gian $duration, $cost.',
        );

        if (i < path.segments.length - 1) {
          buffer.writeln(
            'Khi xuống trạm, bạn dừng lại vài giây để định hướng rồi mới di chuyển sang tuyến tiếp theo.',
          );
        }
      }
    }

    buffer.writeln(
      'Lưu ý an toàn. Hãy đi chậm, bám tay vịn khi lên xuống xe. Ưu tiên lối đi bằng phẳng và khu vực có ánh sáng tốt. Nếu cần, hãy nhờ phụ xe hoặc người xung quanh hỗ trợ.',
    );
    buffer.writeln('Chúc bạn di chuyển an toàn.');

    return buffer.toString();
  }

  Future<void> _speakRouteGuidance(PathResult path) async {
    if (_isSpeakingRouteGuide) {
      return;
    }

    final content = _buildAccessibilityRouteGuidance(path);
    setState(() => _isSpeakingRouteGuide = true);

    final success = await TextToSpeechService.instance.speak(content);
    if (!mounted) {
      return;
    }

    setState(() => _isSpeakingRouteGuide = false);

    if (!success) {
      _showError('Không thể đọc hướng dẫn lộ trình lúc này.');
    }
  }

  Future<void> _stopRouteGuidance() async {
    await TextToSpeechService.instance.stop();
    if (!mounted) {
      return;
    }
    setState(() => _isSpeakingRouteGuide = false);
  }

  void _onMapTap(LatLng point) {
    if (_inputMode != InputMode.map) return;

    setState(() {
      if (_fromPoint == null) {
        _fromPoint = point;
        _showInfo('Đã chọn điểm xuất phát');
      } else if (_toPoint == null) {
        _toPoint = point;
        _showInfo('Đã chọn điểm đích');
      } else {
        _fromPoint = point;
        _toPoint = null;
        _showInfo('Đã chọn lại điểm xuất phát');
      }
    });
  }

  void _onMapLongPress(LatLng point) async {
    if (_inputMode != InputMode.busStop) return;

    // Find nearest station
    if (_stations.isEmpty) return;

    Station? nearestStation;
    double minDistance = double.infinity;

    for (final station in _stations) {
      final stationPoint = LatLng(
        station.latitude,
        station.longitude,
      );
      final distance = _calculateDistance(point, stationPoint);

      if (distance < minDistance && distance < 0.5) {
        // Within 500m
        minDistance = distance;
        nearestStation = station;
      }
    }

    if (nearestStation != null) {
      setState(() {
        if (_fromStation == null) {
          _fromStation = nearestStation;
          _fromPoint = LatLng(
            nearestStation!.latitude,
            nearestStation.longitude,
          );
          _showInfo('Đã chọn trạm xuất phát: ${nearestStation.stationName}');
        } else if (_toStation == null) {
          _toStation = nearestStation;
          _toPoint = LatLng(
            nearestStation!.latitude,
            nearestStation.longitude,
          );
          _showInfo('Đã chọn trạm đích: ${nearestStation.stationName}');
        } else {
          _fromStation = nearestStation;
          _toStation = null;
          _fromPoint = LatLng(
            nearestStation!.latitude,
            nearestStation.longitude,
          );
          _toPoint = null;
          _showInfo(
              'Đã chọn lại trạm xuất phát: ${nearestStation.stationName}');
        }
      });
    } else {
      _showError('Không tìm thấy trạm xe buýt gần vị trí này');
    }
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(point2.latitude - point1.latitude);
    final dLon = _toRadians(point2.longitude - point1.longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(point1.latitude)) *
            math.cos(_toRadians(point2.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  List<LatLng> _buildPathPolyline(PathResult path) {
    final List<LatLng> points = [];
    for (final station in path.stations) {
      points.add(LatLng(station.latitude, station.longitude));
    }
    return points;
  }

  /// Load actual route geometry from OSRM for a given path
  Future<void> _loadRouteGeometry(PathResult path) async {
    if (path.stations.length < 2) return;

    setState(() {
      _isLoadingGeometry = true;
    });

    try {
      final waypoints =
          path.stations.map((s) => LatLng(s.latitude, s.longitude)).toList();

      final geometry =
          await _routeGeometryService.getRouteGeometryBatched(waypoints);

      if (mounted) {
        setState(() {
          _routeGeometry = geometry;
          _isLoadingGeometry = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingGeometry = false;
        });
      }
    }
  }

  void _findPath() {
    if (_isSpeakingRouteGuide) {
      TextToSpeechService.instance.stop();
    }

    if (_inputMode == InputMode.busStop) {
      if (_fromStation == null || _toStation == null) {
        _showError('Vui lòng chọn trạm xuất phát và trạm đích trên bản đồ');
        return;
      }
    } else {
      if (_fromPoint == null || _toPoint == null) {
        _showError('Vui lòng chọn điểm xuất phát và điểm đích');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _showResults = false;
      _showFullRouteDetail = false;
      _paths = null;
      _selectedPathIndex = null;
      _isSpeakingRouteGuide = false;
      _routeGeometry = null; // Reset geometry when starting new search
    });

    if (_inputMode == InputMode.busStop) {
      context.read<RouteBloc>().add(
            FindPathEvent(
              fromStationCode: _fromStation!.stationCode,
              toStationCode: _toStation!.stationCode,
              criteria: _selectedCriteria.value,
              maxTransfers: _maxTransfers,
            ),
          );
    } else {
      context.read<RouteBloc>().add(
            FindPathEvent(
              fromLatitude: _fromPoint!.latitude,
              fromLongitude: _fromPoint!.longitude,
              toLatitude: _toPoint!.latitude,
              toLongitude: _toPoint!.longitude,
              criteria: _selectedCriteria.value,
              maxTransfers: _maxTransfers,
            ),
          );
    }
  }

  void _reset() {
    if (_isSpeakingRouteGuide) {
      TextToSpeechService.instance.stop();
    }

    setState(() {
      _fromPoint = null;
      _toPoint = null;
      _fromStation = null;
      _toStation = null;
      _paths = null;
      _selectedPathIndex = null;
      _showResults = false;
      _showFullRouteDetail = false;
      _isSpeakingRouteGuide = false;
      _fromAddressController.clear();
      _toAddressController.clear();
      _fromAddressResults.clear();
      _toAddressResults.clear();
    });
  }

  void _selectAddress(NominatimResult result, bool isFrom) {
    setState(() {
      final selectedPoint = LatLng(result.lat, result.lon);
      if (isFrom) {
        _fromPoint = selectedPoint;
        _fromAddressController.text = result.displayName;
        _fromAddressResults.clear();
        _showInfo('Đã chọn điểm xuất phát');
      } else {
        _toPoint = selectedPoint;
        _toAddressController.text = result.displayName;
        _toAddressResults.clear();
        _showInfo('Đã chọn điểm đến');
      }
      // Di chuyển map đến vị trí được chọn
      _mapController.move(selectedPoint, 15);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && !Navigator.of(context).canPop()) {
          context.go('/');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tìm đường'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reset,
              tooltip: 'Đặt lại',
            ),
          ],
        ),
        body: MultiBlocListener(
          listeners: [
            BlocListener<StationBloc, StationState>(
              listener: (context, state) {
                if (state is StationLoaded) {
                  setState(() {
                    _stations = state.stations;
                  });
                } else if (state is StationError) {
                  _showError(state.message);
                }
              },
            ),
            BlocListener<RouteBloc, RouteState>(
              listener: (context, state) {
                if (state is PathFindingLoading) {
                  setState(() {
                    _isLoading = true;
                  });
                } else if (state is PathsFound) {
                  if (_isSpeakingRouteGuide) {
                    TextToSpeechService.instance.stop();
                  }
                  final pathsCount = state.paths.length;
                  setState(() {
                    _isLoading = false;
                    _paths = state.paths;
                    _selectedPathIndex = pathsCount > 0 ? 0 : null;
                    _isSpeakingRouteGuide = false;
                    // Chỉ hiển thị panel kết quả khi có ít nhất 1 lộ trình
                    _showResults = pathsCount > 0;
                    _routeGeometry = null; // Reset route geometry
                  });
                  _showInfo('Tìm thấy $pathsCount lộ trình');
                  // Load actual route geometry for selected path
                  if (pathsCount > 0) {
                    _loadRouteGeometry(state.paths[0]);
                  }
                } else if (state is PathFindingError) {
                  if (_isSpeakingRouteGuide) {
                    TextToSpeechService.instance.stop();
                  }
                  setState(() {
                    _isLoading = false;
                    _showResults = false;
                    _paths = null;
                    _isSpeakingRouteGuide = false;
                  });
                  _showError('Lỗi tìm đường: ${state.message}');
                }
              },
            ),
          ],
          child: Stack(
            children: [
              _buildMap(),
              if (!_showFullRouteDetail) _buildTopPanel(),
              if (_inputMode == InputMode.address && !_showFullRouteDetail)
                _buildAddressInputPanel(),
              if (_showResults && _paths != null && !_showFullRouteDetail)
                _buildResultsPanel(_paths!),
              if (_showFullRouteDetail &&
                  _paths != null &&
                  _selectedPathIndex != null)
                _buildFullRouteDetailView(_paths![_selectedPathIndex!]),
              if (_isLoading) _buildLoadingOverlay(),
            ],
          ),
        ),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  Widget _buildMap() {
    final scheme = Theme.of(context).colorScheme;
    final stationMarkers = _buildStationMarkers();
    final overlayMarkers = _buildOverlayMarkers();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(10.8231, 106.6297), // Ho Chi Minh City
        initialZoom: 13,
        onTap: (_, point) => _onMapTap(point),
        onLongPress: (_, point) => _onMapLongPress(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.smartgo.app',
        ),
        if (_selectedPathIndex != null && _paths != null)
          PolylineLayer(
            polylines: [
              // Border polyline (white outline)
              Polyline(
                points: _routeGeometry ??
                    _buildPathPolyline(_paths![_selectedPathIndex!]),
                strokeWidth: 6.0,
                color: Colors.white,
              ),
              // Main route polyline
              Polyline(
                points: _routeGeometry ??
                    _buildPathPolyline(_paths![_selectedPathIndex!]),
                strokeWidth: 4.0,
                color: Colors.blue,
              ),
            ],
          ),
        // Show loading indicator for route geometry
        if (_isLoadingGeometry)
          Positioned(
            bottom: _showResults ? 260 : 100,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Đang tải đường đi...',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        // Station markers with clustering for performance
        if (_inputMode == InputMode.busStop && stationMarkers.isNotEmpty)
          MarkerClusterLayerWidget(
            options: MarkerClusterLayerOptions(
              maxClusterRadius: 60,
              size: const Size(40, 40),
              alignment: Alignment.center,
              disableClusteringAtZoom: 17, // Show all markers at high zoom
              markers: stationMarkers,
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
        // Overlay markers (from/to points) always on top
        if (overlayMarkers.isNotEmpty)
          MarkerLayer(
            markers: overlayMarkers,
          ),
      ],
    );
  }

  // Build station markers for clustering
  List<Marker> _buildStationMarkers() {
    if (_inputMode != InputMode.busStop) return [];

    final markers = <Marker>[];
    for (final station in _stations) {
      final isFrom = _fromStation?.stationCode == station.stationCode;
      final isTo = _toStation?.stationCode == station.stationCode;

      // Skip selected stations - they will be shown in overlay
      if (isFrom || isTo) continue;

      markers.add(
        Marker(
          point: LatLng(
            station.latitude,
            station.longitude,
          ),
          width: 28,
          height: 28,
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (_fromStation == null) {
                  _fromStation = station;
                  _fromPoint = LatLng(
                    station.latitude,
                    station.longitude,
                  );
                  _showInfo('Đã chọn trạm xuất phát: ${station.stationName}');
                } else if (_toStation == null) {
                  _toStation = station;
                  _toPoint = LatLng(
                    station.latitude,
                    station.longitude,
                  );
                  _showInfo('Đã chọn trạm đích: ${station.stationName}');
                } else {
                  _fromStation = station;
                  _toStation = null;
                  _fromPoint = LatLng(
                    station.latitude,
                    station.longitude,
                  );
                  _toPoint = null;
                  _showInfo(
                      'Đã chọn lại trạm xuất phát: ${station.stationName}');
                }
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  // Build overlay markers (from/to points and selected stations)
  List<Marker> _buildOverlayMarkers() {
    final markers = <Marker>[];

    // From marker
    if (_fromPoint != null) {
      markers.add(
        Marker(
          point: _fromPoint!,
          width: 50,
          height: 50,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                bottom: 0,
                child: Icon(Icons.location_on, color: Colors.green, size: 40),
              ),
              Positioned(
                top: -18,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Điểm A',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // To marker
    if (_toPoint != null) {
      markers.add(
        Marker(
          point: _toPoint!,
          width: 50,
          height: 50,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                bottom: 0,
                child: Icon(Icons.location_on, color: Colors.red, size: 40),
              ),
              Positioned(
                top: -18,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Điểm B',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Selected station markers (from/to in busStop mode)
    if (_inputMode == InputMode.busStop) {
      if (_fromStation != null) {
        markers.add(
          Marker(
            point: LatLng(
              _fromStation!.latitude,
              _fromStation!.longitude,
            ),
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        );
      }

      if (_toStation != null) {
        markers.add(
          Marker(
            point: LatLng(
              _toStation!.latitude,
              _toStation!.longitude,
            ),
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  Widget _buildTopPanel() {
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeSelector(),
              const Divider(height: 1),
              _buildCriteriaSelector(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildModeButton(InputMode.map, Icons.map, 'Bản đồ'),
          const SizedBox(width: 8),
          _buildModeButton(InputMode.busStop, Icons.directions_bus, 'Trạm'),
          const SizedBox(width: 8),
          _buildModeButton(InputMode.address, Icons.search, 'Địa chỉ'),
        ],
      ),
    );
  }

  Widget _buildModeButton(InputMode mode, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _inputMode == mode;
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _inputMode = mode;
          });
        },
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected ? scheme.primary : scheme.surfaceContainerHighest,
          foregroundColor: isSelected ? scheme.onPrimary : scheme.onSurface,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCriteriaSelector() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          DropdownButtonFormField<RoutingCriteria>(
            initialValue: _selectedCriteria,
            decoration: const InputDecoration(
              labelText: 'Tiêu chí tối ưu',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: RoutingCriteria.values.map((criteria) {
              return DropdownMenuItem(
                value: criteria,
                child: Text(criteria.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedCriteria = value;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _maxTransfers.toString(),
            decoration: const InputDecoration(
              labelText: 'Số lần chuyển tuyến tối đa',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              suffixIcon: Icon(Icons.transfer_within_a_station),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= 0 && parsed <= 10) {
                setState(() {
                  _maxTransfers = parsed;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(List<PathResult> paths) {
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tìm thấy ${paths.length} lộ trình',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _showResults = false;
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  return _buildPathCard(paths[index], index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathCard(PathResult path, int index) {
    final isSelected = _selectedPathIndex == index;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.blue[50] : null,
      child: InkWell(
        onTap: () {
          if (_isSpeakingRouteGuide) {
            TextToSpeechService.instance.stop();
          }
          setState(() {
            _selectedPathIndex = index;
            _showFullRouteDetail = true;
            _isSpeakingRouteGuide = false;
            _routeGeometry = null; // Reset geometry for new path
          });
          // Load geometry for the newly selected path
          if (_paths != null && index < _paths!.length) {
            _loadRouteGeometry(_paths![index]);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Lộ trình ${index + 1}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: Colors.blue),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(path.formattedTime),
                  const SizedBox(width: 16),
                  Icon(Icons.route, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(path.formattedDistance),
                  const SizedBox(width: 16),
                  Icon(Icons.monetization_on,
                      size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(path.formattedCost),
                ],
              ),
              if (path.transfers != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Chuyển ${path.transfers} lần',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _findPath,
      icon: const Icon(Icons.search),
      label: const Text('Tìm đường'),
    );
  }

  Widget _buildLoadingOverlay() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.scrim.withValues(alpha: 0.35),
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingIndicator(),
                SizedBox(height: 16),
                Text(
                  'Đang tìm đường...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onFromAddressInputChanged(String value) {
    setState(() {});
    _fromAddressDebounce?.cancel();
    _fromAddressDebounce = Timer(
      const Duration(milliseconds: 500),
      () {
        if (value.isNotEmpty) {
          _searchAddress(value, true);
        } else {
          setState(() {
            _fromAddressResults.clear();
          });
        }
      },
    );
  }

  void _onToAddressInputChanged(String value) {
    setState(() {});
    _toAddressDebounce?.cancel();
    _toAddressDebounce = Timer(
      const Duration(milliseconds: 500),
      () {
        if (value.isNotEmpty) {
          _searchAddress(value, false);
        } else {
          setState(() {
            _toAddressResults.clear();
          });
        }
      },
    );
  }

  Widget _buildAddressInputPanel() {
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      top: 200,
      left: 16,
      right: 16,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nhập địa chỉ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fromAddressController,
                decoration: InputDecoration(
                  labelText: 'Điểm xuất phát',
                  hintText: 'VD: 268 Lý Thường Kiệt, Quận 10, TP.HCM',
                  prefixIcon: Icon(Icons.my_location, color: scheme.primary),
                  border: const OutlineInputBorder(),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                    maxWidth: 140,
                  ),
                  suffixIcon: SizedBox(
                    width: _fromAddressController.text.isNotEmpty ? 132 : 88,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        VoiceInputIconButton(
                          controller: _fromAddressController,
                          tooltip: 'Nhập điểm xuất phát bằng giọng nói',
                          stopTooltip: 'Dừng nhập giọng nói',
                          onTextChanged: _onFromAddressInputChanged,
                        ),
                        TtsIconButton(
                          controller: _fromAddressController,
                          tooltip: 'Đọc điểm xuất phát',
                          emptyMessage: 'Bạn chưa nhập điểm xuất phát để đọc.',
                        ),
                        if (_fromAddressController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _fromAddressController.clear();
                                _fromPoint = null;
                                _fromAddressResults.clear();
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                onChanged: _onFromAddressInputChanged,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _toAddressController,
                decoration: InputDecoration(
                  labelText: 'Điểm đến',
                  hintText: 'VD: Chợ Bến Thành, Quận 1, TP.HCM',
                  prefixIcon: const Icon(Icons.location_on, color: Colors.red),
                  border: const OutlineInputBorder(),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                    maxWidth: 140,
                  ),
                  suffixIcon: SizedBox(
                    width: _toAddressController.text.isNotEmpty ? 132 : 88,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        VoiceInputIconButton(
                          controller: _toAddressController,
                          tooltip: 'Nhập điểm đến bằng giọng nói',
                          stopTooltip: 'Dừng nhập giọng nói',
                          onTextChanged: _onToAddressInputChanged,
                        ),
                        TtsIconButton(
                          controller: _toAddressController,
                          tooltip: 'Đọc điểm đến',
                          emptyMessage: 'Bạn chưa nhập điểm đến để đọc.',
                        ),
                        if (_toAddressController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _toAddressController.clear();
                                _toPoint = null;
                                _toAddressResults.clear();
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                onChanged: _onToAddressInputChanged,
              ),
              const SizedBox(height: 8),
              Text(
                'Nhập địa chỉ để tìm kiếm (gợi ý tự động)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (_isSearchingAddress)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (_fromAddressResults.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'Gợi ý điểm xuất phát:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._fromAddressResults.map((result) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on,
                              color: Colors.green, size: 20),
                          title: Text(
                            result.displayName,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectAddress(result, true),
                        )),
                  ],
                ),
              if (_toAddressResults.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'Gợi ý điểm đến:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._toAddressResults.map((result) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on,
                              color: Colors.red, size: 20),
                          title: Text(
                            result.displayName,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectAddress(result, false),
                        )),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullRouteDetailView(PathResult path) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Header với nút đóng
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      if (_isSpeakingRouteGuide) {
                        TextToSpeechService.instance.stop();
                      }
                      setState(() {
                        _showFullRouteDetail = false;
                        _isSpeakingRouteGuide = false;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chi tiết lộ trình',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              path.formattedTime,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.route,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              path.formattedDistance,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.monetization_on,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              path.formattedCost,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _isSpeakingRouteGuide
                        ? 'Đang đọc hướng dẫn'
                        : 'Đọc hướng dẫn di chuyển',
                    onPressed: _isSpeakingRouteGuide
                        ? null
                        : () => _speakRouteGuidance(path),
                    icon: _isSpeakingRouteGuide
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.record_voice_over_rounded),
                  ),
                  IconButton(
                    tooltip: 'Dừng đọc hướng dẫn',
                    onPressed:
                        _isSpeakingRouteGuide ? _stopRouteGuidance : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                ],
              ),
            ),
            // Danh sách hướng dẫn từng bước
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: path.segments.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Điểm xuất phát
                    final firstStation = path.stations.first;
                    return _buildRouteStepCard(
                      icon: Icons.my_location,
                      iconColor: Colors.green,
                      title: 'Điểm xuất phát',
                      subtitle: firstStation.stationName,
                      isFirst: true,
                    );
                  }

                  final segmentIndex = index - 1;
                  final segment = path.segments[segmentIndex];
                  final isLast = segmentIndex == path.segments.length - 1;

                  // Kiểm tra xem có chuyển tuyến không
                  final isTransfer = segmentIndex > 0 &&
                      path.segments[segmentIndex - 1].routeCode !=
                          segment.routeCode;

                  return Column(
                    children: [
                      if (isTransfer)
                        _buildTransferIndicator(
                          path.segments[segmentIndex - 1].routeCode,
                          segment.routeCode,
                        ),
                      _buildRouteStepCard(
                        icon: Icons.directions_bus,
                        iconColor: Colors.blue,
                        title:
                            'Tuyến ${segment.routeCode}: ${segment.routeName}',
                        subtitle:
                            '${segment.from} → ${segment.to}\n${(segment.distance).toStringAsFixed(1)} km • ${(segment.time).toStringAsFixed(0)} phút',
                        routeCode: segment.routeCode,
                        isLast: isLast,
                      ),
                      if (isLast)
                        _buildRouteStepCard(
                          icon: Icons.location_on,
                          iconColor: Colors.red,
                          title: 'Điểm đến',
                          subtitle: path.stations.last.stationName,
                          isLast: true,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteStepCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? routeCode,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  color: Colors.grey[300],
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferIndicator(String fromRoute, String toRoute) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 20),
      child: Row(
        children: [
          const Icon(Icons.transfer_within_a_station,
              color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Chuyển từ tuyến $fromRoute sang tuyến $toRoute',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _searchAddress(String query, bool isFrom) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearchingAddress = true;
    });

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': '$query, Ho Chi Minh City, Vietnam',
          'format': 'json',
          'limit': '5',
          'countrycodes': 'vn',
        },
      );

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'SmartGo/1.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final results = data.map((item) {
          return NominatimResult(
            displayName: item['display_name'],
            lat: double.parse(item['lat']),
            lon: double.parse(item['lon']),
          );
        }).toList();

        setState(() {
          if (isFrom) {
            _fromAddressResults = results;
          } else {
            _toAddressResults = results;
          }
          _isSearchingAddress = false;
        });

        if (results.isEmpty) {
          _showError('Không tìm thấy địa chỉ "$query"');
        }
      } else {
        setState(() {
          _isSearchingAddress = false;
        });
        _showError('Lỗi tìm kiếm địa chỉ: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isSearchingAddress = false;
      });
      _showError('Lỗi kết nối: $e');
    }
  }
}
