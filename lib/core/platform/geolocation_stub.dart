import 'package:geolocator/geolocator.dart';

class GeoPosition {
  final double latitude;
  final double longitude;

  const GeoPosition(this.latitude, this.longitude);
}

Future<GeoPosition?> getCurrentGeoPosition({
  bool enableHighAccuracy = true,
  Duration? timeout,
}) async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: enableHighAccuracy ? LocationAccuracy.high : LocationAccuracy.low,
      timeLimit: timeout,
    );
    return GeoPosition(position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
}

