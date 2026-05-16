import 'package:flutter_map/flutter_map.dart';

class AppTileLayer {
  static const String urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'com.smartgo.app';
  static const String userAgent =
      'SmartGoApp/1.0.0 (contact: tcongdang04@gmail.com)';

  static final NetworkTileProvider tileProvider = NetworkTileProvider(
    headers: {
      'User-Agent': userAgent,
    },
  );

  static TileLayer standard() {
    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: userAgentPackageName,
      tileProvider: tileProvider,
    );
  }
}
