import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/usecases/login_usecase.dart';
import '../../../domain/usecases/register_usecase.dart';
import '../../../domain/usecases/logout_usecase.dart';
import '../../../domain/usecases/get_current_user_usecase.dart';
import '../../../domain/usecases/refresh_token_usecase.dart';
import 'auth_event.dart';
import 'auth_state.dart';

@lazySingleton
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase loginUseCase;
  final RegisterUseCase registerUseCase;
  final LogoutUseCase logoutUseCase;
  final GetCurrentUserUseCase getCurrentUserUseCase;
  final RefreshTokenUseCase refreshTokenUseCase;
  final AuthRepository authRepository;

  AuthBloc({
    required this.loginUseCase,
    required this.registerUseCase,
    required this.logoutUseCase,
    required this.getCurrentUserUseCase,
    required this.refreshTokenUseCase,
    required this.authRepository,
  }) : super(const AuthInitial()) {
    on<LoginEvent>(_onLogin);
    on<RegisterEvent>(_onRegister);
    on<LogoutEvent>(_onLogout);
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<GetCurrentUserEvent>(_onGetCurrentUser);
    on<RefreshTokenEvent>(_onRefreshToken);
    on<GoogleOAuthExchangeEvent>(_onGoogleOAuthExchange);
  }

  Future<void> _onLogin(
    LoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await loginUseCase(
      email: event.email,
      password: event.password,
    );

    await result.fold(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (tokens) async {
        // Try to get user info
        final userResult = await getCurrentUserUseCase();
        await userResult.fold(
          (failure) async {
            // If getting user fails, still consider authenticated
            final cachedUser = authRepository.getCachedUser();
            if (cachedUser != null) {
              emit(AuthAuthenticated(
                user: cachedUser,
                accessToken: tokens.accessToken,
              ));
            } else {
              emit(const AuthError(
                  message:
                      'Đăng nhập thành công nhưng không thể lấy thông tin người dùng'));
            }
          },
          (user) async {
            emit(AuthAuthenticated(
              user: user,
              accessToken: tokens.accessToken,
            ));
          },
        );
      },
    );
  }

  Future<void> _onRegister(
    RegisterEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await registerUseCase(
      email: event.email,
      name: event.name,
      password: event.password,
    );

    await result.fold(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (tokens) async {
        // Try to get user info
        final userResult = await getCurrentUserUseCase();
        await userResult.fold(
          (failure) async {
            // If getting user fails, still show success
            final cachedUser = authRepository.getCachedUser();
            emit(AuthRegisterSuccess(
              user: cachedUser,
              accessToken: tokens.accessToken,
            ));
          },
          (user) async {
            emit(AuthAuthenticated(
              user: user,
              accessToken: tokens.accessToken,
            ));
          },
        );
      },
    );
  }

  Future<void> _onLogout(
    LogoutEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await logoutUseCase();

    await result.fold(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (_) async {
        emit(const AuthUnauthenticated());
      },
    );
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatusEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (authRepository.isAuthenticated()) {
      final user = authRepository.getCachedUser();
      if (user != null) {
        // Get fresh user data
        final userResult = await getCurrentUserUseCase();
        await userResult.fold(
          (failure) async {
            // Use cached user if API fails
            emit(AuthAuthenticated(
              user: user,
              accessToken: '', // We don't expose the token here
            ));
          },
          (freshUser) async {
            emit(AuthAuthenticated(
              user: freshUser,
              accessToken: '',
            ));
          },
        );
      } else {
        emit(const AuthUnauthenticated());
      }
    } else {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onGetCurrentUser(
    GetCurrentUserEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    final result = await getCurrentUserUseCase();

    await result.fold(
      (failure) async {
        emit(AuthError(message: failure.message));
      },
      (user) async {
        emit(AuthAuthenticated(
          user: user,
          accessToken: '',
        ));
      },
    );
  }

  Future<void> _onRefreshToken(
    RefreshTokenEvent event,
    Emitter<AuthState> emit,
  ) async {
    final result = await refreshTokenUseCase(
      accessToken: event.accessToken,
    );

    await result.fold(
      (failure) async {
        // If refresh fails, logout
        emit(const AuthUnauthenticated());
      },
      (tokens) async {
        // Try to get user info with new token
        final userResult = await getCurrentUserUseCase();
        await userResult.fold(
          (failure) async {
            final cachedUser = authRepository.getCachedUser();
            if (cachedUser != null) {
              emit(AuthAuthenticated(
                user: cachedUser,
                accessToken: tokens.accessToken,
              ));
            } else {
              emit(const AuthUnauthenticated());
            }
          },
          (user) async {
            emit(AuthAuthenticated(
              user: user,
              accessToken: tokens.accessToken,
            ));
          },
        );
      },
    );
  }

  Future<void> _onGoogleOAuthExchange(
    GoogleOAuthExchangeEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final result = await authRepository.loginWithGoogle(
        authCode: event.authCode,
        state: event.state,
      );

      await result.fold(
        (failure) async {
          emit(AuthError(message: failure.message));
        },
        (tokens) async {
          final userResult = await getCurrentUserUseCase();
          await userResult.fold(
            (failure) async {
              final cachedUser = authRepository.getCachedUser();
              if (cachedUser != null) {
                emit(AuthAuthenticated(
                  user: cachedUser,
                  accessToken: tokens.accessToken,
                ));
              } else {
                emit(const AuthError(
                  message:
                      'Đăng nhập Google thành công nhưng không thể lấy thông tin người dùng',
                ));
              }
            },
            (user) async {
              emit(AuthAuthenticated(
                user: user,
                accessToken: tokens.accessToken,
              ));
            },
          );
        },
      );
    } catch (_) {
      emit(const AuthError(
        message: 'Đăng nhập Google gặp lỗi hệ thống. Vui lòng thử lại.',
      ));
    }
  }
}
