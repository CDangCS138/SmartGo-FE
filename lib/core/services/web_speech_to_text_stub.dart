import 'web_speech_to_text_base.dart';

class _UnsupportedWebSpeechToText implements WebSpeechToText {
  @override
  bool get isListening => false;

  @override
  bool get isSupported => false;

  @override
  Future<bool> startListening({
    required WebSpeechResultCallback onResult,
    required WebSpeechStatusCallback onStatus,
    required WebSpeechErrorCallback onError,
    String localeId = 'vi-VN',
    bool partialResults = true,
  }) async {
    onStatus('unavailable');
    return false;
  }

  @override
  Future<void> stopListening() async {
    return;
  }
}

WebSpeechToText createWebSpeechToText() => _UnsupportedWebSpeechToText();
