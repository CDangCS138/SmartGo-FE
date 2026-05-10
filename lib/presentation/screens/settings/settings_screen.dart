import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/theme/theme_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/di/injection.dart';
import 'package:smartgo/l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;

    String role = 'MEMBER';
    final rawData = getIt<StorageService>().getUserData();
    if (rawData != null && rawData.isNotEmpty) {
      try {
        final parsed = json.decode(rawData);
        if (parsed['role'] != null) {
          role = parsed['role'].toString().toUpperCase();
        }
      } catch (_) {}
    }

    final isAdmin = role == 'ADMIN';
    final name = user?.name ?? 'Khách';
    final email = user?.email ?? 'Chưa đăng nhập';
    final initials = name.trim().isEmpty
        ? 'SG'
        : name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: UIConstants.scaffoldBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Text(
                  'Tài khoản',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: UIConstants.textPrimary,
                  ),
                ),
              ),

              // Gradient Profile Card
              Container(
                margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D9488), Color(0xFF14B8A6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Cài đặt Section
              BlocBuilder<ThemeBloc, ThemeState>(builder: (context, state) {
                final themeName = _getThemeName(context, state.themeMode);
                return _buildSection(
                  title: 'Cài đặt chung',
                  items: [
                    _SectionItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Thông tin cá nhân',
                      onTap: () => context.go(AppRoutes.profile),
                    ),
                    _SectionItem(
                      icon: Icons.palette_rounded,
                      label: 'Tuỳ chọn hiển thị',
                      meta: themeName,
                      onTap: () => context.go(AppRoutes.themeSettings),
                    ),
                    _SectionItem(
                      icon: Icons.language_rounded,
                      label: 'Ngôn ngữ',
                      onTap: () => context.go(AppRoutes.languageSettings),
                    ),
                  ],
                );
              }),

              // Tiện ích Section
              _buildSection(
                title: 'Tiện ích',
                items: [
                  _SectionItem(
                    icon: Icons.smart_toy_outlined,
                    label: 'Trợ lý AI SmartGo',
                    onTap: () => context.go(AppRoutes.chatbot),
                  ),
                ],
              ),

              if (isAdmin)
                // Quản trị Section
                _buildSection(
                  title: 'Quản trị hệ thống',
                  items: [
                    _SectionItem(
                      icon: Icons.manage_accounts_rounded,
                      label: 'Quản lý người dùng',
                      onTap: () => context.go(AppRoutes.usersAdmin),
                    ),
                    _SectionItem(
                      icon: Icons.psychology_alt_rounded,
                      label: 'Chatbot Admin',
                      onTap: () => context.go(AppRoutes.chatbotAdmin),
                    ),
                  ],
                ),

              // Đăng xuất Button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: InkWell(
                  onTap: () => _showLogoutDialog(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: UIConstants.borderLight),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.logout_rounded,
                            size: 18, color: UIConstants.danger),
                        const SizedBox(width: 8),
                        Text(
                          l10n.logout,
                          style: const TextStyle(
                            color: UIConstants.danger,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
      {required String title, required List<_SectionItem> items}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: UIConstants.textSecondary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: UIConstants.borderLight),
            ),
            child: Column(
              children: items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Column(
                  children: [
                    if (index > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: UIConstants.borderLight,
                      ),
                    InkWell(
                      onTap: item.onTap,
                      borderRadius: BorderRadius.vertical(
                        top: index == 0
                            ? const Radius.circular(24)
                            : Radius.zero,
                        bottom: index == items.length - 1
                            ? const Radius.circular(24)
                            : Radius.zero,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                item.icon,
                                size: 18,
                                color: UIConstants.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                style: const TextStyle(
                                  color: UIConstants.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (item.meta != null) ...[
                              Text(
                                item.meta!,
                                style: const TextStyle(
                                  color: UIConstants.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: UIConstants.iconMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logout),
        content: const Text('Bạn có chắc muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<AuthBloc>().add(const LogoutEvent());
            },
            child: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _getThemeName(BuildContext context, dynamic themeMode) {
    final l10n = AppLocalizations.of(context)!;
    switch (themeMode.toString()) {
      case 'ThemeMode.light':
        return l10n.lightTheme;
      case 'ThemeMode.dark':
        return l10n.darkTheme;
      case 'ThemeMode.system':
        return l10n.systemTheme;
      default:
        return l10n.systemTheme;
    }
  }
}

class _SectionItem {
  final IconData icon;
  final String label;
  final String? meta;
  final VoidCallback onTap;

  _SectionItem({
    required this.icon,
    required this.label,
    this.meta,
    required this.onTap,
  });
}
