import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import '../../../core/constants/app_env.dart';
import '../../../core/utils/open_external_url.dart';
import '../../../core/routes/app_routes.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/voice_input_icon_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _googleOAuthStateStorageKey = 'google_oauth_state';
  static const _googleOAuthLegacyLoginStateStorageKey =
      'google_oauth_state_login';
  static const _googleOAuthLegacyRegisterStateStorageKey =
      'google_oauth_state_register';
  static const _googleOAuthLastCallbackStorageKey =
      'google_oauth_last_callback_signature';
  static const _googleOAuthDebugPrefix = '[GOOGLE_OAUTH_DEBUG]';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập họ và tên';
    }
    if (value.length < 2) {
      return 'Họ và tên quá ngắn';
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

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng xác nhận mật khẩu';
    }
    if (value != _passwordController.text) {
      return 'Mật khẩu không khớp';
    }
    return null;
  }

  void _handleRegister() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
            RegisterEvent(
              email: _emailController.text.trim(),
              name: _nameController.text.trim(),
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
        await prefs.setString(_googleOAuthLegacyRegisterStateStorageKey, state);
        await prefs.remove(_googleOAuthLastCallbackStorageKey);
      } catch (_) {
        // Continue OAuth even if local storage is unavailable.
      }

      final authUri = Uri.parse(
        '${AppEnv.baseUrl}/api/v1/auth/google?state=$state',
      );

      if (kIsWeb) {
        // Keep OAuth in the same tab so callback can be handled immediately
        // by the current app instance on web.
        const webTarget = '_self';
        debugPrint('Google OAuth URL: $authUri (target: $webTarget)');
        final opened = await openExternalUrl(authUri, webTarget: webTarget);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể mở trang đăng nhập Google.'),
              backgroundColor: Colors.red,
            ),
          );
        }
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

    final callbackParams = _extractGoogleCallbackParams(Uri.base.toString()) ??
        _extractGoogleCallbackParamsFromFragment(Uri.base.fragment);

    final authCode = callbackParams?['authCode'];
    final callbackState = callbackParams?['state'];
    if (authCode == null || callbackState == null) {
      return;
    }

    final callbackSignature = '$authCode::$callbackState';

    _isHandlingOAuthCallback = true;

    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastHandled = prefs.getString(_googleOAuthLastCallbackStorageKey);
        if (lastHandled == callbackSignature) {
          _clearOAuthCallbackFromBrowserUrl();
          return;
        }

        await prefs.setString(
          _googleOAuthLastCallbackStorageKey,
          callbackSignature,
        );
      } catch (_) {
        // Continue processing even if dedupe storage is unavailable.
      }

      _clearOAuthCallbackFromBrowserUrl();

      final expectedStates = <String>{};
      try {
        final prefs = await SharedPreferences.getInstance();
        final keysToCheck = <String>[
          _googleOAuthStateStorageKey,
          _googleOAuthLegacyLoginStateStorageKey,
          _googleOAuthLegacyRegisterStateStorageKey,
        ];

        for (final key in keysToCheck) {
          final value = prefs.getString(key);
          if (value != null && value.isNotEmpty) {
            expectedStates.add(value);
          }
        }

        await prefs.remove(_googleOAuthStateStorageKey);
        await prefs.remove(_googleOAuthLegacyLoginStateStorageKey);
        await prefs.remove(_googleOAuthLegacyRegisterStateStorageKey);
      } catch (_) {
        expectedStates.clear();
      }

      if (!mounted) {
        return;
      }

      if (expectedStates.isNotEmpty &&
          !expectedStates.contains(callbackState)) {
        _showOAuthDebugDialog(
          '''$_googleOAuthDebugPrefix
phase: state_mismatch_before_exchange
screen: register
callback_state: $callbackState
expected_states: ${expectedStates.join(', ')}
uri_base: ${Uri.base}''',
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
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể xử lý đăng nhập Google. Vui lòng thử lại.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _isHandlingOAuthCallback = false;
    }
  }

  void _showOAuthDebugDialog(String rawDebugMessage) {
    if (!mounted) {
      return;
    }

    final debugText =
        rawDebugMessage.replaceFirst(_googleOAuthDebugPrefix, '').trim();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Google OAuth Debug'),
          content: SingleChildScrollView(
            child: SelectableText(debugText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
            ElevatedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: debugText));
                if (!mounted) {
                  return;
                }

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã copy thông tin Google OAuth debug'),
                  ),
                );
              },
              child: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  void _handleAuthError(String message) {
    if (message.startsWith(_googleOAuthDebugPrefix)) {
      _showOAuthDebugDialog(message);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _clearOAuthCallbackFromBrowserUrl() {
    if (!kIsWeb || !mounted) {
      return;
    }

    context.replace(AppRoutes.register);
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
          if (state is AuthAuthenticated || state is AuthRegisterSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đăng ký thành công!'),
                backgroundColor: Colors.green,
              ),
            );
            // Navigate to home screen
            context.go(AppRoutes.home);
          } else if (state is AuthError) {
            _handleAuthError(state.message);
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
                      'Đăng ký',
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

                    // Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Họ và tên',
                        hintText: 'Nhập họ và tên',
                        filled: true,
                        fillColor: Colors.grey[100],
                        suffixIcon: VoiceInputIconButton(
                          controller: _nameController,
                          tooltip: 'Nhập họ tên bằng giọng nói',
                          stopTooltip: 'Dừng nhập giọng nói',
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
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      validator: _validateName,
                    ),
                    const SizedBox(height: 16),

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
                      textInputAction: TextInputAction.next,
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 16),

                    // Confirm Password Field
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Xác nhận mật khẩu',
                        hintText: '••••••••',
                        filled: true,
                        fillColor: Colors.grey[100],
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
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
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      validator: _validateConfirmPassword,
                      onFieldSubmitted: (_) => _handleRegister(),
                    ),
                    const SizedBox(height: 24),

                    // Register Button
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return ElevatedButton(
                          onPressed: isLoading ? null : _handleRegister,
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
                                  'Đăng ký',
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

                    // Login Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Đã có tài khoản?',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        TextButton(
                          onPressed: () {
                            context.pop();
                          },
                          child: const Text(
                            'Đăng nhập',
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
