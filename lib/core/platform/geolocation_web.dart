// This file is only compiled on Flutter web via conditional export.
// We keep `dart:html` here to access browser geolocation API.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'geolocation_stub.dart';

Future<GeoPosition?> getCurrentGeoPosition({
  bool enableHighAccuracy = true,
  Duration? timeout,
}) async {
  try {
    final position = await html.window.navigator.geolocation.getCurrentPosition(
      enableHighAccuracy: enableHighAccuracy,
      timeout: timeout,
    );

    final lat = position.coords?.latitude?.toDouble();
    final lon = position.coords?.longitude?.toDouble();

    if (lat == null || lon == null) return null;
    return GeoPosition(lat, lon);
  } catch (_) {
    return null;
  }
}
