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
    final profileId = _profileUser?.id ?? _rawUser?['_id']?.toString() ?? '-';
    final isAdmin = role == 'ADMIN';
    final initials = name.trim().isEmpty
        ? 'SG'
        : name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Hồ sơ cá nhân'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.settings),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF8E8), Color(0xFFF2E7C9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD1B57A)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFF0E1A2B),
                  backgroundImage:
                      (avatarUrl != null && avatarUrl.trim().isNotEmpty)
                          ? NetworkImage(avatarUrl)
                          : null,
                  child: (avatarUrl == null || avatarUrl.trim().isEmpty)
                      ? Text(
                          initials,
                          style: const TextStyle(
                            color: Color(0xFFD4B06A),
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
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2535),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          color: Color(0xFF556070),
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: const Color(0xFFD1B57A)),
                        ),
                        child: Text(
                          role,
                          style: const TextStyle(
                            color: Color(0xFF1A2535),
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
              _line('ID', profileId),
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
                color: const Color(0xFFFFF4F4),
                border: Border.all(color: const Color(0xFFF5BDBD)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFB33A3A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _profileError!,
                      style: const TextStyle(color: Color(0xFF7C2A2A)),
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
            title: 'Tuỳ chọn',
            rows: [
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
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0E1A2B),
              foregroundColor: const Color(0xFFD4B06A),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              context.read<AuthBloc>().add(const LogoutEvent());
            },
            icon: const Icon(Icons.logout),
            label: const Text(
              'Đăng xuất',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Profile Light Edition',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileInfoCard({required String title, required List<Widget> rows}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2535),
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _line(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                color: Color(0xFF5B6677),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF1A2535),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF22334D), size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2535),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6D7888),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF6D7888)),
          ],
        ),
      ),
    );
  }
}
