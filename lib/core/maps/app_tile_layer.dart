import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AppTileLayer {
  static const String urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'com.smartgo.app';
  static const String userAgent =
      'SmartGoApp/1.0.0 (contact: tcongdang04@gmail.com)';

  // Vietnam boundary constants to prevent dragging/panning to outer sea areas
  static final LatLngBounds vietnamBounds = LatLngBounds(
    const LatLng(8.0, 102.0),  // Southwest (covers Ca Mau & Phu Quoc)
    const LatLng(23.5, 110.0), // Northeast (covers Ha Giang & Mong Cai)
  );

  static final CameraConstraint vietnamCameraConstraint =
      CameraConstraint.containCenter(
    bounds: vietnamBounds,
  );

  static const double minZoom = 10.0;
  static const double maxZoom = 19.0;

  static NetworkTileProvider _buildTileProvider() {
    // On web, setting User-Agent is forbidden and can trigger CORS failures.
    final headers = <String, String>{};
    if (!kIsWeb) {
      headers['User-Agent'] = userAgent;
    }
    return NetworkTileProvider(headers: headers.isEmpty ? null : headers);
  }

  static TileLayer standard() {
    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: userAgentPackageName,
      tileProvider: _buildTileProvider(),
      keepBuffer: 4,
    );
  }
}
