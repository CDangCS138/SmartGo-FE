import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../models/auth_request_models.dart';
import '../models/auth_response_models.dart';
import '../models/user_model.dart';
import '../../core/errors/exceptions.dart';

abstract class AuthRemoteDataSource {
  Future<LoginResponse> login({
    required String email,
    required String password,
  });

  Future<RegisterResponse> register({
    required String email,
    required String name,
    required String password,
  });

  Future<RefreshTokenResponse> refreshToken({
    required String accessToken,
  });

  Future<LoginResponse> exchangeGoogleAuthCode({
    required String authCode,
    required String state,
  });

  Future<UserModel> getCurrentUser();
}

@LazySingleton(as: AuthRemoteDataSource)
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  AuthRemoteDataSourceImpl({
    required this.client,
  }) : baseUrl = 'http://20.6.128.105:8000';

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final request = LoginRequest(email: email, password: password);
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = json.decode(response.body);
        return LoginResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 401) {
        throw const ValidationException('Email hoặc mật khẩu không đúng');
      } else if (response.statusCode == 400) {
        final jsonResponse = json.decode(response.body);
        final message = jsonResponse['message'] ?? 'Thông tin không hợp lệ';
        throw ValidationException(message);
      } else {
        throw ServerException('Đăng nhập thất bại: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is ValidationException) rethrow;
      throw ServerException('Lỗi kết nối: $e');
    }
  }

  @override
  Future<RegisterResponse> register({
    required String email,
    required String name,
    required String password,
  }) async {
    try {
      final request = RegisterRequest(
        email: email,
        name: name,
        password: password,
      );
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = json.decode(response.body);
        return RegisterResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 409) {
        throw const ValidationException('Email đã được sử dụng');
      } else if (response.statusCode == 400) {
        final jsonResponse = json.decode(response.body);
        final message = jsonResponse['message'] ?? 'Thông tin không hợp lệ';
        throw ValidationException(message);
      } else {
        throw ServerException('Đăng ký thất bại: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is ValidationException) rethrow;
      throw ServerException('Lỗi kết nối: $e');
    }
  }

  @override
  Future<RefreshTokenResponse> refreshToken({
    required String accessToken,
  }) async {
    try {
      final request = RefreshTokenRequest(accessToken: accessToken);
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = json.decode(response.body);
        return RefreshTokenResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 401) {
        throw const ValidationException('Token không hợp lệ');
      } else {
        throw ServerException('Làm mới token thất bại: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is ValidationException) rethrow;
      throw ServerException('Lỗi kết nối: $e');
    }
  }

  @override
  Future<LoginResponse> exchangeGoogleAuthCode({
    required String authCode,
    required String state,
  }) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/api/v1/auth/google/exchange'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'authCode': authCode,
          'state': state,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResponse = json.decode(response.body);
        return LoginResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 400 || response.statusCode == 401) {
        final jsonResponse = json.decode(response.body);
        final message =
            jsonResponse['message'] ?? 'Mã xác thực Google không hợp lệ';
        throw ValidationException(message);
      } else {
        throw ServerException(
          'Đổi mã xác thực Google thất bại: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is ServerException || e is ValidationException) rethrow;
      throw ServerException('Lỗi kết nối: $e');
    }
  }

  @override
  Future<UserModel> getCurrentUser() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final meResponse = GetMeResponse.fromJson(jsonResponse);
        return meResponse.user;
      } else if (response.statusCode == 401) {
        throw const ValidationException('Token không hợp lệ');
      } else {
        throw ServerException(
            'Lấy thông tin người dùng thất bại: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ServerException || e is ValidationException) rethrow;
      throw ServerException('Lỗi kết nối: $e');
    }
  }
}
