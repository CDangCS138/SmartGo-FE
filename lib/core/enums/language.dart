enum Language {
  english,
  vietnamese,
}

extension LanguageExtension on Language {
  String get code {
    switch (this) {
      case Language.english:
        return 'en';
      case Language.vietnamese:
        return 'vi';
    }
  }

  String get name {
    switch (this) {
      case Language.english:
        return 'English';
      case Language.vietnamese:
        return 'Tiếng Việt';
    }
  }

  static Language fromCode(String code) {
    switch (code) {
      case 'en':
        return Language.english;
      case 'vi':
        return Language.vietnamese;
      default:
        return Language.vietnamese;
    }
  }
}
