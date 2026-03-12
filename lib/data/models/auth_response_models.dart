import 'user_model.dart';

class RegisterRequest {
  final String email;
  final String name;
  final String password;

  const RegisterRequest({
    required this.email,
    required this.name,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'name': name,
      'password': password,
    };
  }
}

class RegisterResponse {
  final String accessToken;
  final String? refreshToken;
  final UserModel? user;

  const RegisterResponse({
    required this.accessToken,
    this.refreshToken,
    this.user,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) {
    // Handle both nested and flat response structures
    final data = json['data'] as Map<String, dynamic>? ?? json;

    return RegisterResponse(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String?,
      user: data['user'] != null
          ? UserModel.fromJson(data['user'] as Map<String, dynamic>)
          : null,
    );
  }
}

class RefreshTokenRequest {
  final String accessToken;

  const RefreshTokenRequest({
    required this.accessToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
    };
  }
}

class RefreshTokenResponse {
  final String accessToken;
  final String? refreshToken;

  const RefreshTokenResponse({
    required this.accessToken,
    this.refreshToken,
  });

  factory RefreshTokenResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;

    return RefreshTokenResponse(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String?,
    );
  }
}

class GetMeResponse {
  final UserModel user;

  const GetMeResponse({
    required this.user,
  });

  factory GetMeResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;

    return GetMeResponse(
      user: UserModel.fromJson(data),
    );
  }
}
