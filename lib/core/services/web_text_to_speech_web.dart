// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js' as js;

import 'web_text_to_speech_base.dart';

class _BrowserWebTextToSpeech implements WebTextToSpeech {
  dynamic get _utteranceConstructor => js.context['SpeechSynthesisUtterance'];

  js.JsObject? get _speechSynthesis {
    final synthesis = js.context['speechSynthesis'];
    return _toJsObject(synthesis);
  }

  @override
  bool get isSupported {
    return _speechSynthesis != null && _utteranceConstructor != null;
  }

  @override
  Future<bool> speak(String text) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return false;
    }

    final synthesis = _speechSynthesis;
    final constructor = _utteranceConstructor;
    if (synthesis == null || constructor == null) {
      return false;
    }

    try {
      final utterance = js.JsObject(constructor, [normalizedText]);
      utterance['lang'] = 'vi-VN';
      utterance['rate'] = 1.0;
      utterance['pitch'] = 1.0;
      utterance['volume'] = 1.0;

      _assignPreferredVietnameseVoice(synthesis, utterance);

      synthesis.callMethod('cancel');
      synthesis.callMethod('speak', [utterance]);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final synthesis = _speechSynthesis;
    if (synthesis == null) {
      return;
    }

    try {
      synthesis.callMethod('cancel');
    } catch (_) {
      // Ignore browser-specific speech synthesis errors.
    }
  }

  void _assignPreferredVietnameseVoice(
    js.JsObject synthesis,
    js.JsObject utterance,
  ) {
    try {
      final voices = _collectVoices(synthesis.callMethod('getVoices'));
      if (voices.isEmpty) {
        return;
      }

      dynamic selectedVoice;
      var selectedScore = -1;

      for (final voice in voices) {
        final score = _voiceScore(voice);
        if (score > selectedScore) {
          selectedScore = score;
          selectedVoice = voice;
        }
      }

      if (selectedVoice != null && selectedScore >= 0) {
        utterance['voice'] = selectedVoice;
      }
    } catch (_) {
      // Keep browser default voice if voice selection is unsupported.
    }
  }

  List<dynamic> _collectVoices(dynamic rawVoices) {
    if (rawVoices is js.JsArray) {
      return List<dynamic>.generate(
          rawVoices.length, (index) => rawVoices[index]);
    }

    if (rawVoices is List) {
      return rawVoices;
    }

    final wrapped = _toJsObject(rawVoices);
    if (wrapped == null) {
      return const <dynamic>[];
    }

    final length = _asInt(wrapped['length']);
    if (length <= 0) {
      return const <dynamic>[];
    }

    final voices = <dynamic>[];
    for (var index = 0; index < length; index++) {
      final voice = wrapped[index];
      if (voice != null) {
        voices.add(voice);
      }
    }
    return voices;
  }

  int _voiceScore(dynamic voice) {
    final wrappedVoice = _toJsObject(voice);
    if (wrappedVoice == null) {
      return -1;
    }

    final lang = _normalizeTag(
      (wrappedVoice['lang'] ?? wrappedVoice['locale'] ?? '').toString(),
    );
    if (!_isVietnameseTag(lang)) {
      return -1;
    }

    var score = 100;
    final name = (wrappedVoice['name'] ?? '').toString().toLowerCase();

    if (name.contains('vietnamese') ||
        name.contains('viet') ||
        name.contains('vi-vn')) {
      score += 10;
    }

    if (name.contains('female') ||
        name.contains('hoaimy') ||
        name.contains('linhsan')) {
      score += 5;
    }

    return score;
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isVietnameseTag(String tag) {
    return tag == 'vi' || tag.startsWith('vi-');
  }

  String _normalizeTag(String raw) {
    return raw.toLowerCase().replaceAll('_', '-').trim();
  }

  js.JsObject? _toJsObject(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is js.JsObject) {
      return value;
    }

    try {
      return js.JsObject.fromBrowserObject(value);
    } catch (_) {
      return null;
    }
  }
}

WebTextToSpeech createWebTextToSpeech() => _BrowserWebTextToSpeech();
