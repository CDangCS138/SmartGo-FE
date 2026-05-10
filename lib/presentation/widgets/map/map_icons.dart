import 'package:flutter/material.dart';

import '../../../domain/entities/station.dart';

class MapIcons {
  MapIcons._();

  static const IconData search = Icons.search_rounded;
  static const IconData route = Icons.route_rounded;
  static const IconData bus = Icons.directions_bus_rounded;
  static const IconData location = Icons.location_on_rounded;
  static const IconData myLocation = Icons.my_location_rounded;
  static const IconData nearby = Icons.near_me_rounded;
  static const IconData zoomIn = Icons.add_rounded;
  static const IconData zoomOut = Icons.remove_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData settings = Icons.settings_outlined;
  static const IconData mapMode = Icons.map_rounded;
  static const IconData addressMode = Icons.search_rounded;
  static const IconData busStopMode = Icons.directions_bus_rounded;
  static const IconData transfer = Icons.transfer_within_a_station_rounded;

  static IconData stationType(StationType type) {
    switch (type) {
      case StationType.METRO_STATION:
        return Icons.train_rounded;
      case StationType.FERRY_TERMINAL:
        return Icons.directions_boat_rounded;
      default:
        return bus;
    }
  }
}
