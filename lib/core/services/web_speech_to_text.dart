import 'web_speech_to_text_base.dart';
import 'web_speech_to_text_stub.dart'
    if (dart.library.html) 'web_speech_to_text_web.dart' as impl;

export 'web_speech_to_text_base.dart';

WebSpeechToText createWebSpeechToText() => impl.createWebSpeechToText();
