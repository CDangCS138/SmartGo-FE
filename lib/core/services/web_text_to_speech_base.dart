abstract class WebTextToSpeech {
  bool get isSupported;

  Future<bool> speak(String text);

  Future<void> stop();
}
