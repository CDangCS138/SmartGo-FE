import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'web_text_to_speech.dart';

class TextToSpeechService {
  TextToSpeechService._();

  static final TextToSpeechService instance = TextToSpeechService._();

  final FlutterTts _tts = FlutterTts();
  final WebTextToSpeech _webTextToSpeech = createWebTextToSpeech();
  bool _isInitialized = false;
  bool _hasConfiguredVietnameseLanguage = false;
  bool _hasConfiguredVietnameseVoice = false;
  String? _activeLanguageTag;

  Future<void> _initialize() async {
    if (_isInitialized) {
      return;
    }

    await _tts.awaitSpeakCompletion(true);
    await _configurePreferredVoice(force: true);

    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);

    if (!kIsWeb) {
      await _tts.setVolume(1.0);
    }

    _isInitialized = true;
  }

  Future<void> _configurePreferredVoice({bool force = false}) async {
    if (_hasConfiguredVietnameseLanguage &&
        _hasConfiguredVietnameseVoice &&
        !force) {
      return;
    }

    if (force || !_hasConfiguredVietnameseLanguage) {
      final languageCandidates = await _buildLanguageCandidates();

      var languageWasSet = false;
      for (final candidate in languageCandidates) {
        final didSet = await _trySetLanguage(candidate);
        if (didSet) {
          languageWasSet = true;
          break;
        }
      }

      if (!languageWasSet) {
        for (final fallback in const ['vi-VN', 'vi', 'vi_VN']) {
          final didSet = await _trySetLanguage(fallback);
          if (didSet) {
            languageWasSet = true;
            break;
          }
        }
      }

      _hasConfiguredVietnameseLanguage = languageWasSet;
    }

    if (force || !_hasConfiguredVietnameseVoice) {
      var voiceWasSet = await _setVietnameseVoiceIfAvailable();
      if (!voiceWasSet && kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 250));
        voiceWasSet = await _setVietnameseVoiceIfAvailable();
      }
      _hasConfiguredVietnameseVoice = voiceWasSet;
    }
  }

  Future<List<String>> _buildLanguageCandidates() async {
    final candidates = <String>[];

    try {
      final raw = await _tts.getLanguages;
      if (raw is List) {
        for (final item in raw) {
          final language = item.toString().trim();
          if (language.isEmpty) {
            continue;
          }

          if (_isVietnameseTag(language)) {
            candidates.add(language);
          }
        }
      }
    } catch (_) {
      // Keep fallback candidates.
    }

    for (final fallback in const ['vi-VN', 'vi_VN', 'vi']) {
      if (!candidates.contains(fallback)) {
        candidates.add(fallback);
      }
    }

    return candidates;
  }

  Future<bool> _setVietnameseVoiceIfAvailable() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) {
        return false;
      }

      Map<String, dynamic>? selectedVoice;
      var selectedScore = -1;

      for (final voice in raw) {
        if (voice is! Map) {
          continue;
        }

        final mapped = <String, dynamic>{};
        for (final entry in voice.entries) {
          mapped[entry.key.toString()] = entry.value;
        }

        final locale =
            (mapped['locale'] ?? mapped['language'] ?? '').toString().trim();
        final name = (mapped['name'] ?? '').toString().trim();
        final score = _scoreVietnameseVoice(locale, name);
        if (score > selectedScore) {
          selectedScore = score;
          selectedVoice = mapped;
        }
      }

      if (selectedVoice == null || selectedScore < 0) {
        return false;
      }

      final locale =
          (selectedVoice['locale'] ?? selectedVoice['language'] ?? '')
              .toString()
              .trim();
      final name = (selectedVoice['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        return false;
      }

      if (locale.isNotEmpty) {
        await _trySetLanguage(locale);
      }

      await _tts.setVoice({
        'name': name,
        if (locale.isNotEmpty) 'locale': locale,
      });
      return true;
    } catch (_) {
      // Keep default voice if voice selection is unsupported.
      return false;
    }
  }

  Future<bool> _trySetLanguage(String languageTag) async {
    final tag = languageTag.trim();
    if (tag.isEmpty) {
      return false;
    }

    try {
      await _tts.setLanguage(tag);
      _activeLanguageTag = tag;
      return true;
    } catch (_) {
      return false;
    }
  }

  int _scoreVietnameseVoice(String locale, String name) {
    if (!_isVietnameseTag(locale)) {
      return -1;
    }

    var score = 100;

    final normalizedName = name.toLowerCase();

    if (normalizedName.contains('vietnamese') ||
        normalizedName.contains('viet') ||
        normalizedName.contains('vi-vn')) {
      score += 10;
    }

    if (normalizedName.contains('female') ||
        normalizedName.contains('hoaimy') ||
        normalizedName.contains('linhsan')) {
      score += 5;
    }

    return score;
  }

  bool _containsNonAscii(String value) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit > 127) {
        return true;
      }
    }
    return false;
  }

  bool _isVietnameseTag(String rawTag) {
    final tag = rawTag.toLowerCase().replaceAll('_', '-').trim();
    return tag == 'vi' || tag.startsWith('vi-');
  }

  Future<bool> speak(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) {
      return false;
    }

    if (kIsWeb && _webTextToSpeech.isSupported) {
      final spokeOnWeb = await _webTextToSpeech.speak(text);
      if (spokeOnWeb) {
        return true;
      }
    }

    try {
      await _initialize();

      final shouldRetryVietnamese = _containsNonAscii(text) &&
          (!_isVietnameseTag(_activeLanguageTag ?? '') ||
              !_hasConfiguredVietnameseVoice);
      await _configurePreferredVoice(force: shouldRetryVietnamese);

      await _tts.stop();
      final result = await _tts.speak(text);
      return result == null || result == 1;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    if (kIsWeb && _webTextToSpeech.isSupported) {
      await _webTextToSpeech.stop();
    }

    try {
      await _tts.stop();
    } catch (_) {
      // Ignore stop errors from unsupported platforms.
    }
  }
}
