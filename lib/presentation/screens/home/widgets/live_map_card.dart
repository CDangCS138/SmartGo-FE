import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/app_env.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/maps/app_tile_layer.dart';
import '../../../../core/platform/sse_client.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/themes/app_colors.dart';

class LiveMapCard extends StatefulWidget {
  const LiveMapCard({super.key});

  @override
  State<LiveMapCard> createState() => _LiveMapCardState();
}

class _LiveMapCardState extends State<LiveMapCard> {
  final MapController _mapController = MapController();
  List<_LiveBusPosition> _buses = [];
  int _totalActiveBuses = 0;

  SseClient? _sseClient;
  StreamSubscription<String>? _sseSubscription;
  bool _isRealtime = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRealtime();
    });
  }

  @override
  void dispose() {
    _stopRealtime(notify: false);
    super.dispose();
  }

  void _stopRealtime({bool notify = true}) {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseClient?.close();
    _sseClient = null;
    _isRealtime = false;
    if (notify && mounted) {
      setState(() {
        _isRealtime = false;
      });
    }
  }

  Future<void> _startRealtime() async {
    final token = getIt<StorageService>().getAuthToken();
    if (token == null || token.trim().isEmpty) return;

    final uri = Uri.parse(
      '${AppEnv.baseUrl}/api/v1/bus-simulations/positions/stream?token=${Uri.encodeComponent(token.trim())}',
    );

    final sseClient = createSseClient();
    _sseClient = sseClient;

    setState(() {
      _isRealtime = true;
    });

    _sseSubscription = sseClient.connect(uri).listen(
      (payload) {
        if (!mounted) return;
        try {
          final data = json.decode(payload);
          if (data is Map<String, dynamic>) {
            final positionsRaw = data['positions'];
            final total = (data['totalActiveBuses'] as num?)?.toInt() ?? 0;
            if (positionsRaw is List) {
              final parsed = positionsRaw
                  .map((e) =>
                      _LiveBusPosition.fromJson(e as Map<String, dynamic>))
                  .toList();
              setState(() {
                _buses = parsed;
                _totalActiveBuses = total;
              });
            }
          } else if (data is List) {
            final parsed = data
                .map(
                    (e) => _LiveBusPosition.fromJson(e as Map<String, dynamic>))
                .toList();
            setState(() {
              _buses = parsed;
              _totalActiveBuses = parsed.length;
            });
          }
        } catch (_) {
          // Ignore malformed JSON
        }
      },
      onError: (_) {
        if (!mounted) return;
        _stopRealtime();
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _startRealtime();
        });
      },
      cancelOnError: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeBuses = _buses
        .where((b) =>
            b.status.toUpperCase() == 'RUNNING' ||
            b.status.toUpperCase() == 'SCHEDULED')
        .toList();
    final center = _resolveCenter(activeBuses);
    final displayCount =
        _totalActiveBuses > 0 ? _totalActiveBuses : activeBuses.length;
    final visibleLabel = '$displayCount xe đang chạy';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E000000),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12.5,
                  minZoom: AppTileLayer.minZoom,
                  maxZoom: AppTileLayer.maxZoom,
                  cameraConstraint: AppTileLayer.vietnamCameraConstraint,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.doubleTapZoom,
                  ),
                ),
                children: [
                  AppTileLayer.standard(),
                  MarkerLayer(
                    markers: activeBuses
                        .map(
                          (bus) => Marker(
                            point: LatLng(bus.latitude, bus.longitude),
                            width: 36,
                            height: 36,
                            child: _MapBusDot(
                              routeCode: bus.routeCode,
                              status: bus.status,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              Positioned(
                top: 10,
                left: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.56),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isRealtime) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.busRunning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          visibleLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LatLng _resolveCenter(List<_LiveBusPosition> buses) {
    if (buses.isEmpty) {
      return const LatLng(10.8231, 106.6297);
    }

    var latSum = 0.0;
    var lonSum = 0.0;
    for (final bus in buses) {
      latSum += bus.latitude;
      lonSum += bus.longitude;
    }

    return LatLng(
      latSum / buses.length,
      lonSum / buses.length,
    );
  }
}

class _LiveBusPosition {
  final String routeCode;
  final double latitude;
  final double longitude;
  final String status;

  _LiveBusPosition({
    required this.routeCode,
    required this.latitude,
    required this.longitude,
    required this.status,
  });

  factory _LiveBusPosition.fromJson(Map<String, dynamic> json) {
    return _LiveBusPosition(
      routeCode: json['routeCode']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      status: json['status']?.toString() ?? 'UNKNOWN',
    );
  }
}

class _MapBusDot extends StatelessWidget {
  final String routeCode;
  final String status;

  const _MapBusDot({
    required this.routeCode,
    required this.status,
  });

  Color _getStatusColor() {
    final s = status.toUpperCase();
    if (s == 'RUNNING') {
      return AppColors.busRunning;
    }
    if (s == 'SCHEDULED') {
      return AppColors.busScheduled;
    }
    if (s == 'COMPLETED') {
      return AppColors.busCompleted;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        routeCode,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
