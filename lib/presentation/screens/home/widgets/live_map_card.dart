import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/maps/app_tile_layer.dart';
import '../../../../domain/entities/station.dart';
import '../../../widgets/map/map_icons.dart';

class LiveMapCard extends StatelessWidget {
  final List<Station> stations;

  const LiveMapCard({
    super.key,
    required this.stations,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const maxPreviewStations = 40;
    final previewStations = stations.length > maxPreviewStations
        ? stations.take(maxPreviewStations).toList()
        : stations;
    final center = _resolveCenter(previewStations);
    final visibleLabel = previewStations.length == stations.length
        ? '${previewStations.length} trạm hiển thị'
        : '${previewStations.length}/${stations.length} trạm hiển thị';

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
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12.5,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.doubleTapZoom,
                  ),
                ),
                children: [
                  AppTileLayer.standard(),
                  MarkerLayer(
                    markers: previewStations
                        .map(
                          (station) => Marker(
                            point: LatLng(station.latitude, station.longitude),
                            width: 30,
                            height: 30,
                            child: _MapDot(
                              icon: _stationIcon(station.stationType),
                              color: _stationColor(
                                  station.stationType, scheme.primary),
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
                    child: Text(
                      visibleLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

  LatLng _resolveCenter(List<Station> previewStations) {
    if (previewStations.isEmpty) {
      return const LatLng(10.8231, 106.6297);
    }

    var latSum = 0.0;
    var lonSum = 0.0;
    for (final station in previewStations) {
      latSum += station.latitude;
      lonSum += station.longitude;
    }

    return LatLng(
      latSum / previewStations.length,
      lonSum / previewStations.length,
    );
  }

  IconData _stationIcon(StationType type) {
    return MapIcons.stationType(type);
  }

  Color _stationColor(StationType type, Color primary) {
    switch (type) {
      case StationType.METRO_STATION:
        return const Color(0xFF334155);
      case StationType.FERRY_TERMINAL:
        return const Color(0xFF0F766E);
      default:
        return primary;
    }
  }
}

class _MapDot extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MapDot({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }
}
