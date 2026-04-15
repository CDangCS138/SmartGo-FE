import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/users_models.dart';

class UsersRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  UsersRemoteDataSource({
    required this.client,
    this.baseUrl = 'http://20.6.128.105:8000',
  });

  Map<String, String> _authHeaders(String accessToken) {
    return {
      'Authorization': 'Bearer $accessToken',
    };
  }

  Future<UsersPageResponse> getUsers({
    required String accessToken,
    int page = 1,
    int limit = 10,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/users').replace(
      queryParameters: {
        'page': '$page',
        'limit': '$limit',
      },
    );

    final response = await client.get(uri, headers: _authHeaders(accessToken));
    if (response.statusCode != 200) {
      throw Exception('Lấy danh sách users thất bại: ${response.statusCode}');
    }

    final jsonBody = json.decode(response.body) as Map<String, dynamic>;
    return UsersPageResponse.fromJson(jsonBody);
  }

  Future<AdminUserModel> getUserById({
    required String accessToken,
    required String id,
  }) async {
    final response = await client.get(
      Uri.parse('$baseUrl/api/v1/users/$id'),
      headers: _authHeaders(accessToken),
    );

    if (response.statusCode != 200) {
      throw Exception('Không tìm thấy user: ${response.statusCode}');
    }

    final jsonBody = json.decode(response.body) as Map<String, dynamic>;
    final data = jsonBody['data'] as Map<String, dynamic>? ?? jsonBody;
    return AdminUserModel.fromJson(data);
  }

  Future<AdminUserModel> createUser({
    required String accessToken,
    required String email,
    required String name,
    required String role,
    required XFile avatar,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/users'),
    );

    request.headers.addAll(_authHeaders(accessToken));
    request.fields['email'] = email;
    request.fields['name'] = name;
    request.fields['role'] = role;
    request.files.add(
      await _avatarPart(avatar),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Tạo user thất bại: ${response.statusCode}');
    }

    final jsonBody = json.decode(response.body) as Map<String, dynamic>;
    final data = jsonBody['data'] as Map<String, dynamic>? ?? jsonBody;
    return AdminUserModel.fromJson(data);
  }

  Future<AdminUserModel> updateUser({
    required String accessToken,
    required String id,
    String? email,
    String? name,
    String? role,
    XFile? avatar,
  }) async {
    if (avatar == null) {
      throw Exception('Cập nhật user yêu cầu avatar theo API hiện tại.');
    }

    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/v1/users/$id'),
    );

    request.headers.addAll(_authHeaders(accessToken));
    request.files.add(await _avatarPart(avatar));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception('Cập nhật user thất bại: ${response.statusCode}');
    }

    final jsonBody = json.decode(response.body) as Map<String, dynamic>;
    final data = jsonBody['data'] as Map<String, dynamic>? ?? jsonBody;
    return AdminUserModel.fromJson(data);
  }

  Future<void> deleteUser({
    required String accessToken,
    required String id,
  }) async {
    final response = await client.delete(
      Uri.parse('$baseUrl/api/v1/users/$id'),
      headers: _authHeaders(accessToken),
    );

    if (response.statusCode != 200) {
      throw Exception('Xóa user thất bại: ${response.statusCode}');
    }
  }

  Future<http.MultipartFile> _avatarPart(XFile avatar) async {
    final bytes = await avatar.readAsBytes();
    return http.MultipartFile.fromBytes(
      'avatar',
      Uint8List.fromList(bytes),
      filename: avatar.name,
    );
  }
}
