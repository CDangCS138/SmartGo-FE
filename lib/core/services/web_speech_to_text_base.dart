typedef WebSpeechResultCallback = void Function(
  String recognizedText,
  bool isFinal,
);

typedef WebSpeechStatusCallback = void Function(String status);
typedef WebSpeechErrorCallback = void Function(String errorMessage);

abstract class WebSpeechToText {
  bool get isSupported;
  bool get isListening;

  Future<bool> startListening({
    required WebSpeechResultCallback onResult,
    required WebSpeechStatusCallback onStatus,
    required WebSpeechErrorCallback onError,
    String localeId = 'vi-VN',
    bool partialResults = true,
  });

  Future<void> stopListening();
}
