class GeoPosition {
  final double latitude;
  final double longitude;

  const GeoPosition(this.latitude, this.longitude);
}

Future<GeoPosition?> getCurrentGeoPosition({
  bool enableHighAccuracy = true,
  Duration? timeout,
}) async {
  return null;
}
