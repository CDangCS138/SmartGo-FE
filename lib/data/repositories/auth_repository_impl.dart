import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/exceptions.dart';
import '../../core/errors/failures.dart';
import '../../core/services/storage_service.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/user_model.dart';
import 'dart:convert';

@LazySingleton(as: AuthRepository)
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final StorageService storageService;
  UserModel? _cachedUser;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.storageService,
  }) {
    _loadCachedUser();
  }

  void _loadCachedUser() {
    final userData = storageService.getUserData();
    if (userData != null) {
      try {
        _cachedUser = UserModel.fromJson(json.decode(userData));
      } catch (e) {
        _cachedUser = null;
      }
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await remoteDataSource.login(
        email: email,
        password: password,
      );

      // Save token
      await storageService.saveAuthToken(response.accessToken);
      if (response.refreshToken != null) {
        await storageService.saveRefreshToken(response.refreshToken!);
      }

      // Fetch and save user data
      try {
        final user = await remoteDataSource.getCurrentUser();
        _cachedUser = user;
        await storageService.saveUserData(json.encode(user.toJson()));
      } catch (e) {
        // Continue even if fetching user data fails
      }

      return Right(AuthTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      ));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('Lỗi không xác định: $e'));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> register({
    required String email,
    required String name,
    required String password,
  }) async {
    try {
      final response = await remoteDataSource.register(
        email: email,
        name: name,
        password: password,
      );

      // Save token
      await storageService.saveAuthToken(response.accessToken);
      if (response.refreshToken != null) {
        await storageService.saveRefreshToken(response.refreshToken!);
      }

      // Save user data if available
      if (response.user != null) {
        _cachedUser = response.user;
        await storageService.saveUserData(json.encode(response.user!.toJson()));
      } else {
        // Fetch and save user data
        try {
          final user = await remoteDataSource.getCurrentUser();
          _cachedUser = user;
          await storageService.saveUserData(json.encode(user.toJson()));
        } catch (e) {
          // Continue even if fetching user data fails
        }
      }

      return Right(AuthTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      ));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('Lỗi không xác định: $e'));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> refreshToken({
    required String accessToken,
  }) async {
    try {
      final response = await remoteDataSource.refreshToken(
        accessToken: accessToken,
      );

      // Save new token
      await storageService.saveAuthToken(response.accessToken);
      if (response.refreshToken != null) {
        await storageService.saveRefreshToken(response.refreshToken!);
      }

      return Right(AuthTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      ));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('Lỗi không xác định: $e'));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> loginWithGoogle({
    required String authCode,
    required String state,
  }) async {
    try {
      final response = await remoteDataSource.exchangeGoogleAuthCode(
        authCode: authCode,
        state: state,
      );

      await storageService.saveAuthToken(response.accessToken);
      if (response.refreshToken != null) {
        await storageService.saveRefreshToken(response.refreshToken!);
      }

      try {
        final user = await remoteDataSource.getCurrentUser();
        _cachedUser = user;
        await storageService.saveUserData(json.encode(user.toJson()));
      } catch (e) {
        // Continue even if fetching user data fails
      }

      return Right(AuthTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      ));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('Lỗi không xác định: $e'));
    }
  }

  @override
  Future<Either<Failure, User>> getCurrentUser() async {
    try {
      final token = storageService.getAuthToken();
      if (token == null) {
        return const Left(AuthenticationFailure('Chưa đăng nhập'));
      }

      final user = await remoteDataSource.getCurrentUser();
      _cachedUser = user;
      await storageService.saveUserData(json.encode(user.toJson()));

      return Right(user);
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('Lỗi không xác định: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await storageService.clearAuthToken();
      await storageService.clearRefreshToken();
      await storageService.clearUserData();
      _cachedUser = null;
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure('Lỗi khi đăng xuất: $e'));
    }
  }

  @override
  bool isAuthenticated() {
    return storageService.getAuthToken() != null;
  }

  @override
  User? getCachedUser() {
    return _cachedUser;
  }
}
