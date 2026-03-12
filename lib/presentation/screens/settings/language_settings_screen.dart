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
        children: [
          RadioListTile<String>(
            title: Text(l10n.english),
            value: 'en',
            groupValue: _selectedLanguage,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedLanguage = value;
                });
                // In real app, would save to storage and update locale
              }
            },
          ),
          RadioListTile<String>(
            title: Text(l10n.vietnamese),
            value: 'vi',
            groupValue: _selectedLanguage,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedLanguage = value;
                });
                // In real app, would save to storage and update locale
              }
            },
          ),
        ],
      ),
    );
  }
}
