import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/theme/theme_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../../core/routes/app_routes.dart';
import 'package:smartgo/l10n/app_localizations.dart';

/// Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(l10n.settings),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          _buildSectionCard(
            context,
            title: 'Tài khoản',
            children: [
              _settingTile(
                context,
                icon: Icons.person_outline,
                title: 'Hồ sơ cá nhân',
                subtitle: 'Thông tin tài khoản và tuỳ chọn nhanh',
                onTap: () => context.push(AppRoutes.profile),
              ),
              const SizedBox(height: 8),
              _settingTile(
                context,
                icon: Icons.smart_toy_outlined,
                title: 'SmartGo AI Assistant',
                subtitle: 'Chat với AI có RAG từ tuyến, trạm và FAQ',
                onTap: () => context.go(AppRoutes.chatbot),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            title: 'Tùy chỉnh',
            children: [
              BlocBuilder<ThemeBloc, ThemeState>(
                builder: (context, state) {
                  return _settingTile(
                    context,
                    icon: Icons.palette_outlined,
                    title: l10n.theme,
                    subtitle: _getThemeName(context, state.themeMode),
                    onTap: () => context.go(AppRoutes.themeSettings),
                  );
                },
              ),
              const SizedBox(height: 8),
              _settingTile(
                context,
                icon: Icons.language_outlined,
                title: l10n.language,
                subtitle: 'Thiết lập ngôn ngữ hiển thị',
                onTap: () => context.go(AppRoutes.languageSettings),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            context,
            title: 'Quản trị',
            children: [
              _settingTile(
                context,
                icon: Icons.manage_accounts_outlined,
                title: 'Quản lý người dùng',
                subtitle: 'CRUD users cho admin',
                onTap: () => context.go(AppRoutes.usersAdmin),
              ),
              const SizedBox(height: 8),
              _settingTile(
                context,
                icon: Icons.psychology_alt_outlined,
                title: 'Chatbot admin',
                subtitle: 'Embed knowledge va quan tri messages',
                onTap: () => context.go(AppRoutes.chatbotAdmin),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: Text(l10n.logout),
              onPressed: () {
                _showLogoutDialog(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _settingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
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
            Icon(
              Icons.chevron_right,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
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
