import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_env.dart';
import '../../../core/routes/app_routes.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../../core/platform/geolocation.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/route_geometry_service.dart';
import '../../widgets/tts_icon_button.dart';
import '../../widgets/voice_input_icon_button.dart';

/// Map Screen - Redesigned
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  final RouteGeometryService _routeGeometryService =
      getIt<RouteGeometryService>();

  LatLng _currentPosition = const LatLng(10.8231, 106.6297);
  LatLng? _userLocation;

  List<Marker> _markers = [];
  List<Map<String, dynamic>> _busStopsData = [];
  List<Map<String, dynamic>> _selectedRouteStops = [];
  List<LatLng> _routePoints = [];
  List<Map<String, dynamic>> _apiRoutes = [];

  bool _isLoading = false;
  bool _isLoadingLocation = false;
  double _nearbyRadius = 3.0;

  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _getUserLocation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    if (!mounted) return;
    setState(() => _isLoadingLocation = true);

    try {
      final position = await getCurrentGeoPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
      );

      final lat = position?.latitude ?? 10.8231;
      final lon = position?.longitude ?? 106.6297;

      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(lat, lon);
        _currentPosition = LatLng(lat, lon);
        _isLoadingLocation = false;
      });

      _mapController.move(_currentPosition, 15);
    } catch (e) {
      debugPrint('Error: $e');
      if (!mounted) return;
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _focusOnCurrentLocation() async {
    if (_isLoadingLocation) {
      return;
    }

    if (_userLocation == null) {
      await _getUserLocation();
    }

    if (!mounted) {
      return;
    }

    final position = _userLocation;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lấy được vị trí hiện tại.')),
      );
      return;
    }

    _mapController.move(position, 16);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();

    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchBusStops(query);
    });
  }

  // Normalize station name để match với OSM
  String _normalizeStationName(String name) {
    // Bỏ "Trạm xe buýt" và phần trong ngoặc []
    String normalized = name
        .replaceAll(RegExp(r'Trạm xe buýt\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .trim();

    // Bỏ dấu phẩy và phần sau (quận/huyện)
    if (normalized.contains(',')) {
      normalized = normalized.split(',').first.trim();
    }

    return normalized;
  }

  // Tìm trạm OSM match với station từ API
  Map<String, dynamic>? _findMatchingOsmStop(
      String stationName, String? stationCode) {
    final normalized = _normalizeStationName(stationName).toLowerCase();

    // Thử match theo tên đã normalize
    for (var stop in _busStopsData) {
      final stopName = (stop['name'] as String).toLowerCase();
      if (stopName.contains(normalized) || normalized.contains(stopName)) {
        return stop;
      }
    }

    // Thử match theo station code nếu có
    if (stationCode != null && stationCode.isNotEmpty) {
      for (var stop in _busStopsData) {
        final ref = (stop['ref'] as String).toLowerCase();
        if (ref.contains(stationCode.toLowerCase())) {
          return stop;
        }
      }
    }

    return null;
  }

  Future<List<LatLng>> _buildRouteGeometryFromStops(
    List<Map<String, dynamic>> stops,
  ) async {
    final waypoints = <LatLng>[];

    for (final stop in stops) {
      final lat = (stop['lat'] as num?)?.toDouble();
      final lon = (stop['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        continue;
      }
      waypoints.add(LatLng(lat, lon));
    }

    if (waypoints.length < 2) {
      return waypoints;
    }

    return _routeGeometryService.getRouteGeometryBatched(waypoints);
  }

  // Fetch routes từ API
  Future<void> _fetchApiRoutes() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final url = Uri.parse('${AppEnv.baseUrl}/api/v1/routes').replace(
        queryParameters: {
          'page': '1',
          'limit': '100',
          'direction': 'both',
          'routeCode': '',
        },
      );
      final response = await http.get(
        url,
        headers: {'accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        setState(() {
          _apiRoutes =
              List<Map<String, dynamic>>.from(data['data']['routes'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error fetching routes: \$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Vẽ route từ API data
  Future<void> _drawRouteFromApi(
      Map<String, dynamic> routeData, bool isForward) async {
    if (!mounted) return;

    // Load bus stops nếu chưa có
    if (_busStopsData.isEmpty) {
      setState(() => _isLoading = true);
      await _loadBusStops();
      if (mounted) setState(() => _isLoading = false);
    }

    setState(() => _isLoading = true);

    try {
      final stations = routeData['data']['stations'] as List;
      final routeCodes = isForward
          ? (routeData['data']['routes'][0]['routeForwardCodes']
              as Map<String, dynamic>)
          : (routeData['data']['routes'][0]['routeBackwardCodes']
              as Map<String, dynamic>);

      // Lấy danh sách station codes theo thứ tự
      final orderedStationCodes = routeCodes.keys.toList();

      List<Map<String, dynamic>> matchedStops = [];

      // Match từng trạm
      for (var stationCode in orderedStationCodes) {
        if (stationCode.isEmpty) continue;

        // Tìm station info từ API
        final stationInfo = stations.firstWhere(
          (s) => s['stationCode'] == stationCode,
          orElse: () => null,
        );

        if (stationInfo != null) {
          // Tìm matching OSM stop
          final osmStop = _findMatchingOsmStop(
            stationInfo['stationName'] as String,
            stationInfo['stationCode'] as String,
          );

          if (osmStop != null) {
            matchedStops.add(osmStop);
          }
        }
      }

      if (matchedStops.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Không thể match đủ trạm (${matchedStops.length} trạm)')),
          );
        }
        return;
      }

      final allRoutePoints = await _buildRouteGeometryFromStops(matchedStops);

      if (!mounted) return;

      setState(() {
        _selectedRouteStops = matchedStops;
        _routePoints = allRoutePoints;
        _markers = matchedStops.asMap().entries.map((entry) {
          final index = entry.key;
          final stop = entry.value;
          return Marker(
            point: LatLng(stop['lat'] as double, stop['lon'] as double),
            width: 50,
            height: 50,
            child: GestureDetector(
              onTap: () => _showStopDetails(stop),
              child: Stack(
                children: [
                  const Icon(Icons.directions_bus,
                      color: Colors.green, size: 40),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: Text('${index + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();
      });

      if (_routePoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(_routePoints);
        _mapController.fitCamera(CameraFit.bounds(
            bounds: bounds, padding: const EdgeInsets.all(50)));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Đã vẽ tuyến với ${matchedStops.length} trạm')),
        );
      }
    } catch (e) {
      debugPrint('Error drawing route from API: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi: \$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchBusStops(String query) async {
    if (_busStopsData.isEmpty) {
      await _loadBusStops();
    }

    final results = _busStopsData
        .where((stop) {
          final name = (stop['name'] as String).toLowerCase();
          final ref = (stop['ref'] as String).toLowerCase();
          final searchTerm = query.toLowerCase();

          return name.contains(searchTerm) || ref.contains(searchTerm);
        })
        .take(10)
        .toList();

    if (mounted) {
      setState(() => _searchResults = results);
    }
  }

  Future<void> _loadBusStops() async {
    if (_busStopsData.isNotEmpty || !mounted) return;

    setState(() => _isLoading = true);

    try {
      const query = '''
[out:json][timeout:25];
(
  node["highway"="bus_stop"](10.6,106.4,11.0,106.9);
  node["public_transport"="platform"](10.6,106.4,11.0,106.9);
);
out body;
''';

      final url = Uri.parse('https://overpass-api.de/api/interpreter');
      final response = await http
          .post(url, body: query)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        _busStopsData = elements.map((element) {
          final tags = element['tags'] as Map<String, dynamic>?;
          return {
            'id': element['id'].toString(),
            'name': tags?['name'] ?? 'Trạm xe buýt',
            'ref': tags?['ref'] ?? '',
            'routes': tags?['route_ref'] ?? '',
            'lat': element['lat'] as double,
            'lon': element['lon'] as double,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectStop(Map<String, dynamic> stop) {
    final position = LatLng(stop['lat'] as double, stop['lon'] as double);

    setState(() {
      _searchController.clear();
      _searchResults = [];
      _routePoints = [];
      _selectedRouteStops.clear();
      _markers = [
        Marker(
          point: position,
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () => _showStopDetails(stop),
            child:
                const Icon(Icons.directions_bus, color: Colors.red, size: 40),
          ),
        ),
      ];
    });

    _mapController.move(position, 16);
    _showStopDetails(stop);
  }

  void _showStopDetails(Map<String, dynamic> stop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.directions_bus,
                      color: Colors.blue.shade700, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stop['name'] as String,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      if ((stop['ref'] as String).isNotEmpty)
                        Text('Mã: ${stop['ref']}',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            if ((stop['routes'] as String).isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Tuyến xe:',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(stop['routes'] as String,
                    style: const TextStyle(fontSize: 15)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showNearbyStops() async {
    if (_busStopsData.isEmpty) {
      setState(() => _isLoading = true);
      await _loadBusStops();
      if (mounted) setState(() => _isLoading = false);
    }

    final center = _userLocation ?? _currentPosition;
    final nearbyStops = _busStopsData.where((stop) {
      final distance = const Distance().as(
        LengthUnit.Kilometer,
        center,
        LatLng(stop['lat'] as double, stop['lon'] as double),
      );
      return distance <= _nearbyRadius;
    }).toList();

    if (!mounted) return;

    setState(() {
      _routePoints = [];
      _selectedRouteStops.clear();
      _markers = nearbyStops.map((stop) {
        return Marker(
          point: LatLng(stop['lat'] as double, stop['lon'] as double),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showStopDetails(stop),
            child:
                const Icon(Icons.directions_bus, color: Colors.blue, size: 32),
          ),
        );
      }).toList();
    });

    _mapController.move(center, 14);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Tìm thấy ${nearbyStops.length} trạm trong ${_nearbyRadius}km')),
    );
  }

  void _showNearbyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trạm gần tôi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chọn bán kính:'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [0.5, 1.0, 2.0, 3.0].map((radius) {
                final label = radius < 1
                    ? '${(radius * 1000).toInt()}m'
                    : '${radius.toInt()}km';
                return ChoiceChip(
                  label: Text(label),
                  selected: _nearbyRadius == radius,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _nearbyRadius = radius);
                      Navigator.pop(context);
                      _showNearbyStops();
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
  }

  void _showRouteBuilder() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tạo tuyến đường',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showApiRouteSelector();
                        },
                        icon: const Icon(Icons.bus_alert, size: 18),
                        label: const Text('Từ API'),
                      ),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ],
              ),
              const Divider(),
              if (_selectedRouteStops.isEmpty)
                Expanded(
                    child: Center(
                        child: Text('Chưa có trạm',
                            style: TextStyle(color: Colors.grey.shade600))))
              else
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _selectedRouteStops.length,
                    onReorder: (oldIndex, newIndex) {
                      setModalState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _selectedRouteStops.removeAt(oldIndex);
                        _selectedRouteStops.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final stop = _selectedRouteStops[index];
                      return Card(
                        key: ValueKey(stop['id']),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Text('${index + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: Text(stop['name'] as String),
                          subtitle: Text(stop['ref'] as String),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => setModalState(
                                () => _selectedRouteStops.removeAt(index)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showStopSelector(),
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Thêm trạm'),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedRouteStops.length >= 2
                          ? () {
                              Navigator.pop(context);
                              _drawRoute();
                            }
                          : null,
                      icon: const Icon(Icons.route),
                      label: const Text('Vẽ tuyến'),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStopSelector() async {
    if (_busStopsData.isEmpty) {
      setState(() => _isLoading = true);
      await _loadBusStops();
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    final searchController = TextEditingController();
    var filteredStops = List<Map<String, dynamic>>.from(_busStopsData);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSearchState) {
          void updateSearchResults(String query) {
            setSearchState(() {
              filteredStops = query.isEmpty
                  ? List<Map<String, dynamic>>.from(_busStopsData)
                  : _busStopsData.where((stop) {
                      final name = (stop['name'] as String).toLowerCase();
                      return name.contains(query.toLowerCase());
                    }).toList();
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('Chọn trạm',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                      maxWidth: 100,
                    ),
                    suffixIcon: SizedBox(
                      width: 88,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          VoiceInputIconButton(
                            controller: searchController,
                            tooltip: 'Nhập từ khóa bằng giọng nói',
                            stopTooltip: 'Dừng nhập giọng nói',
                            onTextChanged: updateSearchResults,
                          ),
                          TtsIconButton(
                            controller: searchController,
                            tooltip: 'Đọc từ khóa tìm kiếm',
                            emptyMessage: 'Bạn chưa nhập từ khóa để đọc.',
                          ),
                        ],
                      ),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: updateSearchResults,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredStops.length,
                    itemBuilder: (context, index) {
                      final stop = filteredStops[index];
                      final isSelected =
                          _selectedRouteStops.any((s) => s['id'] == stop['id']);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(Icons.directions_bus,
                              color: isSelected ? Colors.green : Colors.blue),
                          title: Text(stop['name'] as String),
                          subtitle: Text(stop['ref'] as String),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green)
                              : null,
                          onTap: () {
                            if (!isSelected) {
                              setState(() => _selectedRouteStops.add(stop));
                            }
                            Navigator.pop(context);
                            _showRouteBuilder();
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Show API route selector
  Future<void> _showApiRouteSelector() async {
    if (_apiRoutes.isEmpty) {
      await _fetchApiRoutes();
    }

    if (!mounted || _apiRoutes.isEmpty) return;

    final searchController = TextEditingController();

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => StatefulBuilder(
          builder: (context, setSearchState) {
            final query = searchController.text.trim().toLowerCase();
            final filteredRoutes = query.isEmpty
                ? _apiRoutes
                : _apiRoutes.where((route) {
                    final routeCode =
                        (route['routeCode'] ?? '').toString().toLowerCase();
                    final routeName =
                        (route['routeName'] ?? '').toString().toLowerCase();
                    final startPoint =
                        (route['startPoint'] ?? '').toString().toLowerCase();
                    final endPoint =
                        (route['endPoint'] ?? '').toString().toLowerCase();
                    return routeCode.contains(query) ||
                        routeName.contains(query) ||
                        startPoint.contains(query) ||
                        endPoint.contains(query);
                  }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Chọn tuyến xe',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm tuyến theo mã, tên hoặc điểm đầu-cuối',
                      prefixIcon: const Icon(Icons.search),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                        maxWidth: 176,
                      ),
                      suffixIcon: SizedBox(
                        width: 132,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            VoiceInputIconButton(
                              controller: searchController,
                              tooltip: 'Nhập từ khóa tuyến bằng giọng nói',
                              stopTooltip: 'Dừng nhập giọng nói',
                              onTextChanged: (_) => setSearchState(() {}),
                            ),
                            TtsIconButton(
                              controller: searchController,
                              tooltip: 'Đọc từ khóa tìm tuyến',
                              emptyMessage:
                                  'Bạn chưa nhập từ khóa tuyến để đọc.',
                            ),
                            if (searchController.text.trim().isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                tooltip: 'Xóa từ khóa',
                                onPressed: () {
                                  searchController.clear();
                                  setSearchState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (_) => setSearchState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredRoutes.isEmpty
                        ? const Center(
                            child: Text('Không tìm thấy tuyến phù hợp'),
                          )
                        : ListView.builder(
                            itemCount: filteredRoutes.length,
                            itemBuilder: (context, index) {
                              final route = filteredRoutes[index];
                              final routeCode =
                                  (route['routeCode'] ?? '').toString().trim();
                              final displayRouteCode =
                                  routeCode.isEmpty ? '?' : routeCode;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ExpansionTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue,
                                    child: Text(
                                      displayRouteCode,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                      (route['routeName'] ?? 'N/A').toString()),
                                  subtitle:
                                      Text('${route['totalDistance'] ?? 0} km'),
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.arrow_forward),
                                      title: const Text('Lượt đi'),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await _fetchAndDrawRoute(
                                            routeCode, true);
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.arrow_back),
                                      title: const Text('Lượt về'),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await _fetchAndDrawRoute(
                                          routeCode,
                                          false,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      searchController.dispose();
    }
  }

  // Fetch full route data and draw
  Future<void> _fetchAndDrawRoute(String routeCode, bool isForward) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final url = Uri.parse('${AppEnv.baseUrl}/api/v1/routes').replace(
        queryParameters: {
          'page': '1',
          'limit': '1',
          'direction': 'both',
          'routeCode': routeCode,
        },
      );
      final response = await http.get(
        url,
        headers: {'accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        await _drawRouteFromApi(data, isForward);
      }
    } catch (e) {
      debugPrint('Error: \$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi tải tuyến: \$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _drawRoute() async {
    if (_selectedRouteStops.length < 2 || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final allRoutePoints =
          await _buildRouteGeometryFromStops(_selectedRouteStops);

      if (!mounted) return;

      setState(() {
        _routePoints = allRoutePoints;
        _markers = _selectedRouteStops.asMap().entries.map((entry) {
          final index = entry.key;
          final stop = entry.value;
          return Marker(
            point: LatLng(stop['lat'] as double, stop['lon'] as double),
            width: 50,
            height: 50,
            child: GestureDetector(
              onTap: () => _showStopDetails(stop),
              child: Stack(
                children: [
                  const Icon(Icons.directions_bus,
                      color: Colors.green, size: 40),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: Text('${index + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();
      });

      if (_routePoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(_routePoints);
        _mapController.fitCamera(CameraFit.bounds(
            bounds: bounds, padding: const EdgeInsets.all(50)));
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartGo'),
        actions: [
          if (_markers.isNotEmpty || _routePoints.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () => setState(() {
                _markers = [];
                _routePoints = [];
                _selectedRouteStops.clear();
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
              initialZoom: 13,
              minZoom: 10,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smartgo.app',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: scheme.primary,
                      strokeWidth: 4.0,
                    )
                  ],
                ),
              MarkerLayer(markers: _markers),
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
                          border: Border.all(color: Colors.white, width: 3),
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
              elevation: 0,
              borderRadius: BorderRadius.circular(12),
              color: scheme.surface,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12)),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Tìm trạm...',
                        prefixIcon: const Icon(Icons.search),
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
                                onTextChanged: (_) {
                                  setState(() {});
                                  _onSearchChanged();
                                },
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(12)),
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _searchResults.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final stop = _searchResults[index];
                          return ListTile(
                            leading: Icon(
                              Icons.directions_bus,
                              color: scheme.primary,
                            ),
                            title: Text(stop['name'] as String),
                            subtitle: Text(stop['ref'] as String),
                            onTap: () => _selectStop(stop),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _isLoadingLocation ? null : _focusOnCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Vị trí tôi'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _showNearbyDialog,
                    icon: const Icon(Icons.near_me),
                    label: const Text('Gần tôi'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: scheme.surfaceContainerHighest,
                      foregroundColor: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _showRouteBuilder,
                    icon: const Icon(Icons.route),
                    label: const Text('Tìm đường'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang tải...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_isLoadingLocation)
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Đang lấy vị trí...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
