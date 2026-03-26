import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/errors/exceptions.dart';
import '../models/payment_request_models.dart';
import '../models/payment_response_models.dart';

abstract class PaymentRemoteDataSource {
  Future<VnpayCreatePaymentResponse> createVnpayPayment(
    VnpayCreatePaymentRequest request,
    String? accessToken,
  );

  Future<VnpayCreatePaymentResponse> createMomoPayment(
    VnpayCreatePaymentRequest request,
    String? accessToken,
  );

  Future<VnpayReturnResponse> getVnpayReturnResult(String? accessToken);

  Future<VnpayReturnResponse> getMomoReturnResult(String? accessToken);

  Future<VnpayIpnResponse> handleVnpayIpn(String? accessToken);

  Future<MomoIpnResponse> handleMomoIpn(String? accessToken);
}

@LazySingleton(as: PaymentRemoteDataSource)
class PaymentRemoteDataSourceImpl implements PaymentRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  PaymentRemoteDataSourceImpl({
    required this.client,
  }) : baseUrl = 'https://smart-go.onrender.com';

  Map<String, String> _buildHeaders(String? accessToken) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    return headers;
  }

  @override
  Future<VnpayCreatePaymentResponse> createVnpayPayment(
    VnpayCreatePaymentRequest request,
    String? accessToken,
  ) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/payments/vnpay/create'),
        headers: _buildHeaders(accessToken),
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return VnpayCreatePaymentResponse.fromJson(jsonData);
      } else if (response.statusCode == 400) {
        throw const BadRequestException('Invalid payment request');
      } else if (response.statusCode == 401) {
        throw const UnauthorizedException('Unauthorized payment request');
      } else {
        throw ServerException(
            'Failed to create payment: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException ||
          e is BadRequestException ||
          e is UnauthorizedException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  @override
  Future<VnpayCreatePaymentResponse> createMomoPayment(
    VnpayCreatePaymentRequest request,
    String? accessToken,
  ) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/payments/momo/create'),
        headers: _buildHeaders(accessToken),
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return VnpayCreatePaymentResponse.fromJson(jsonData);
      } else if (response.statusCode == 400) {
        throw const BadRequestException('Invalid payment request');
      } else if (response.statusCode == 401) {
        throw const UnauthorizedException('Unauthorized payment request');
      } else {
        throw ServerException(
            'Failed to create MoMo payment: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException ||
          e is BadRequestException ||
          e is UnauthorizedException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  @override
  Future<VnpayReturnResponse> getVnpayReturnResult(String? accessToken) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/v1/payments/vnpay/return'),
        headers: _buildHeaders(accessToken),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return VnpayReturnResponse.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw const NotFoundException('Payment result not found');
      } else {
        throw ServerException(
            'Failed to fetch payment result: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is NotFoundException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  @override
  Future<VnpayReturnResponse> getMomoReturnResult(String? accessToken) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/v1/payments/momo/return'),
        headers: _buildHeaders(accessToken),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return VnpayReturnResponse.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw const NotFoundException('Payment result not found');
      } else {
        throw ServerException(
            'Failed to fetch MoMo payment result: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is NotFoundException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  @override
  Future<VnpayIpnResponse> handleVnpayIpn(String? accessToken) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/v1/payments/vnpay/ipn'),
        headers: _buildHeaders(accessToken),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return VnpayIpnResponse.fromJson(jsonData);
      } else {
        throw ServerException('Failed to handle IPN: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }

  @override
  Future<MomoIpnResponse> handleMomoIpn(String? accessToken) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/payments/momo/ipn'),
        headers: _buildHeaders(accessToken),
        body: json.encode({}),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        return MomoIpnResponse.fromJson(jsonData);
      } else {
        throw ServerException(
            'Failed to handle MoMo IPN: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException) {
        rethrow;
      }
      throw NetworkException('Network error occurred: $e');
    }
  }
}
