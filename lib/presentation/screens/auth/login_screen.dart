import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import '../../../core/utils/open_external_url.dart';
import '../../../core/routes/app_routes.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/voice_input_icon_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _googleOAuthStateStorageKey = 'google_oauth_state_login';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isEmailInput = true;
  bool _isHandlingOAuthCallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryHandleGoogleOAuthCallbackFromCurrentUrl();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập email hoặc số điện thoại';
    }
    if (_isEmailInput) {
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      if (!emailRegex.hasMatch(value)) {
        return 'Email không hợp lệ';
      }
    } else {
      // Phone validation
      final phoneRegex = RegExp(r'^[0-9]{10}$');
      if (!phoneRegex.hasMatch(value)) {
        return 'Số điện thoại không hợp lệ';
      }
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu';
    }
    if (value.length < 6) {
      return 'Mật khẩu phải có ít nhất 6 ký tự';
    }
    return null;
  }

  void _handleLogin() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
            LoginEvent(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            ),
          );
    }
  }

  String _generateOAuthState() {
    final random = Random.secure().nextInt(9000000) + 1000000;
    return random.toString();
  }

  Future<void> _handleGoogleOAuth() async {
    try {
      final state = _generateOAuthState();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_googleOAuthStateStorageKey, state);
      } catch (_) {
        // Continue OAuth even if local persistence is unavailable on web.
      }

      final authUri = Uri.parse(
        'http://20.6.128.105:8000/api/v1/auth/google?state=$state',
      );

      if (kIsWeb) {
        // In debug, stay in the same tab to inspect OAuth network requests.
        // In production, open a new tab to avoid replacing the app tab.
        const webTarget = kDebugMode ? '_self' : '_blank';
        debugPrint('Google OAuth URL: $authUri (target: $webTarget)');
        await openExternalUrl(authUri, webTarget: webTarget);
        return;
      }

      final opened = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened || !mounted) {
        return;
      }

      final callbackInput = await _showGoogleCallbackInputDialog();
      if (!mounted || callbackInput == null || callbackInput.trim().isEmpty) {
        return;
      }

      final callbackParams = _extractGoogleCallbackParams(callbackInput);
      final authCode = callbackParams?['authCode'];
      final callbackState = callbackParams?['state'];

      if (authCode == null || callbackState == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Không đọc được auth_code hoặc state từ URL callback'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (callbackState != state) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('State không khớp, vui lòng thử đăng nhập Google lại'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      context.read<AuthBloc>().add(
            GoogleOAuthExchangeEvent(
              authCode: authCode,
              state: callbackState,
            ),
          );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể khởi tạo đăng nhập Google. Vui lòng thử lại. ($e)',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _tryHandleGoogleOAuthCallbackFromCurrentUrl() async {
    if (_isHandlingOAuthCallback || !mounted) {
      return;
    }

    try {
      final callbackParams =
          _extractGoogleCallbackParams(Uri.base.toString()) ??
              _extractGoogleCallbackParamsFromFragment(Uri.base.fragment);

      final authCode = callbackParams?['authCode'];
      final callbackState = callbackParams?['state'];
      if (authCode == null || callbackState == null) {
        return;
      }

      _isHandlingOAuthCallback = true;
      _clearOAuthCallbackFromBrowserUrl();

      String? expectedState;
      try {
        final prefs = await SharedPreferences.getInstance();
        expectedState = prefs.getString(_googleOAuthStateStorageKey);
        await prefs.remove(_googleOAuthStateStorageKey);
      } catch (_) {
        expectedState = null;
      }

      if (!mounted) {
        return;
      }

      if (expectedState != null && expectedState != callbackState) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('State không khớp, vui lòng đăng nhập Google lại'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      context.read<AuthBloc>().add(
            GoogleOAuthExchangeEvent(
              authCode: authCode,
              state: callbackState,
            ),
          );
    } catch (_) {
      _isHandlingOAuthCallback = false;
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể xử lý đăng nhập Google. Vui lòng thử lại.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearOAuthCallbackFromBrowserUrl() {
    if (!kIsWeb || !mounted) {
      return;
    }

    final cleanPath = Uri.base.path.isEmpty ? '/' : Uri.base.path;
    context.replace(cleanPath);
  }

  Map<String, String>? _extractGoogleCallbackParamsFromFragment(
      String fragment) {
    if (fragment.isEmpty || !fragment.contains('?')) {
      return null;
    }

    final queryString = fragment.substring(fragment.indexOf('?') + 1);
    return _extractGoogleCallbackParams(queryString);
  }

  Future<String?> _showGoogleCallbackInputDialog() async {
    final controller = TextEditingController();
    final callback = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nhập URL callback Google'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Dán URL chứa auth_code và state',
              suffixIcon: VoiceInputIconButton(
                controller: controller,
                tooltip: 'Nhập URL callback bằng giọng nói',
                stopTooltip: 'Dừng nhập giọng nói',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return callback;
  }

  Map<String, String>? _extractGoogleCallbackParams(String callbackInput) {
    final input = callbackInput.trim();
    if (input.isEmpty) {
      return null;
    }

    try {
      final uri = Uri.parse(input);
      if (uri.queryParameters.isNotEmpty) {
        final authCode =
            uri.queryParameters['auth_code'] ?? uri.queryParameters['code'];
        final state = uri.queryParameters['state'];
        if (authCode != null && state != null) {
          return {'authCode': authCode, 'state': state};
        }
      }
    } catch (_) {
      // Fallback to parsing as raw query string.
    }

    try {
      final queryString = input.startsWith('?') ? input.substring(1) : input;
      final queryParams = Uri.splitQueryString(queryString);
      final authCode = queryParams['auth_code'] ?? queryParams['code'];
      final state = queryParams['state'];
      if (authCode != null && state != null) {
        return {'authCode': authCode, 'state': state};
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đăng nhập thành công!'),
                backgroundColor: Colors.green,
              ),
            );
            // Navigate to home screen
            context.go(AppRoutes.home);
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    Text(
                      'Đăng nhập',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chào mừng đến Signal Map',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Email or Phone Field
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email hoặc số điện thoại',
                        hintText: 'user@example.com',
                        filled: true,
                        fillColor: Colors.grey[100],
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.email, color: Colors.white),
                        ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                          maxWidth: 132,
                        ),
                        suffixIcon: SizedBox(
                          width: 116,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              VoiceInputIconButton(
                                controller: _emailController,
                                tooltip: 'Nhập email bằng giọng nói',
                                stopTooltip: 'Dừng nhập giọng nói',
                                onTextChanged: (value) {
                                  setState(() {
                                    _isEmailInput = value.contains('@');
                                  });
                                },
                              ),
                              Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child:
                                    const Icon(Icons.phone, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 1),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _validateEmail,
                      onChanged: (value) {
                        setState(() {
                          _isEmailInput = value.contains('@');
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password Field
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        hintText: '••••••••',
                        filled: true,
                        fillColor: Colors.grey[100],
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 1),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      validator: _validatePassword,
                      onFieldSubmitted: (_) => _handleLogin(),
                    ),
                    const SizedBox(height: 16),

                    // Remember Me & Forgot Password
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                                activeColor: Colors.red,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              Flexible(
                                child: Text(
                                  'Ghi nhớ',
                                  style: TextStyle(color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // TODO: Navigate to forgot password
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Tính năng đang phát triển'),
                              ),
                            );
                          },
                          child: const Text(
                            'Quên mật khẩu?',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Login Button
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return ElevatedButton(
                          onPressed: isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Đăng nhập',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Divider
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey[300])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'hoặc',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey[300])),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Google Sign In
                    OutlinedButton(
                      onPressed: () {
                        final isLoading =
                            context.read<AuthBloc>().state is AuthLoading;
                        if (!isLoading) {
                          _handleGoogleOAuth();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text(
                        'Đăng nhập với Google',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Facebook Sign In
                    OutlinedButton(
                      onPressed: () {
                        // TODO: Implement Facebook Sign In
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tính năng đang phát triển'),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text(
                        'Đăng nhập với Facebook',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Register Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Chưa có tài khoản?',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        TextButton(
                          onPressed: () {
                            context.push(AppRoutes.register);
                          },
                          child: const Text(
                            'Đăng ký',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
