import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

class AppTileLayer {
  static const String urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'com.smartgo.app';
  static const String userAgent =
      'SmartGoApp/1.0.0 (contact: tcongdang04@gmail.com)';

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
