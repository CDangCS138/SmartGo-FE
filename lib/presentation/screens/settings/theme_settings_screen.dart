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
            children: [
              RadioListTile<app_theme.ThemeMode>(
                title: Text(l10n.lightTheme),
                value: app_theme.ThemeMode.light,
                groupValue: state.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    context.read<ThemeBloc>().add(ThemeChanged(value));
                  }
                },
              ),
              RadioListTile<app_theme.ThemeMode>(
                title: Text(l10n.darkTheme),
                value: app_theme.ThemeMode.dark,
                groupValue: state.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    context.read<ThemeBloc>().add(ThemeChanged(value));
                  }
                },
              ),
              RadioListTile<app_theme.ThemeMode>(
                title: Text(l10n.systemTheme),
                value: app_theme.ThemeMode.system,
                groupValue: state.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    context.read<ThemeBloc>().add(ThemeChanged(value));
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
