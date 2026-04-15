import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../../core/constants/app_env.dart';
import '../models/station_model.dart';
import '../../core/errors/exceptions.dart';

abstract class StationRemoteDataSource {
  Future<List<StationModel>> getAllStations({int page = 1, int limit = 5000});

  Future<StationModel> getStationById(String id);
}

@LazySingleton(as: StationRemoteDataSource)
class StationRemoteDataSourceImpl implements StationRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  StationRemoteDataSourceImpl({
    required this.client,
  }) : baseUrl = AppEnv.baseUrl;

  @override
  Future<List<StationModel>> getAllStations({
    int page = 1,
    int limit = 5000,
  }) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/v1/stations?page=$page&limit=$limit'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final stationListResponse = StationListResponse.fromJson(jsonResponse);
        return stationListResponse.data;
      } else {
        throw ServerException(
            'Failed to load stations: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Network error: $e');
    }
  }

  @override
  Future<StationModel> getStationById(String id) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/v1/stations/$id'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final stationResponse = StationResponse.fromJson(jsonResponse);
        return stationResponse.data;
      } else if (response.statusCode == 404) {
        throw const NotFoundException('Station not found');
      } else {
        throw ServerException('Failed to load station: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is NotFoundException) rethrow;
      throw ServerException('Network error: $e');
    }
  }
}
