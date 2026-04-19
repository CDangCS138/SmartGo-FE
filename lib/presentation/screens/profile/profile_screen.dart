import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/core/routes/app_routes.dart';
import 'package:smartgo/core/services/storage_service.dart';
import 'package:smartgo/data/datasources/users_remote_data_source.dart';
import 'package:smartgo/data/models/users_models.dart';
import 'package:smartgo/presentation/blocs/auth/auth_bloc.dart';
import 'package:smartgo/presentation/blocs/auth/auth_event.dart';
import 'package:smartgo/presentation/blocs/auth/auth_state.dart';
import 'package:smartgo/presentation/widgets/app_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final http.Client _client = http.Client();
  late final UsersRemoteDataSource _usersDataSource;

  Map<String, dynamic>? _rawUser;
  AdminUserModel? _profileUser;
  bool _isLoadingProfile = false;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _usersDataSource = UsersRemoteDataSource(client: _client);
    _loadUserFromStorage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchMyProfile();
    });
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  void _loadUserFromStorage() {
    final raw = getIt<StorageService>().getUserData();
    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    try {
      final parsed = json.decode(raw);
      if (parsed is Map<String, dynamic>) {
        setState(() {
          _rawUser = parsed;
        });
      }
    } catch (_) {
      // Ignore malformed cached user JSON.
    }
  }

  Future<void> _fetchMyProfile() async {
    final token = getIt<StorageService>().getAuthToken();
    if (token == null || token.isEmpty) {
      return;
    }

    final authState = context.read<AuthBloc>().state;
    final userIdFromState =
        authState is AuthAuthenticated ? authState.user.id : null;
    final fallbackId = _rawUser?['_id']?.toString();
    final userId = userIdFromState ?? fallbackId;

    if (userId == null || userId.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });

    try {
      final me = await _usersDataSource.getUserById(
        accessToken: token,
        id: userId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profileUser = me;
        _isLoadingProfile = false;
      });

      final currentRaw = <String, dynamic>{...?_rawUser};
      currentRaw['_id'] = me.id;
      currentRaw['name'] = me.name;
      currentRaw['email'] = me.email;
      currentRaw['role'] = me.role;
      currentRaw['avatar'] = me.avatar;
      await getIt<StorageService>().saveUserData(json.encode(currentRaw));
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingProfile = false;
        _profileError = 'Không tải được hồ sơ từ server: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final authState = context.watch<AuthBloc>().state;

    final fallbackName = _rawUser?['name']?.toString() ?? 'Người dùng SmartGo';
    final fallbackEmail = _rawUser?['email']?.toString() ?? 'No email';

    final name = _profileUser?.name ??
        (authState is AuthAuthenticated ? authState.user.name : fallbackName);
    final email = _profileUser?.email ??
        (authState is AuthAuthenticated ? authState.user.email : fallbackEmail);
    final role =
        (_profileUser?.role ?? _rawUser?['role']?.toString() ?? 'member')
            .toUpperCase();
    final avatarUrl = _profileUser?.avatar ?? _rawUser?['avatar']?.toString();
    final isAdmin = role == 'ADMIN';
    final initials = name.trim().isEmpty
        ? 'SG'
        : name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Hồ sơ cá nhân'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            context.go(AppRoutes.home);
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer,
                  scheme.primaryContainer.withValues(alpha: 0.72),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.16),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: scheme.primary,
                  backgroundImage:
                      (avatarUrl != null && avatarUrl.trim().isNotEmpty)
                          ? NetworkImage(avatarUrl)
                          : null,
                  child: (avatarUrl == null || avatarUrl.trim().isEmpty)
                      ? Text(
                          initials,
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          role,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _profileInfoCard(
            title: 'Thông tin tài khoản',
            rows: [
              _line('Tên hiển thị', name),
              _line('Email', email),
              _line('Vai trò', role),
            ],
          ),
          if (_isLoadingProfile) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_profileError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.7),
                border: Border.all(color: scheme.error.withValues(alpha: 0.32)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _profileError!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: _fetchMyProfile,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _profileInfoCard(
            title: 'Quản lý tài khoản',
            rows: [
              _actionTile(
                icon: Icons.person_outline,
                title: 'Thông tin cá nhân',
                subtitle: 'Xem dữ liệu hồ sơ và trạng thái tài khoản',
                onTap: () => _showFeatureInProgress('Thông tin cá nhân'),
              ),
              _actionTile(
                icon: Icons.lock_outline,
                title: 'Bảo mật tài khoản',
                subtitle: 'Quản lý phiên đăng nhập và xác thực',
                onTap: () => _showFeatureInProgress('Bảo mật tài khoản'),
              ),
              _actionTile(
                icon: Icons.settings_outlined,
                title: 'Cài đặt',
                subtitle: 'Theme, ngôn ngữ, cấu hình ứng dụng',
                onTap: () => context.go(AppRoutes.settings),
              ),
              if (isAdmin)
                _actionTile(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Quản lý người dùng',
                  subtitle: 'Khu vực admin',
                  onTap: () => context.go(AppRoutes.usersAdmin),
                ),
            ],
          ),
          const SizedBox(height: 16),
          AppButton(
            text: 'Đăng xuất',
            icon: Icons.logout,
            backgroundColor: scheme.error,
            textColor: scheme.onError,
            onPressed: () {
              context.read<AuthBloc>().add(const LogoutEvent());
            },
          ),
        ],
      ),
    );
  }

  Widget _profileInfoCard({required String title, required List<Widget> rows}) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _line(String k, String v) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: scheme.onPrimaryContainer, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _showFeatureInProgress(String featureName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$featureName sẽ được cập nhật trong phiên bản tới.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
