import 'web_text_to_speech_base.dart';
import 'web_text_to_speech_stub.dart'
    if (dart.library.html) 'web_text_to_speech_web.dart' as impl;

export 'web_text_to_speech_base.dart';

WebTextToSpeech createWebTextToSpeech() => impl.createWebTextToSpeech();
