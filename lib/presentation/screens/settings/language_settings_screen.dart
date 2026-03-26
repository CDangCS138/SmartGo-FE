import 'package:flutter/material.dart';
import 'package:smartgo/l10n/app_localizations.dart';

/// Language Settings Screen
class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String _selectedLanguage = 'vi';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.language),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildLanguageTile(
            context,
            label: l10n.english,
            value: 'en',
          ),
          _buildLanguageTile(
            context,
            label: l10n.vietnamese,
            value: 'vi',
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final selected = _selectedLanguage == value;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check, color: scheme.primary)
          : const SizedBox.shrink(),
      onTap: () {
        setState(() {
          _selectedLanguage = value;
        });
        // In real app, save language to storage and update locale
      },
    );
  }
}
