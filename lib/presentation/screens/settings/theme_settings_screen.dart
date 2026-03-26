import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/theme/theme_bloc.dart';
import '../../../core/enums/theme_mode.dart' as app_theme;
import 'package:smartgo/l10n/app_localizations.dart';

/// Theme Settings Screen
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.theme),
      ),
      body: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _buildThemeTile(
                context,
                title: l10n.lightTheme,
                value: app_theme.ThemeMode.light,
                current: state.themeMode,
              ),
              _buildThemeTile(
                context,
                title: l10n.darkTheme,
                value: app_theme.ThemeMode.dark,
                current: state.themeMode,
              ),
              _buildThemeTile(
                context,
                title: l10n.systemTheme,
                value: app_theme.ThemeMode.system,
                current: state.themeMode,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThemeTile(
    BuildContext context, {
    required String title,
    required app_theme.ThemeMode value,
    required app_theme.ThemeMode current,
  }) {
    final selected = value == current;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(title),
      trailing: selected
          ? Icon(Icons.check, color: scheme.primary)
          : const SizedBox.shrink(),
      onTap: () => context.read<ThemeBloc>().add(ThemeChanged(value)),
    );
  }
}
