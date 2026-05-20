import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_env.dart';
import '../../core/errors/exceptions.dart';
import '../models/bill_models.dart';

class BillsRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  BillsRemoteDataSource({
    required this.client,
    String? baseUrl,
  }) : baseUrl = baseUrl ?? AppEnv.baseUrl;

  Future<BillsPageResponse> getBills({
    int page = 1,
    int limit = 20,
    String orderBy = 'createdAt',
    String orderDirection = 'desc',
    String? search,
    String? searchFields,
    String? status,
    String? ticketType,
    String? routeId,
    String? accessToken,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': '$page',
        'limit': '$limit',
        'orderBy': orderBy,
        'orderDirection': orderDirection,
      };

      final normalizedSearch = search?.trim() ?? '';
      if (normalizedSearch.isNotEmpty) {
        queryParams['search'] = normalizedSearch;
      }

      final normalizedFields = searchFields?.trim() ?? '';
      if (normalizedFields.isNotEmpty) {
        queryParams['searchFields'] = normalizedFields;
      }

      final normalizedStatus = status?.trim() ?? '';
      if (normalizedStatus.isNotEmpty) {
        queryParams['status'] = normalizedStatus;
      }

      final normalizedTicketType = ticketType?.trim() ?? '';
      if (normalizedTicketType.isNotEmpty) {
        queryParams['ticketType'] = normalizedTicketType;
      }

      final normalizedRouteId = routeId?.trim() ?? '';
      if (normalizedRouteId.isNotEmpty) {
        queryParams['routeId'] = normalizedRouteId;
      }

      final uri = Uri.parse('$baseUrl/api/v1/bills')
          .replace(queryParameters: queryParams);

      final response = await client.get(
        uri,
        headers: _buildHeaders(accessToken),
      );

      if (response.statusCode == 200) {
        final decoded = _decodeBody(response.body);
        return BillsPageResponse.fromJson(decoded);
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const UnauthorizedException('Chưa được xác thực');
      }

      throw _errorFromResponse(response, 'Lấy danh sách hóa đơn thất bại');
    } catch (e) {
      if (e is ServerException || e is UnauthorizedException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  Future<BillModel> createBill(
    BillCreateRequest request, {
    String? accessToken,
  }) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/bills'),
        headers: _buildHeaders(accessToken),
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = _decodeBody(response.body);
        return BillModel.fromJson(decoded);
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const UnauthorizedException('Chưa được xác thực');
      }

      throw _errorFromResponse(response, 'Tạo hóa đơn thất bại');
    } catch (e) {
      if (e is ServerException || e is UnauthorizedException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  Future<BillModel> updateBillStatus(
    String billId, {
    required String status,
    String? accessToken,
  }) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/api/v1/bills/$billId'),
        headers: _buildHeaders(accessToken),
        body: json.encode({'status': status}),
      );

      if (response.statusCode == 200) {
        final decoded = _decodeBody(response.body);
        return BillModel.fromJson(decoded);
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const UnauthorizedException('Chưa được xác thực');
      }

      throw _errorFromResponse(response, 'Cập nhật hóa đơn thất bại');
    } catch (e) {
      if (e is ServerException || e is UnauthorizedException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  Future<BillModel> getBillById(
    String billId, {
    String? accessToken,
  }) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/v1/bills/$billId'),
        headers: _buildHeaders(accessToken),
      );

      if (response.statusCode == 200) {
        final decoded = _decodeBody(response.body);
        return BillModel.fromJson(decoded);
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const UnauthorizedException('Chưa được xác thực');
      }

      throw _errorFromResponse(response, 'Lấy hóa đơn thất bại');
    } catch (e) {
      if (e is ServerException || e is UnauthorizedException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  Map<String, String> _buildHeaders(String? accessToken) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (accessToken != null && accessToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${accessToken.trim()}';
    }

    return headers;
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final parsed = json.decode(body);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    if (parsed is Map) {
      return Map<String, dynamic>.from(parsed);
    }
    if (parsed is List) {
      return {
        'data': parsed,
      };
    }

    throw const ServerException('Phản hồi không hợp lệ');
  }

  Exception _errorFromResponse(http.Response response, String fallback) {
    final body = response.body;
    if (body.trim().isNotEmpty) {
      try {
        final parsed = json.decode(body);
        if (parsed is Map<String, dynamic>) {
          final message =
              parsed['message']?.toString() ?? parsed['error']?.toString();
          if (message != null && message.isNotEmpty) {
            return ServerException(message);
          }
        }
      } catch (_) {
        // Ignore parse errors and use fallback.
      }
    }

    if (response.statusCode == 404) {
      return const NotFoundException('Không tìm thấy hóa đơn');
    }

    return ServerException('$fallback: ${response.statusCode}');
  }
}
