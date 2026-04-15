import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_env.dart';
import '../../core/errors/exceptions.dart';
import '../models/bus_simulation_models.dart';

class BusSimulationRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  BusSimulationRemoteDataSource({
    required this.client,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? AppEnv.baseUrl;

  Future<List<BusSimulationTrip>> getRouteTrips({
    required String routeId,
    String? accessToken,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/bus-simulations/routes/$routeId/trips',
    );

    final decoded = await _getJson(uri, accessToken: accessToken);
    final rows = _extractList(decoded);

    return rows
        .whereType<Map<String, dynamic>>()
        .map(BusSimulationTrip.fromJson)
        .toList();
  }

  Future<List<BusSimulationPosition>> getRoutePositions({
    required String routeId,
    String? accessToken,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/bus-simulations/routes/$routeId/positions',
    );

    final decoded = await _getJson(uri, accessToken: accessToken);
    return _decodePositionList(decoded);
  }

  Future<BusSimulationPosition> getTripPosition({
    required String tripId,
    String? accessToken,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/bus-simulations/trips/$tripId/position',
    );

    final decoded = await _getJson(uri, accessToken: accessToken);
    final map = _extractMap(decoded);
    return BusSimulationPosition.fromJson(map);
  }

  Future<List<UpcomingBusAtStation>> getStationEta({
    required String stationId,
    String? accessToken,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/bus-simulations/stations/$stationId/eta',
    );

    final decoded = await _getJson(uri, accessToken: accessToken);
    return _decodeStationEtaList(decoded);
  }

  List<BusSimulationPosition> parseRoutePositionsEvent(String rawPayload) {
    final decoded = json.decode(rawPayload);
    return _decodePositionList(decoded);
  }

  BusSimulationPosition parseTripPositionEvent(String rawPayload) {
    final decoded = json.decode(rawPayload);
    final map = _extractMap(decoded);
    return BusSimulationPosition.fromJson(map);
  }

  List<UpcomingBusAtStation> parseStationEtaEvent(String rawPayload) {
    final decoded = json.decode(rawPayload);
    return _decodeStationEtaList(decoded);
  }

  Uri routePositionsStreamUri({
    required String routeId,
    required String token,
  }) {
    return Uri.parse(
      '$baseUrl/api/v1/bus-simulations/routes/$routeId/stream',
    ).replace(
      queryParameters: {'token': token},
    );
  }

  Uri tripPositionStreamUri({
    required String tripId,
    required String token,
  }) {
    return Uri.parse(
      '$baseUrl/api/v1/bus-simulations/trips/$tripId/stream',
    ).replace(
      queryParameters: {'token': token},
    );
  }

  Uri stationEtaStreamUri({
    required String stationId,
    required String token,
  }) {
    return Uri.parse(
      '$baseUrl/api/v1/bus-simulations/stations/$stationId/eta/stream',
    ).replace(
      queryParameters: {'token': token},
    );
  }

  Future<dynamic> _getJson(
    Uri uri, {
    String? accessToken,
  }) async {
    http.Response response;

    try {
      response = await client.get(
        uri,
        headers: _buildHeaders(accessToken),
      );
    } catch (error) {
      throw NetworkException('Khong ket noi duoc Bus Simulations API: $error');
    }

    final decoded = _safeDecodeResponse(response);

    if (response.statusCode == 200) {
      return decoded;
    }

    final message = _readErrorMessage(decoded, response);

    if (response.statusCode == 400) {
      throw BadRequestException(message);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw UnauthorizedException(message);
    }

    if (response.statusCode == 404) {
      throw NotFoundException(message);
    }

    throw ServerException(message);
  }

  Map<String, String> _buildHeaders(String? accessToken) {
    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (accessToken != null && accessToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${accessToken.trim()}';
    }

    return headers;
  }

  dynamic _safeDecodeResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes).trim();
    if (body.isEmpty) {
      return null;
    }

    try {
      return json.decode(body);
    } catch (_) {
      return body;
    }
  }

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) {
        return data;
      }

      if (data is Map<String, dynamic>) {
        for (final key in const [
          'items',
          'trips',
          'positions',
          'etas',
          'results',
        ]) {
          final value = data[key];
          if (value is List) {
            return value;
          }
        }
      }

      for (final key in const [
        'items',
        'trips',
        'positions',
        'etas',
        'results'
      ]) {
        final value = decoded[key];
        if (value is List) {
          return value;
        }
      }
    }

    return const <dynamic>[];
  }

  Map<String, dynamic> _extractMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return decoded;
    }

    throw const ServerException('Du lieu phan hoi khong dung dinh dang object');
  }

  List<BusSimulationPosition> _decodePositionList(dynamic decoded) {
    return _extractList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(BusSimulationPosition.fromJson)
        .toList();
  }

  List<UpcomingBusAtStation> _decodeStationEtaList(dynamic decoded) {
    return _extractList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(UpcomingBusAtStation.fromJson)
        .toList();
  }

  String _readErrorMessage(dynamic decoded, http.Response response) {
    if (decoded is Map<String, dynamic>) {
      final candidates = [
        decoded['message'],
        decoded['error'],
        decoded['detail'],
      ];
      for (final candidate in candidates) {
        final text = candidate?.toString().trim();
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    }

    final raw = utf8.decode(response.bodyBytes).trim();
    if (raw.isNotEmpty) {
      return raw;
    }

    return 'Bus Simulations API loi (${response.statusCode})';
  }
}
