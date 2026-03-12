import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../entities/auth_tokens.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  /// Login with email and password
  Future<Either<Failure, AuthTokens>> login({
    required String email,
    required String password,
  });

  /// Register a new user
  Future<Either<Failure, AuthTokens>> register({
    required String email,
    required String name,
    required String password,
  });

  /// Refresh access token
  Future<Either<Failure, AuthTokens>> refreshToken({
    required String accessToken,
  });

  /// Get current user information
  Future<Either<Failure, User>> getCurrentUser();

  /// Logout user
  Future<Either<Failure, void>> logout();

  /// Check if user is authenticated
  bool isAuthenticated();

  /// Get cached user data
  User? getCachedUser();
}
