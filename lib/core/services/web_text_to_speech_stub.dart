import 'web_text_to_speech_base.dart';

class _UnsupportedWebTextToSpeech implements WebTextToSpeech {
  @override
  bool get isSupported => false;

  @override
  Future<bool> speak(String text) async {
    return false;
  }

  @override
  Future<void> stop() async {
    return;
  }
}

WebTextToSpeech createWebTextToSpeech() => _UnsupportedWebTextToSpeech();
