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
import 'package:smartgo/core/logging/app_logger.dart';
import 'package:smartgo/core/services/text_to_speech_service.dart';
import 'package:smartgo/core/services/route_geometry_service.dart';
import 'package:smartgo/core/themes/app_colors.dart';
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

class _PathGeometryLoadResult {
  final int index;
  final PathResult pathWithMetadata;
  final List<LatLng> transitGeometry;
  final List<List<LatLng>> transitGeometrySegments;
  final List<List<LatLng>> walkingGeometrySegments;
  final List<TransitStationAccessPoint> accessPoints;

  const _PathGeometryLoadResult({
    required this.index,
    required this.pathWithMetadata,
    required this.transitGeometry,
    required this.transitGeometrySegments,
    required this.walkingGeometrySegments,
    required this.accessPoints,
  });
}

class _PathGeometryCacheEntry {
  final PathResult pathWithMetadata;
  final List<LatLng> transitGeometry;
  final List<List<LatLng>> transitGeometrySegments;
  final List<List<LatLng>> walkingGeometrySegments;
  final List<TransitStationAccessPoint> accessPoints;

  const _PathGeometryCacheEntry({
    required this.pathWithMetadata,
    required this.transitGeometry,
    required this.transitGeometrySegments,
    required this.walkingGeometrySegments,
    required this.accessPoints,
  });

  _PathGeometryLoadResult toLoadResult(int index) {
    return _PathGeometryLoadResult(
      index: index,
      pathWithMetadata: pathWithMetadata,
      transitGeometry: transitGeometry,
      transitGeometrySegments: transitGeometrySegments,
      walkingGeometrySegments: walkingGeometrySegments,
      accessPoints: accessPoints,
    );
  }
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
  bool _isMapUiCollapsed = false;
  int? _selectedPathIndex;
  int _maxTransfers = 3;
  List<Station> _stations = [];
  List<PathResult>? _paths;
  bool _isLoading = false;
  bool _isSpeakingRouteGuide = false;

  // Route geometry service and cache
  final RouteGeometryService _routeGeometryService =
      getIt<RouteGeometryService>();
  List<TransitStationAccessPoint> _selectedTransitAccessPoints = const [];
  final Map<int, List<LatLng>> _pathRouteGeometryCache = {};
  final Map<int, List<List<LatLng>>> _pathRouteGeometrySegmentsCache = {};
  final Map<int, List<List<LatLng>>> _pathWalkingGeometrySegmentsCache = {};
  final Map<int, List<TransitStationAccessPoint>> _pathTransitAccessCache = {};
  final Map<String, _PathGeometryCacheEntry> _pathGeometryByKeyCache = {};
  final List<String> _pathGeometryByKeyOrder = [];
  bool _isLoadingGeometry = false;
  int _routeGeometryRequestId = 0;

  static const int _maxPathGeometryByKeyCacheEntries = 24;

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

    if (path.hasWalkingLegs) {
      buffer.writeln(
        'Tổng quãng đường đi bộ khoảng ${path.formattedWalkingDistance}, thời gian đi bộ ước tính ${path.formattedWalkingTime}.',
      );
    }

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

    if (path.walkingLegs.isNotEmpty) {
      buffer.writeln('Chi tiết các chặng đi bộ.');
      for (var i = 0; i < path.walkingLegs.length; i++) {
        final leg = path.walkingLegs[i];
        buffer.writeln('Chặng đi bộ ${i + 1}. ${_walkingLegSpeechText(leg)}');
      }
    }

    final stationAccessWalkingLegs = path.stationAccessWalkingLegs;
    if (stationAccessWalkingLegs.isNotEmpty) {
      buffer.writeln('Các đoạn đi bộ từ đường chính vào trạm.');
      for (var i = 0; i < stationAccessWalkingLegs.length; i++) {
        final leg = stationAccessWalkingLegs[i];
        buffer.writeln(
          'Đoạn ${i + 1}. Đi bộ khoảng ${leg.distanceKm.toStringAsFixed(2)} ki lô mét trong ${leg.estimatedTimeMinutes.toStringAsFixed(0)} phút để vào trạm ${leg.stationName}.',
        );
      }
    }

    buffer.writeln(
      'Lưu ý an toàn. Hãy đi chậm, bám tay vịn khi lên xuống xe. Ưu tiên lối đi bằng phẳng và khu vực có ánh sáng tốt. Nếu cần, hãy nhờ phụ xe hoặc người xung quanh hỗ trợ.',
    );
    buffer.writeln('Chúc bạn di chuyển an toàn.');

    return buffer.toString();
  }

  String _walkingLegSpeechText(WalkingLeg leg) {
    final distance = leg.distanceKm > 0
        ? '${leg.distanceKm.toStringAsFixed(1)} ki lô mét'
        : 'một quãng ngắn';
    final duration = leg.estimatedTimeMinutes > 0
        ? '${leg.estimatedTimeMinutes.toStringAsFixed(0)} phút'
        : 'vài phút';

    if (leg.isToFirstStation) {
      return 'Đi bộ $distance trong khoảng $duration đến trạm ${leg.stationName} để lên xe.';
    }

    if (leg.isFromLastStation) {
      return 'Đi bộ $distance trong khoảng $duration từ trạm ${leg.stationName} đến điểm đến.';
    }

    if (leg.isTransfer) {
      final fromName =
          leg.fromStationName ?? leg.fromStationCode ?? 'trạm trước';
      return 'Đi bộ $distance trong khoảng $duration để chuyển tuyến từ $fromName sang ${leg.stationName}.';
    }

    return 'Đi bộ $distance trong khoảng $duration quanh khu vực trạm ${leg.stationName}.';
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

  List<LatLng> _buildTransitDrivingWaypoints(
    PathResult path, {
    List<TransitStationAccessPoint>? accessPoints,
  }) {
    if (accessPoints != null && accessPoints.isNotEmpty) {
      return accessPoints
          .map((station) => station.busAccessCoordinate)
          .toList(growable: false);
    }

    return path.stations
        .map((station) => station.busAccessCoordinate)
        .map((coordinate) => LatLng(coordinate.latitude, coordinate.longitude))
        .toList(growable: false);
  }

  String _normalizeStationIdentity(String value) {
    return value.trim().toLowerCase();
  }

  int _findStationIndexByIdentity(
    List<PathStationInfo> stations,
    String identity, {
    int startAt = 0,
  }) {
    final normalizedIdentity = _normalizeStationIdentity(identity);
    if (normalizedIdentity.isEmpty) {
      return -1;
    }

    final safeStart = startAt < 0 ? 0 : startAt;
    for (var index = safeStart; index < stations.length; index++) {
      final station = stations[index];
      final stationCode = _normalizeStationIdentity(station.stationCode);
      final stationName = _normalizeStationIdentity(station.stationName);
      if (stationCode == normalizedIdentity ||
          stationName == normalizedIdentity) {
        return index;
      }

      if (stationCode.isNotEmpty &&
          (stationCode.contains(normalizedIdentity) ||
              normalizedIdentity.contains(stationCode))) {
        return index;
      }

      if (stationName.isNotEmpty &&
          (stationName.contains(normalizedIdentity) ||
              normalizedIdentity.contains(stationName))) {
        return index;
      }
    }

    return -1;
  }

  int _findStationIndexByCodeOrName(
    List<PathStationInfo> stations, {
    String? stationCode,
    String? stationName,
    int startAt = 0,
  }) {
    if (stationCode != null && stationCode.trim().isNotEmpty) {
      final byCode = _findStationIndexByIdentity(
        stations,
        stationCode,
        startAt: startAt,
      );
      if (byCode != -1) {
        return byCode;
      }

      final byCodeFallback = _findStationIndexByIdentity(
        stations,
        stationCode,
      );
      if (byCodeFallback != -1) {
        return byCodeFallback;
      }
    }

    if (stationName != null && stationName.trim().isNotEmpty) {
      final byName = _findStationIndexByIdentity(
        stations,
        stationName,
        startAt: startAt,
      );
      if (byName != -1) {
        return byName;
      }

      final byNameFallback = _findStationIndexByIdentity(
        stations,
        stationName,
      );
      if (byNameFallback != -1) {
        return byNameFallback;
      }
    }

    return -1;
  }

  List<List<PathStationInfo>> _buildTransitStationGroupsFromWalkingLegs(
    PathResult path,
    List<PathStationInfo> stations,
  ) {
    if (stations.length < 2) {
      return const <List<PathStationInfo>>[];
    }

    var startIndex = 0;
    var endIndex = stations.length - 1;

    for (final leg in path.walkingLegs) {
      if (leg.isToFirstStation) {
        final candidateIndex = _findStationIndexByCodeOrName(
          stations,
          stationCode: leg.stationCode,
          stationName: leg.stationName,
          startAt: startIndex,
        );
        if (candidateIndex != -1) {
          startIndex = candidateIndex;
        }
        break;
      }
    }

    for (final leg in path.walkingLegs) {
      if (leg.isFromLastStation) {
        final candidateIndex = _findStationIndexByCodeOrName(
          stations,
          stationCode: leg.stationCode,
          stationName: leg.stationName,
          startAt: startIndex,
        );
        if (candidateIndex != -1) {
          endIndex = candidateIndex;
        }
        break;
      }
    }

    if (endIndex - startIndex < 1) {
      return const <List<PathStationInfo>>[];
    }

    final transferPairs = <MapEntry<int, int>>[];
    for (final leg in path.walkingLegs) {
      if (!leg.isTransfer) {
        continue;
      }

      final fromIndex = _findStationIndexByCodeOrName(
        stations,
        stationCode: leg.fromStationCode,
        stationName: leg.fromStationName,
        startAt: startIndex,
      );
      final toIndex = _findStationIndexByCodeOrName(
        stations,
        stationCode: leg.stationCode,
        stationName: leg.stationName,
        startAt: fromIndex != -1 ? fromIndex : startIndex,
      );

      if (fromIndex == -1 || toIndex == -1 || fromIndex == toIndex) {
        continue;
      }

      final pairStart = fromIndex < toIndex ? fromIndex : toIndex;
      final pairEnd = fromIndex < toIndex ? toIndex : fromIndex;
      if (pairEnd < startIndex || pairStart > endIndex) {
        continue;
      }

      transferPairs.add(MapEntry(pairStart, pairEnd));
    }

    if (transferPairs.isEmpty) {
      final baseGroup = stations.sublist(startIndex, endIndex + 1);
      return baseGroup.length >= 2
          ? <List<PathStationInfo>>[baseGroup]
          : const <List<PathStationInfo>>[];
    }

    transferPairs.sort((a, b) => a.key.compareTo(b.key));

    final groups = <List<PathStationInfo>>[];
    var groupStart = startIndex;

    for (final pair in transferPairs) {
      final transferFrom = pair.key;
      final transferTo = pair.value;

      if (transferFrom < groupStart || transferFrom > endIndex) {
        continue;
      }

      if (transferFrom - groupStart >= 1) {
        groups.add(stations.sublist(groupStart, transferFrom + 1));
      }

      if (transferTo > groupStart && transferTo <= endIndex) {
        groupStart = transferTo;
      }
    }

    if (endIndex - groupStart >= 1) {
      groups.add(stations.sublist(groupStart, endIndex + 1));
    }

    return groups;
  }

  List<List<PathStationInfo>> _buildTransitStationGroups(
    PathResult path,
    List<PathStationInfo> stations,
  ) {
    if (stations.length < 2) {
      return const <List<PathStationInfo>>[];
    }

    if (path.segments.isEmpty) {
      return <List<PathStationInfo>>[stations];
    }

    final groups = <List<PathStationInfo>>[];
    var searchStart = 0;

    for (final segment in path.segments) {
      var startIndex = _findStationIndexByIdentity(
        stations,
        segment.from,
        startAt: searchStart,
      );
      if (startIndex == -1) {
        startIndex = _findStationIndexByIdentity(stations, segment.from);
      }

      var endIndex = _findStationIndexByIdentity(
        stations,
        segment.to,
        startAt: startIndex >= 0 ? startIndex : 0,
      );
      if (endIndex == -1) {
        endIndex = _findStationIndexByIdentity(stations, segment.to);
      }

      if (startIndex == -1 || endIndex == -1) {
        continue;
      }

      if (startIndex > endIndex) {
        final temp = startIndex;
        startIndex = endIndex;
        endIndex = temp;
      }

      final segmentStations = stations.sublist(startIndex, endIndex + 1);
      if (segmentStations.length >= 2) {
        groups.add(segmentStations);
      }

      searchStart = endIndex;
    }

    if (groups.isEmpty) {
      final groupsByWalkingLegs =
          _buildTransitStationGroupsFromWalkingLegs(path, stations);
      if (groupsByWalkingLegs.isNotEmpty) {
        return groupsByWalkingLegs;
      }

      var startIndex = 0;
      var endIndex = stations.length - 1;

      final hasToFirstStationWalk =
          path.walkingLegs.any((leg) => leg.isToFirstStation);
      final hasFromLastStationWalk =
          path.walkingLegs.any((leg) => leg.isFromLastStation);

      if (hasToFirstStationWalk && stations.length > 2) {
        startIndex = 1;
      }
      if (hasFromLastStationWalk && endIndex - startIndex >= 2) {
        endIndex -= 1;
      }

      if (endIndex - startIndex >= 1) {
        return <List<PathStationInfo>>[
          stations.sublist(startIndex, endIndex + 1),
        ];
      }

      return <List<PathStationInfo>>[stations];
    }

    return groups;
  }

  List<LatLng> _flattenTransitGeometrySegments(List<List<LatLng>> segments) {
    if (segments.isEmpty) {
      return const <LatLng>[];
    }

    final merged = <LatLng>[];
    for (final segment in segments) {
      if (segment.isEmpty) {
        continue;
      }

      if (merged.isEmpty) {
        merged.addAll(segment);
        continue;
      }

      final isConnected =
          _calculateDistance(merged.last, segment.first) <= 0.002;
      if (isConnected) {
        merged.addAll(segment.skip(1));
      } else {
        merged.addAll(segment);
      }
    }

    return merged;
  }

  String _buildPathGeometryCacheKey(
    PathResult path, {
    required bool includeWalkingGeometry,
  }) {
    final stationKey = path.stations
        .map(
          (station) =>
              '${_normalizeStationIdentity(station.stationCode)}@${station.latitude.toStringAsFixed(6)},${station.longitude.toStringAsFixed(6)}',
        )
        .join(';');

    final segmentKey = path.segments
        .map(
          (segment) =>
              '${_normalizeStationIdentity(segment.routeCode)}:${_normalizeStationIdentity(segment.from)}>${_normalizeStationIdentity(segment.to)}',
        )
        .join('|');

    final walkingKey = includeWalkingGeometry
        ? _walkingLegsForMap(path)
            .map(
              (leg) =>
                  '${leg.normalizedType}:${_normalizeStationIdentity(leg.fromStationCode ?? '')}>${_normalizeStationIdentity(leg.stationCode)}@${leg.fromCoordinates.latitude.toStringAsFixed(6)},${leg.fromCoordinates.longitude.toStringAsFixed(6)}-${leg.toCoordinates.latitude.toStringAsFixed(6)},${leg.toCoordinates.longitude.toStringAsFixed(6)}',
            )
            .join('|')
        : 'no-walking';

    return '$stationKey#$segmentKey#$walkingKey';
  }

  void _cachePathGeometryByKey(
    String cacheKey,
    _PathGeometryLoadResult result,
  ) {
    _pathGeometryByKeyCache[cacheKey] = _PathGeometryCacheEntry(
      pathWithMetadata: result.pathWithMetadata,
      transitGeometry: result.transitGeometry,
      transitGeometrySegments: result.transitGeometrySegments,
      walkingGeometrySegments: result.walkingGeometrySegments,
      accessPoints: result.accessPoints,
    );

    _pathGeometryByKeyOrder.remove(cacheKey);
    _pathGeometryByKeyOrder.add(cacheKey);
    if (_pathGeometryByKeyOrder.length <= _maxPathGeometryByKeyCacheEntries) {
      return;
    }

    final keyToRemove = _pathGeometryByKeyOrder.removeAt(0);
    _pathGeometryByKeyCache.remove(keyToRemove);
  }

  Map<String, int> _snapshotOsrmRequestStats() {
    return _routeGeometryService.getOsrmRequestStatsSnapshot();
  }

  void _logOsrmRequestStatsDelta(
    String scope,
    Map<String, int> before,
    Map<String, int> after,
  ) {
    final routeDelta = (after['route'] ?? 0) - (before['route'] ?? 0);
    final matchDelta = (after['match'] ?? 0) - (before['match'] ?? 0);
    final nearestDelta = (after['nearest'] ?? 0) - (before['nearest'] ?? 0);
    final walkingDelta = (after['walking'] ?? 0) - (before['walking'] ?? 0);
    final totalDelta = routeDelta + matchDelta + nearestDelta + walkingDelta;

    if (totalDelta <= 0) {
      return;
    }

    AppLogger.info(
      '$scope OSRM delta route=$routeDelta match=$matchDelta nearest=$nearestDelta walking=$walkingDelta total=$totalDelta',
    );
  }

  List<LatLng> _buildStationGroupWaypoints(List<PathStationInfo> stationGroup) {
    return stationGroup
        .map((station) => station.busAccessCoordinate)
        .map((coordinate) => LatLng(coordinate.latitude, coordinate.longitude))
        .toList(growable: false);
  }

  int _findNearestGeometryIndexForward(
    List<LatLng> geometry,
    LatLng anchor, {
    required int startIndex,
  }) {
    if (geometry.isEmpty) {
      return -1;
    }

    var safeStartIndex = startIndex;
    if (safeStartIndex < 0) {
      safeStartIndex = 0;
    }
    if (safeStartIndex >= geometry.length) {
      return -1;
    }

    var bestIndex = -1;
    var bestDistanceKm = double.infinity;

    for (var i = safeStartIndex; i < geometry.length; i++) {
      final distanceKm = _calculateDistance(geometry[i], anchor);
      if (distanceKm < bestDistanceKm) {
        bestDistanceKm = distanceKm;
        bestIndex = i;
      }
    }

    const maxAnchorSnapDistanceKm = 1.0;
    if (bestDistanceKm > maxAnchorSnapDistanceKm) {
      return -1;
    }

    return bestIndex;
  }

  List<List<LatLng>> _splitGeometryByStationGroups({
    required List<LatLng> fullGeometry,
    required List<List<PathStationInfo>> stationGroups,
  }) {
    if (fullGeometry.length < 2 || stationGroups.isEmpty) {
      return const <List<LatLng>>[];
    }

    final segments = <List<LatLng>>[];
    var searchStartIndex = 0;

    for (final stationGroup in stationGroups) {
      final groupWaypoints = _buildStationGroupWaypoints(stationGroup);
      if (groupWaypoints.length < 2) {
        continue;
      }

      final startIndex = _findNearestGeometryIndexForward(
        fullGeometry,
        groupWaypoints.first,
        startIndex: searchStartIndex,
      );
      final endIndex = startIndex == -1
          ? -1
          : _findNearestGeometryIndexForward(
              fullGeometry,
              groupWaypoints.last,
              startIndex: startIndex,
            );

      if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
        segments.add(groupWaypoints);
        continue;
      }

      final sliced = fullGeometry.sublist(startIndex, endIndex + 1);
      if (sliced.length >= 2) {
        segments.add(sliced);
        searchStartIndex = endIndex;
      } else {
        segments.add(groupWaypoints);
      }
    }

    return segments;
  }

  List<TransitStationAccessPoint> _safeSelectedTransitAccessPoints() {
    try {
      final dynamic raw = _selectedTransitAccessPoints;
      if (raw == null) {
        return const <TransitStationAccessPoint>[];
      }
      if (raw is List<TransitStationAccessPoint>) {
        return raw;
      }
      if (raw is List) {
        return raw
            .whereType<TransitStationAccessPoint>()
            .toList(growable: false);
      }
    } catch (_) {
      // Hot reload on web may keep stale state objects with undefined fields.
    }

    return const <TransitStationAccessPoint>[];
  }

  List<LatLng>? _safeRouteGeometryFromCache(int index) {
    try {
      final dynamic raw = _pathRouteGeometryCache;
      if (raw is! Map) {
        return null;
      }

      final dynamic value = raw[index];
      if (value is List<LatLng>) {
        return value;
      }
      if (value is List) {
        final points = value.whereType<LatLng>().toList(growable: false);
        return points.isEmpty ? null : points;
      }
    } catch (_) {
      // Hot reload on web may keep stale state objects with undefined fields.
    }

    return null;
  }

  List<List<LatLng>>? _safeRouteGeometrySegmentsFromCache(int index) {
    try {
      final dynamic raw = _pathRouteGeometrySegmentsCache;
      if (raw is! Map) {
        return null;
      }

      final dynamic value = raw[index];
      if (value is List<List<LatLng>>) {
        return value.where((segment) => segment.length >= 2).toList();
      }
      if (value is List) {
        final segments = <List<LatLng>>[];
        for (final segment in value) {
          if (segment is List<LatLng>) {
            if (segment.length >= 2) {
              segments.add(segment);
            }
            continue;
          }
          if (segment is List) {
            final points = segment.whereType<LatLng>().toList(growable: false);
            if (points.length >= 2) {
              segments.add(points);
            }
          }
        }
        return segments.isEmpty ? null : segments;
      }
    } catch (_) {
      // Hot reload on web may keep stale state objects with undefined fields.
    }

    return null;
  }

  List<List<LatLng>>? _safeWalkingGeometrySegmentsFromCache(int index) {
    try {
      final dynamic raw = _pathWalkingGeometrySegmentsCache;
      if (raw is! Map) {
        return null;
      }

      final dynamic value = raw[index];
      if (value is List<List<LatLng>>) {
        return value.where((segment) => segment.length >= 2).toList();
      }
      if (value is List) {
        final segments = <List<LatLng>>[];
        for (final segment in value) {
          if (segment is List<LatLng>) {
            if (segment.length >= 2) {
              segments.add(segment);
            }
            continue;
          }
          if (segment is List) {
            final points = segment.whereType<LatLng>().toList(growable: false);
            if (points.length >= 2) {
              segments.add(points);
            }
          }
        }
        return segments.isEmpty ? null : segments;
      }
    } catch (_) {
      // Hot reload on web may keep stale state objects with undefined fields.
    }

    return null;
  }

  List<TransitStationAccessPoint>? _safeTransitAccessFromCache(int index) {
    try {
      final dynamic raw = _pathTransitAccessCache;
      if (raw is! Map) {
        return null;
      }

      final dynamic value = raw[index];
      if (value is List<TransitStationAccessPoint>) {
        return value;
      }
      if (value is List) {
        final points = value
            .whereType<TransitStationAccessPoint>()
            .toList(growable: false);
        return points.isEmpty ? null : points;
      }
    } catch (_) {
      // Hot reload on web may keep stale state objects with undefined fields.
    }

    return null;
  }

  void _safeCacheRouteGeometry(int index, List<LatLng> geometry) {
    try {
      _pathRouteGeometryCache[index] = geometry;
    } catch (_) {
      // Ignore cache update if stale web state cannot write this field.
    }
  }

  void _safeCacheRouteGeometrySegments(
    int index,
    List<List<LatLng>> geometrySegments,
  ) {
    try {
      _pathRouteGeometrySegmentsCache[index] = geometrySegments;
    } catch (_) {
      // Ignore cache update if stale web state cannot write this field.
    }
  }

  void _safeCacheWalkingGeometrySegments(
    int index,
    List<List<LatLng>> geometrySegments,
  ) {
    try {
      _pathWalkingGeometrySegmentsCache[index] = geometrySegments;
    } catch (_) {
      // Ignore cache update if stale web state cannot write this field.
    }
  }

  void _safeCacheTransitAccess(
    int index,
    List<TransitStationAccessPoint> accessPoints,
  ) {
    try {
      _pathTransitAccessCache[index] = accessPoints;
    } catch (_) {
      // Ignore cache update if stale web state cannot write this field.
    }
  }

  void _safeClearGeometryCaches() {
    try {
      _pathRouteGeometryCache.clear();
    } catch (_) {
      // Ignore cache clear if stale web state cannot access this field.
    }

    try {
      _pathRouteGeometrySegmentsCache.clear();
    } catch (_) {
      // Ignore cache clear if stale web state cannot access this field.
    }

    try {
      _pathWalkingGeometrySegmentsCache.clear();
    } catch (_) {
      // Ignore cache clear if stale web state cannot access this field.
    }

    try {
      _pathTransitAccessCache.clear();
    } catch (_) {
      // Ignore cache clear if stale web state cannot access this field.
    }
  }

  void _safeReplaceGeometryCaches({
    required Map<int, List<LatLng>> routeGeometry,
    required Map<int, List<List<LatLng>>> routeGeometrySegments,
    required Map<int, List<List<LatLng>>> walkingGeometrySegments,
    required Map<int, List<TransitStationAccessPoint>> transitAccess,
  }) {
    _safeClearGeometryCaches();

    try {
      _pathRouteGeometryCache.addAll(routeGeometry);
    } catch (_) {
      // Ignore cache update if stale web state cannot access this field.
    }

    try {
      _pathRouteGeometrySegmentsCache.addAll(routeGeometrySegments);
    } catch (_) {
      // Ignore cache update if stale web state cannot access this field.
    }

    try {
      _pathWalkingGeometrySegmentsCache.addAll(walkingGeometrySegments);
    } catch (_) {
      // Ignore cache update if stale web state cannot access this field.
    }

    try {
      _pathTransitAccessCache.addAll(transitAccess);
    } catch (_) {
      // Ignore cache update if stale web state cannot access this field.
    }
  }

  List<WalkingLeg> _walkingLegsForMap(PathResult path) {
    final merged = <WalkingLeg>[
      ...path.walkingLegs,
      ...path.stationAccessWalkingLegs,
    ];
    final seen = <String>{};
    final unique = <WalkingLeg>[];

    for (final leg in merged) {
      final key = [
        leg.normalizedType,
        leg.fromCoordinates.latitude.toStringAsFixed(6),
        leg.fromCoordinates.longitude.toStringAsFixed(6),
        leg.toCoordinates.latitude.toStringAsFixed(6),
        leg.toCoordinates.longitude.toStringAsFixed(6),
        leg.stationCode,
      ].join('|');

      if (seen.add(key)) {
        unique.add(leg);
      }
    }

    return unique;
  }

  LatLng _interpolatePoint(LatLng from, LatLng to, double factor) {
    return LatLng(
      from.latitude + ((to.latitude - from.latitude) * factor),
      from.longitude + ((to.longitude - from.longitude) * factor),
    );
  }

  List<Polyline> _buildDashedWalkingSegments(
    LatLng from,
    LatLng to, {
    required Color color,
    required double strokeWidth,
  }) {
    final distanceKm = _calculateDistance(from, to);
    var totalSegments = (distanceKm * 30).round();
    if (totalSegments < 8) {
      totalSegments = 8;
    }
    if (totalSegments > 30) {
      totalSegments = 30;
    }
    if (totalSegments.isOdd) {
      totalSegments += 1;
    }

    final segments = <Polyline>[];
    for (var segmentIndex = 0;
        segmentIndex < totalSegments;
        segmentIndex += 2) {
      final startFactor = segmentIndex / totalSegments;
      final endFactor = (segmentIndex + 1) / totalSegments;
      segments.add(
        Polyline(
          points: [
            _interpolatePoint(from, to, startFactor),
            _interpolatePoint(from, to, endFactor),
          ],
          strokeWidth: strokeWidth,
          color: color,
        ),
      );
    }

    return segments;
  }

  List<Polyline> _buildDashedWalkingPolyline(
    List<LatLng> points, {
    required Color outlineColor,
    required Color dashColor,
    required double outlineWidth,
    required double dashWidth,
  }) {
    if (points.length < 2) {
      return const <Polyline>[];
    }

    final polylines = <Polyline>[];
    polylines.add(
      Polyline(
        points: points,
        strokeWidth: outlineWidth,
        color: outlineColor,
      ),
    );

    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i];
      final to = points[i + 1];
      if (_calculateDistance(from, to) <= 0) {
        continue;
      }
      polylines.addAll(
        _buildDashedWalkingSegments(
          from,
          to,
          color: dashColor,
          strokeWidth: dashWidth,
        ),
      );
    }

    return polylines;
  }

  List<Polyline> _buildWalkingLegPolylines(
    int pathIndex,
    PathResult path, {
    required bool isSelected,
  }) {
    final legs = _walkingLegsForMap(path);
    if (legs.isEmpty) {
      return const <Polyline>[];
    }

    final walkingSegments = _safeWalkingGeometrySegmentsFromCache(pathIndex);
    if (isSelected && (walkingSegments == null || walkingSegments.isEmpty)) {
      return const <Polyline>[];
    }

    final outlineColor = Colors.white.withValues(
      alpha: isSelected ? 0.75 : 0.3,
    );
    final dashColor = AppColors.aiWarning.withValues(
      alpha: isSelected ? 0.82 : 0.4,
    );
    final outlineWidth = isSelected ? 3.4 : 2.4;
    final dashWidth = isSelected ? 2.0 : 1.35;

    final polylines = <Polyline>[];
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final from = LatLng(
        leg.fromCoordinates.latitude,
        leg.fromCoordinates.longitude,
      );
      final to = LatLng(
        leg.toCoordinates.latitude,
        leg.toCoordinates.longitude,
      );
      if (_calculateDistance(from, to) <= 0) {
        continue;
      }

      final segmentGeometry =
          (walkingSegments != null && i < walkingSegments.length)
              ? walkingSegments[i]
              : <LatLng>[from, to];
      final usableGeometry =
          segmentGeometry.length >= 2 ? segmentGeometry : <LatLng>[from, to];

      polylines.addAll(
        _buildDashedWalkingPolyline(
          usableGeometry,
          outlineColor: outlineColor,
          dashColor: dashColor,
          outlineWidth: outlineWidth,
          dashWidth: dashWidth,
        ),
      );
    }

    return polylines;
  }

  List<LatLng> _mergeMapPoints(List<LatLng> points) {
    if (points.isEmpty) {
      return const <LatLng>[];
    }

    final merged = <LatLng>[points.first];
    for (final point in points.skip(1)) {
      final previous = merged.last;
      if (_calculateDistance(previous, point) >= 0.002) {
        merged.add(point);
      }
    }

    return merged;
  }

  Color _pathColor(int index) {
    const palette = AppColors.pathResultPalette;
    return palette[index % palette.length];
  }

  PathResult? _selectedPath() {
    final paths = _paths;
    final selectedIndex = _selectedPathIndex;
    if (paths == null || selectedIndex == null) {
      return null;
    }
    if (selectedIndex < 0 || selectedIndex >= paths.length) {
      return null;
    }
    return paths[selectedIndex];
  }

  List<Polyline> _buildRoutePolylines() {
    final paths = _paths;
    if (paths == null || paths.isEmpty) {
      return const <Polyline>[];
    }

    final selectedIndex = _selectedPathIndex;
    final selectedTransitAccessPoints = _safeSelectedTransitAccessPoints();
    final polylines = <Polyline>[];

    for (var index = 0; index < paths.length; index++) {
      final path = paths[index];
      final isSelected = selectedIndex == index;
      final cachedGeometry = _safeRouteGeometryFromCache(index);
      final cachedGeometrySegments = _safeRouteGeometrySegmentsFromCache(index);
      final cachedAccessPoints = _safeTransitAccessFromCache(index);
      final fallbackPoints =
          (cachedGeometry != null && cachedGeometry.isNotEmpty)
              ? cachedGeometry
              : _buildTransitDrivingWaypoints(
                  path,
                  accessPoints: isSelected
                      ? selectedTransitAccessPoints
                      : cachedAccessPoints,
                );

      final segmentGeometries =
          (cachedGeometrySegments != null && cachedGeometrySegments.isNotEmpty)
              ? cachedGeometrySegments
              : (fallbackPoints.length >= 2
                  ? <List<LatLng>>[fallbackPoints]
                  : const <List<LatLng>>[]);

      if (segmentGeometries.isEmpty) {
        continue;
      }

      final color = _pathColor(index);

      if (isSelected) {
        for (final segmentPoints in segmentGeometries) {
          polylines.add(
            Polyline(
              points: segmentPoints,
              strokeWidth: 7,
              color: Colors.white,
            ),
          );
        }
      }

      for (final segmentPoints in segmentGeometries) {
        polylines.add(
          Polyline(
            points: segmentPoints,
            strokeWidth: isSelected ? 4.5 : 2.4,
            color: isSelected ? color : color.withValues(alpha: 0.38),
          ),
        );
      }

      polylines.addAll(
        _buildWalkingLegPolylines(index, path, isSelected: isSelected),
      );
    }

    return polylines;
  }

  List<Marker> _buildSelectedPathMarkers(PathResult? path,
      {required Color color}) {
    if (path == null) {
      return const <Marker>[];
    }

    List<PathStationInfo> stations;
    try {
      stations = path.stations;
    } catch (_) {
      return const <Marker>[];
    }

    if (stations.isEmpty) {
      return const <Marker>[];
    }

    final lastStationIndex = stations.length - 1;
    final stationMarkers = stations.asMap().entries.map((entry) {
      final index = entry.key;
      final station = entry.value;
      final isStart = index == 0;
      final isEnd = index == lastStationIndex;
      final markerLabel = isStart
          ? 'A'
          : isEnd
              ? 'B'
              : '${index + 1}';

      return Marker(
        point: LatLng(station.latitude, station.longitude),
        width: 50,
        height: 58,
        child: GestureDetector(
          onTap: () => _showInfo(station.stationName),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_bus,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isStart
                      ? Colors.green
                      : isEnd
                          ? Colors.red
                          : color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  markerLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    final selectedTransitAccessPoints = _safeSelectedTransitAccessPoints();
    final accessMarkers = <Marker>[];
    for (var index = 0;
        index < selectedTransitAccessPoints.length && index < stations.length;
        index++) {
      final access = selectedTransitAccessPoints[index];
      if (access.walkDistanceToAccessPointKm <= 0) {
        continue;
      }

      accessMarkers.add(
        Marker(
          point: access.busAccessCoordinate,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showInfo(
              'Điểm đón/trả trên đường chính cho trạm ${stations[index].stationName}',
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.alt_route,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      );
    }

    return [
      ...stationMarkers,
      ...accessMarkers,
    ];
  }

  void _fitMapToPath(PathResult path, {List<LatLng>? preferredPoints}) {
    final selectedTransitAccessPoints = _safeSelectedTransitAccessPoints();
    final basePoints = (preferredPoints != null && preferredPoints.isNotEmpty)
        ? preferredPoints
        : _buildPathPolyline(path);
    final points = _mergeMapPoints([
      ...basePoints,
      ...selectedTransitAccessPoints
          .map((accessPoint) => accessPoint.busAccessCoordinate),
    ]);

    if (points.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (points.length == 1) {
        _mapController.move(points.first, 16);
        return;
      }

      final bounds = LatLngBounds.fromPoints(points);
      final bottomPadding =
          (_showResults && !_isMapUiCollapsed) ? 280.0 : 120.0;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.fromLTRB(36, 96, 36, bottomPadding),
        ),
      );
    });
  }

  Future<List<List<LatLng>>> _resolveWalkingGeometrySegments(
    PathResult path,
  ) async {
    final walkingLegs = _walkingLegsForMap(path);
    if (walkingLegs.isEmpty) {
      return const <List<LatLng>>[];
    }

    final segmentFutures = walkingLegs.map((leg) async {
      final from = LatLng(
        leg.fromCoordinates.latitude,
        leg.fromCoordinates.longitude,
      );
      final to = LatLng(
        leg.toCoordinates.latitude,
        leg.toCoordinates.longitude,
      );

      if (_calculateDistance(from, to) <= 0) {
        return <LatLng>[from, to];
      }

      final geometry = await _routeGeometryService.getWalkingGeometry(
        from: from,
        to: to,
      );
      if (geometry.length >= 2) {
        return geometry;
      }

      return <LatLng>[from, to];
    }).toList(growable: false);

    return Future.wait(segmentFutures);
  }

  Future<_PathGeometryLoadResult> _resolvePathGeometry({
    required int index,
    required PathResult path,
    required bool includeWalkingGeometry,
  }) async {
    if (path.stations.length < 2) {
      final fallbackGeometry = _buildTransitDrivingWaypoints(path);
      return _PathGeometryLoadResult(
        index: index,
        pathWithMetadata: path,
        transitGeometry: fallbackGeometry,
        transitGeometrySegments: fallbackGeometry.length >= 2
            ? <List<LatLng>>[fallbackGeometry]
            : const <List<LatLng>>[],
        walkingGeometrySegments: const <List<LatLng>>[],
        accessPoints: const [],
      );
    }

    final geometryCacheKey = _buildPathGeometryCacheKey(
      path,
      includeWalkingGeometry: includeWalkingGeometry,
    );
    final cachedByKey = _pathGeometryByKeyCache[geometryCacheKey];
    if (cachedByKey != null) {
      return cachedByKey.toLoadResult(index);
    }

    final stopCoordinates = path.stations
        .map((station) => LatLng(station.latitude, station.longitude))
        .toList(growable: false);

    final transitResult =
        await _routeGeometryService.buildTransitGeometryWithAccessPoints(
      stopCoordinates,
    );

    final stationsWithAccessMetadata = _applyAccessMetadataToStations(
      path.stations,
      transitResult.stationAccessPoints,
    );
    final pathWithAccessMetadata = path.copyWith(
      stations: stationsWithAccessMetadata,
    );

    final walkingGeometrySegments = includeWalkingGeometry
        ? await _resolveWalkingGeometrySegments(pathWithAccessMetadata)
        : const <List<LatLng>>[];

    final stationGroups = _buildTransitStationGroups(
        pathWithAccessMetadata, stationsWithAccessMetadata);
    final transitGeometrySegments = <List<LatLng>>[];

    final resolvedGeometry = transitResult.transitGeometry.isNotEmpty
        ? transitResult.transitGeometry
        : transitResult.drivingWaypoints;

    if (stationGroups.length <= 1) {
      if (resolvedGeometry.length >= 2) {
        transitGeometrySegments.add(resolvedGeometry);
      }
    } else {
      transitGeometrySegments.addAll(
        _splitGeometryByStationGroups(
          fullGeometry: resolvedGeometry,
          stationGroups: stationGroups,
        ),
      );
    }

    final resolvedSegments = transitGeometrySegments.isNotEmpty
        ? transitGeometrySegments
        : (resolvedGeometry.length >= 2
            ? <List<LatLng>>[resolvedGeometry]
            : const <List<LatLng>>[]);

    final flattenedGeometry = _flattenTransitGeometrySegments(resolvedSegments);

    final resolvedResult = _PathGeometryLoadResult(
      index: index,
      pathWithMetadata: pathWithAccessMetadata,
      transitGeometry:
          flattenedGeometry.isNotEmpty ? flattenedGeometry : resolvedGeometry,
      transitGeometrySegments: resolvedSegments,
      walkingGeometrySegments: walkingGeometrySegments,
      accessPoints: transitResult.stationAccessPoints,
    );

    _cachePathGeometryByKey(geometryCacheKey, resolvedResult);
    return resolvedResult;
  }

  void _syncSelectedPathGeometryCache() {
    final selectedIndex = _selectedPathIndex;
    if (selectedIndex == null) {
      _selectedTransitAccessPoints = const [];
      return;
    }

    _selectedTransitAccessPoints = _safeTransitAccessFromCache(selectedIndex) ??
        const <TransitStationAccessPoint>[];
  }

  Future<void> _loadRouteGeometryForPathIndex(int pathIndex) async {
    final currentPaths = _paths;
    if (currentPaths == null ||
        pathIndex < 0 ||
        pathIndex >= currentPaths.length) {
      return;
    }

    final requestId = ++_routeGeometryRequestId;
    setState(() {
      _isLoadingGeometry = true;
    });

    final osrmStatsBefore = _snapshotOsrmRequestStats();

    try {
      final result = await _resolvePathGeometry(
        index: pathIndex,
        path: currentPaths[pathIndex],
        includeWalkingGeometry: true,
      );

      if (!mounted || requestId != _routeGeometryRequestId) {
        return;
      }

      final latestPaths = _paths;
      if (latestPaths == null || result.index >= latestPaths.length) {
        setState(() {
          _isLoadingGeometry = false;
        });
        return;
      }

      final updatedPaths = List<PathResult>.from(latestPaths);
      updatedPaths[result.index] = result.pathWithMetadata;

      setState(() {
        _paths = updatedPaths;
        _safeCacheRouteGeometry(result.index, result.transitGeometry);
        _safeCacheRouteGeometrySegments(
          result.index,
          result.transitGeometrySegments,
        );
        _safeCacheWalkingGeometrySegments(
          result.index,
          result.walkingGeometrySegments,
        );
        _safeCacheTransitAccess(result.index, result.accessPoints);
        _syncSelectedPathGeometryCache();
        _isLoadingGeometry = false;
      });

      if (_selectedPathIndex == result.index) {
        _fitMapToPath(
          result.pathWithMetadata,
          preferredPoints: result.transitGeometry,
        );
      }
    } catch (_) {
      if (!mounted || requestId != _routeGeometryRequestId) {
        return;
      }

      setState(() {
        _isLoadingGeometry = false;
      });
    } finally {
      final osrmStatsAfter = _snapshotOsrmRequestStats();
      _logOsrmRequestStatsDelta(
        'Path geometry index=$pathIndex',
        osrmStatsBefore,
        osrmStatsAfter,
      );
    }
  }

  Future<void> _loadRouteGeometryForAllPaths() async {
    final currentPaths = _paths;
    if (currentPaths == null || currentPaths.isEmpty) {
      return;
    }

    final requestId = ++_routeGeometryRequestId;
    setState(() {
      _isLoadingGeometry = true;
    });

    final osrmStatsBefore = _snapshotOsrmRequestStats();

    try {
      final updatedPaths = List<PathResult>.from(currentPaths);
      final nextGeometryCache = <int, List<LatLng>>{};
      final nextGeometrySegmentsCache = <int, List<List<LatLng>>>{};
      final nextWalkingGeometrySegmentsCache = <int, List<List<LatLng>>>{};
      final nextAccessCache = <int, List<TransitStationAccessPoint>>{};
      final selectedIndex = (_selectedPathIndex != null &&
              _selectedPathIndex! >= 0 &&
              _selectedPathIndex! < currentPaths.length)
          ? _selectedPathIndex!
          : 0;

      final selectedPath = updatedPaths[selectedIndex];
      _PathGeometryLoadResult result;
      try {
        result = await _resolvePathGeometry(
          index: selectedIndex,
          path: selectedPath,
          includeWalkingGeometry: true,
        );
      } catch (_) {
        final fallbackGeometry = _buildTransitDrivingWaypoints(selectedPath);
        result = _PathGeometryLoadResult(
          index: selectedIndex,
          pathWithMetadata: selectedPath,
          transitGeometry: fallbackGeometry,
          transitGeometrySegments: fallbackGeometry.length >= 2
              ? <List<LatLng>>[fallbackGeometry]
              : const <List<LatLng>>[],
          walkingGeometrySegments: const <List<LatLng>>[],
          accessPoints: const [],
        );
      }

      if (result.index < updatedPaths.length) {
        updatedPaths[result.index] = result.pathWithMetadata;
      }
      if (result.transitGeometry.length >= 2) {
        nextGeometryCache[result.index] = result.transitGeometry;
      }
      if (result.transitGeometrySegments.isNotEmpty) {
        nextGeometrySegmentsCache[result.index] =
            result.transitGeometrySegments;
      }
      if (result.walkingGeometrySegments.isNotEmpty) {
        nextWalkingGeometrySegmentsCache[result.index] =
            result.walkingGeometrySegments;
      }
      nextAccessCache[result.index] = result.accessPoints;

      if (!mounted || requestId != _routeGeometryRequestId) {
        return;
      }

      setState(() {
        _paths = updatedPaths;
        _safeReplaceGeometryCaches(
          routeGeometry: nextGeometryCache,
          routeGeometrySegments: nextGeometrySegmentsCache,
          walkingGeometrySegments: nextWalkingGeometrySegmentsCache,
          transitAccess: nextAccessCache,
        );
        _syncSelectedPathGeometryCache();
        _isLoadingGeometry = false;
      });

      final selectedPathAfterSync = _selectedPath();
      if (selectedPathAfterSync != null) {
        _fitMapToPath(
          selectedPathAfterSync,
          preferredPoints: _safeRouteGeometryFromCache(selectedIndex),
        );
      }
    } finally {
      final osrmStatsAfter = _snapshotOsrmRequestStats();
      _logOsrmRequestStatsDelta(
        'Path geometry selected-path preload',
        osrmStatsBefore,
        osrmStatsAfter,
      );
    }
  }

  PathCoordinates _toPathCoordinates(LatLng point) {
    return PathCoordinates(
      latitude: point.latitude,
      longitude: point.longitude,
    );
  }

  List<PathStationInfo> _applyAccessMetadataToStations(
    List<PathStationInfo> stations,
    List<TransitStationAccessPoint> stationAccessPoints,
  ) {
    if (stations.isEmpty) {
      return const [];
    }

    return List<PathStationInfo>.generate(stations.length, (index) {
      final station = stations[index];
      if (index >= stationAccessPoints.length) {
        return station;
      }

      final access = stationAccessPoints[index];
      final hasOffset = access.walkDistanceToAccessPointKm > 0;
      final hasSnappedPoint = access.snappedRoadCoordinate != null;

      return station.copyWith(
        accessPoint:
            hasOffset ? _toPathCoordinates(access.busAccessCoordinate) : null,
        snappedPoint: hasSnappedPoint
            ? _toPathCoordinates(access.snappedRoadCoordinate!)
            : null,
        isInAlley: access.isInAlley,
        walkDistanceToAccessPointKm:
            hasOffset ? access.walkDistanceToAccessPointKm : null,
        walkTimeToAccessPointMinutes:
            hasOffset ? access.walkTimeToAccessPointMinutes : null,
        clearAccessPoint: !hasOffset,
        clearSnappedPoint: !hasSnappedPoint,
        clearWalkDistanceToAccessPointKm: !hasOffset,
        clearWalkTimeToAccessPointMinutes: !hasOffset,
      );
    });
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
      _selectedTransitAccessPoints = const [];
      _safeClearGeometryCaches();
      _routeGeometryRequestId++;
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
      _isMapUiCollapsed = false;
      _isSpeakingRouteGuide = false;
      _selectedTransitAccessPoints = const [];
      _safeClearGeometryCaches();
      _routeGeometryRequestId++;
      _fromAddressController.clear();
      _toAddressController.clear();
      _fromAddressResults.clear();
      _toAddressResults.clear();
    });
  }

  void _openSelectedPathDetail() {
    final paths = _paths;
    final selectedIndex = _selectedPathIndex;
    if (paths == null ||
        selectedIndex == null ||
        selectedIndex >= paths.length) {
      _showError('Vui lòng chọn một lộ trình trước khi xem chi tiết');
      return;
    }

    if (_isSpeakingRouteGuide) {
      TextToSpeechService.instance.stop();
    }

    setState(() {
      _showFullRouteDetail = true;
      _isSpeakingRouteGuide = false;
      _isMapUiCollapsed = false;
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
                    _selectedTransitAccessPoints = const [];
                    _safeClearGeometryCaches();
                    _routeGeometryRequestId++;
                  });
                  _showInfo('Tìm thấy $pathsCount lộ trình');
                  // Load actual route geometry for all paths
                  if (pathsCount > 0) {
                    _fitMapToPath(state.paths[0]);
                    _loadRouteGeometryForAllPaths();
                  }
                } else if (state is PathFindingError) {
                  if (_isSpeakingRouteGuide) {
                    TextToSpeechService.instance.stop();
                  }
                  setState(() {
                    _isLoading = false;
                    _showResults = false;
                    _paths = null;
                    _selectedPathIndex = null;
                    _selectedTransitAccessPoints = const [];
                    _safeClearGeometryCaches();
                    _routeGeometryRequestId++;
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
              if (!_showFullRouteDetail && !_isMapUiCollapsed) _buildTopPanel(),
              if (_inputMode == InputMode.address &&
                  !_showFullRouteDetail &&
                  !_isMapUiCollapsed)
                _buildAddressInputPanel(),
              if (_showResults &&
                  _paths != null &&
                  !_showFullRouteDetail &&
                  !_isMapUiCollapsed)
                _buildResultsPanel(_paths!),
              if (_showFullRouteDetail &&
                  _paths != null &&
                  _selectedPathIndex != null)
                _buildFullRouteDetailView(_paths![_selectedPathIndex!]),
              if (!_showFullRouteDetail) _buildMapUiToggleButton(),
              if (_isLoading) _buildLoadingOverlay(),
            ],
          ),
        ),
        floatingActionButton:
            (_showFullRouteDetail || _isMapUiCollapsed) ? null : _buildFAB(),
      ),
    );
  }

  Widget _buildMap() {
    final scheme = Theme.of(context).colorScheme;
    final hasRouteResults = _paths != null && _paths!.isNotEmpty;
    final selectedPath = _selectedPath();
    final selectedPathColor = _pathColor(_selectedPathIndex ?? 0);
    final stationMarkers = _buildStationMarkers();
    final routeStationMarkers = _buildSelectedPathMarkers(
      selectedPath,
      color: selectedPathColor,
    );
    final overlayMarkers =
        hasRouteResults ? <Marker>[] : _buildOverlayMarkers();

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
        if (hasRouteResults)
          PolylineLayer(
            polylines: _buildRoutePolylines(),
          ),
        // Show loading indicator for route geometry
        if (_isLoadingGeometry)
          Positioned(
            bottom: (_showResults && !_isMapUiCollapsed) ? 260 : 100,
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
        if (_inputMode == InputMode.busStop &&
            !hasRouteResults &&
            stationMarkers.isNotEmpty)
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
        if (routeStationMarkers.isNotEmpty)
          MarkerLayer(
            markers: routeStationMarkers,
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
            value: _selectedCriteria,
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
    final hasValidSelection =
        _selectedPathIndex != null && _selectedPathIndex! < paths.length;

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
            if (hasValidSelection)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openSelectedPathDetail,
                    icon: const Icon(Icons.article_outlined),
                    label: Text(
                      'Xem chi tiết lộ trình ${_selectedPathIndex! + 1}',
                    ),
                  ),
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
    final routeColor = _pathColor(index);
    final stationAccessWalkingLegs = path.stationAccessWalkingLegs;
    final stationAccessDistanceKm = stationAccessWalkingLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.distanceKm,
    );
    final stationAccessTimeMinutes = stationAccessWalkingLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.estimatedTimeMinutes,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: isSelected ? 4 : 1,
      color: isSelected ? routeColor.withValues(alpha: 0.15) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? routeColor : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isSpeakingRouteGuide) {
            TextToSpeechService.instance.stop();
          }
          setState(() {
            _selectedPathIndex = index;
            _isSpeakingRouteGuide = false;
            _syncSelectedPathGeometryCache();
          });

          final cachedGeometry = _safeRouteGeometryFromCache(index);
          final cachedWalkingGeometry =
              _safeWalkingGeometrySegmentsFromCache(index);
          _fitMapToPath(path, preferredPoints: cachedGeometry);

          // Fetch geometry on demand if this path is not cached yet.
          if (!_isLoadingGeometry &&
              ((cachedGeometry == null || cachedGeometry.length < 2) ||
                  cachedWalkingGeometry == null ||
                  cachedWalkingGeometry.isEmpty)) {
            _loadRouteGeometryForPathIndex(index);
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
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: routeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Lộ trình ${index + 1}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: routeColor,
                    ),
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
              if (path.hasWalkingLegs) ...[
                const SizedBox(height: 4),
                Text(
                  'Đi bộ ${path.formattedWalkingDistance} (${path.formattedWalkingTime})',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
              if (stationAccessWalkingLegs.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Vào trạm từ đường chính: ${stationAccessDistanceKm.toStringAsFixed(2)} km (${stationAccessTimeMinutes.toStringAsFixed(0)} phút)',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapUiToggleButton() {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 12,
      right: 16,
      child: Material(
        color: scheme.surface,
        elevation: 3,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip:
              _isMapUiCollapsed ? 'Hiện bảng điều khiển' : 'Ẩn bảng điều khiển',
          onPressed: () {
            setState(() {
              _isMapUiCollapsed = !_isMapUiCollapsed;
            });
          },
          icon: Icon(
            _isMapUiCollapsed ? Icons.visibility : Icons.visibility_off,
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
    final stationAccessLegs = path.stationAccessWalkingLegs;
    final stationAccessDistanceKm = stationAccessLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.distanceKm,
    );
    final stationAccessTimeMinutes = stationAccessLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.estimatedTimeMinutes,
    );

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
                        if (stationAccessLegs.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Đi bộ vào trạm: ${stationAccessDistanceKm.toStringAsFixed(2)} km (${stationAccessTimeMinutes.toStringAsFixed(0)} phút)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
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
                    final firstStationName = path.stations.isNotEmpty
                        ? path.stations.first.stationName
                        : (_fromStation?.stationName ?? 'Điểm xuất phát');
                    final toFirstStationWalkingLeg =
                        _findWalkingLegByType(path, 'to_first_station');

                    return Column(
                      children: [
                        _buildRouteStepCard(
                          icon: Icons.my_location,
                          iconColor: Colors.green,
                          title: 'Điểm xuất phát',
                          subtitle: firstStationName,
                          isFirst: true,
                        ),
                        if (toFirstStationWalkingLeg != null &&
                            toFirstStationWalkingLeg.distanceKm > 0)
                          _buildWalkingLegStepCard(toFirstStationWalkingLeg),
                      ],
                    );
                  }

                  final segmentIndex = index - 1;
                  final segment = path.segments[segmentIndex];
                  final isLast = segmentIndex == path.segments.length - 1;

                  // Kiểm tra xem có chuyển tuyến không
                  final isTransfer = segmentIndex > 0 &&
                      path.segments[segmentIndex - 1].routeCode !=
                          segment.routeCode;
                  final transferWalkingLeg = isTransfer
                      ? _findTransferWalkingLeg(
                          path,
                          path.segments[segmentIndex - 1],
                          segment,
                        )
                      : null;
                  final lastWalkingLeg = isLast
                      ? _findWalkingLegByType(path, 'from_last_station')
                      : null;
                  final hasLastWalkingLeg =
                      lastWalkingLeg != null && lastWalkingLeg.distanceKm > 0;

                  return Column(
                    children: [
                      if (isTransfer)
                        _buildTransferIndicator(
                          path.segments[segmentIndex - 1].routeCode,
                          segment.routeCode,
                        ),
                      if (transferWalkingLeg != null &&
                          transferWalkingLeg.distanceKm > 0)
                        _buildWalkingLegStepCard(transferWalkingLeg),
                      _buildRouteStepCard(
                        icon: Icons.directions_bus,
                        iconColor: Colors.blue,
                        title:
                            'Tuyến ${segment.routeCode}: ${segment.routeName}',
                        subtitle:
                            '${segment.from} → ${segment.to}\n${(segment.distance).toStringAsFixed(1)} km • ${(segment.time).toStringAsFixed(0)} phút',
                        routeCode: segment.routeCode,
                        isLast: isLast && !hasLastWalkingLeg,
                      ),
                      if (hasLastWalkingLeg)
                        _buildWalkingLegStepCard(lastWalkingLeg),
                      if (isLast)
                        _buildRouteStepCard(
                          icon: Icons.location_on,
                          iconColor: Colors.red,
                          title: 'Điểm đến',
                          subtitle: path.stations.isNotEmpty
                              ? path.stations.last.stationName
                              : (_toStation?.stationName ?? 'Điểm đến'),
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

  WalkingLeg? _findWalkingLegByType(PathResult path, String type) {
    final normalizedType = type.trim().toLowerCase();
    for (final leg in path.walkingLegs) {
      if (leg.normalizedType == normalizedType) {
        return leg;
      }
    }
    return null;
  }

  WalkingLeg? _findTransferWalkingLeg(
    PathResult path,
    PathSegment previous,
    PathSegment next,
  ) {
    for (final leg in path.walkingLegs) {
      if (!leg.isTransfer) {
        continue;
      }

      final fromCode = (leg.fromStationCode ?? '').trim();
      final toCode = leg.stationCode.trim();
      final previousTo = previous.to.trim();
      final nextFrom = next.from.trim();

      if (fromCode.isNotEmpty &&
          toCode.isNotEmpty &&
          previousTo == fromCode &&
          nextFrom == toCode) {
        return leg;
      }
    }

    return null;
  }

  Widget _buildWalkingLegStepCard(WalkingLeg leg) {
    return _buildRouteStepCard(
      icon: Icons.directions_walk,
      iconColor: Colors.orange,
      title: leg.displayType,
      subtitle: _buildWalkingLegSubtitle(leg),
    );
  }

  String _buildWalkingLegSubtitle(WalkingLeg leg) {
    final distance = '${leg.distanceKm.toStringAsFixed(2)} km';
    final duration = '${leg.estimatedTimeMinutes.toStringAsFixed(0)} phút';

    if (leg.isToFirstStation) {
      return 'Đến trạm ${leg.stationName} • $distance • $duration';
    }

    if (leg.isFromLastStation) {
      return 'Rời trạm ${leg.stationName} đến điểm đến • $distance • $duration';
    }

    if (leg.isTransfer) {
      final fromName =
          leg.fromStationName ?? leg.fromStationCode ?? 'trạm trước';
      return '$fromName → ${leg.stationName} • $distance • $duration';
    }

    return '${leg.stationName} • $distance • $duration';
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
