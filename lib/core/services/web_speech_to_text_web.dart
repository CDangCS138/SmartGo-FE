// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js' as js;

import 'web_speech_to_text_base.dart';

class _BrowserWebSpeechToText implements WebSpeechToText {
  js.JsObject? _recognition;
  Function? _onStartHandler;
  Function? _onEndHandler;
  Function? _onErrorHandler;
  Function? _onResultHandler;

  bool _isListening = false;

  dynamic get _speechRecognitionConstructor {
    final standard = js.context['SpeechRecognition'];
    if (standard != null) {
      return standard;
    }
    return js.context['webkitSpeechRecognition'];
  }

  @override
  bool get isSupported => _speechRecognitionConstructor != null;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> startListening({
    required WebSpeechResultCallback onResult,
    required WebSpeechStatusCallback onStatus,
    required WebSpeechErrorCallback onError,
    String localeId = 'vi-VN',
    bool partialResults = true,
  }) async {
    final constructor = _speechRecognitionConstructor;
    if (constructor == null) {
      onStatus('unavailable');
      return false;
    }

    if (_isListening) {
      return true;
    }

    try {
      final recognition = js.JsObject(constructor);
      final resolvedLocale = localeId.trim().isEmpty ? 'vi-VN' : localeId;

      recognition['lang'] = resolvedLocale;
      recognition['continuous'] = false;
      recognition['interimResults'] = partialResults;
      recognition['maxAlternatives'] = 1;

      _bindEventHandlers(
        recognition: recognition,
        onStatus: onStatus,
        onError: onError,
        onResult: onResult,
      );

      _recognition = recognition;
      recognition.callMethod('start');
      return true;
    } catch (_) {
      onError('Không thể khởi động nhận diện giọng nói trên trình duyệt này.');
      onStatus('error');
      return false;
    }
  }

  @override
  Future<void> stopListening() async {
    final recognition = _recognition;
    if (recognition == null) {
      _isListening = false;
      return;
    }

    try {
      recognition.callMethod('stop');
    } catch (_) {
      try {
        recognition.callMethod('abort');
      } catch (_) {
        // Ignore abort errors.
      }
    }

    _isListening = false;
  }

  void _bindEventHandlers({
    required js.JsObject recognition,
    required WebSpeechStatusCallback onStatus,
    required WebSpeechErrorCallback onError,
    required WebSpeechResultCallback onResult,
  }) {
    _onStartHandler = (dynamic _) {
      _isListening = true;
      onStatus('listening');
    };

    _onEndHandler = (dynamic _) {
      _isListening = false;
      onStatus('done');
    };

    _onErrorHandler = (dynamic event) {
      _isListening = false;
      onError(_normalizeError(event));
      onStatus('done');
    };

    _onResultHandler = (dynamic event) {
      final parsed = _parseResultEvent(event);
      if (parsed == null) {
        return;
      }
      onResult(parsed.$1, parsed.$2);
    };

    recognition['onstart'] = _onStartHandler;
    recognition['onend'] = _onEndHandler;
    recognition['onerror'] = _onErrorHandler;
    recognition['onresult'] = _onResultHandler;
  }

  (String, bool)? _parseResultEvent(dynamic event) {
    try {
      final results = _property(event, 'results');
      if (results == null) {
        return null;
      }

      final length = _asInt(_property(results, 'length'));
      if (length == 0) {
        return null;
      }

      final eventResultIndex = _asInt(_property(event, 'resultIndex'));
      final startIndex = eventResultIndex >= 0 && eventResultIndex < length
          ? eventResultIndex
          : 0;

      final buffer = StringBuffer();
      var hasFinal = false;

      for (var index = startIndex; index < length; index++) {
        final result = _index(results, index);
        if (result == null) {
          continue;
        }

        final alternative = _index(result, 0);
        final transcript =
            (_property(alternative, 'transcript') ?? '').toString().trim();

        if (transcript.isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.write(' ');
          }
          buffer.write(transcript);
        }

        if (_asBool(_property(result, 'isFinal'))) {
          hasFinal = true;
        }
      }

      final text = buffer.toString().trim();
      if (text.isEmpty) {
        return null;
      }

      return (text, hasFinal);
    } catch (_) {
      return null;
    }
  }

  String _normalizeError(dynamic event) {
    try {
      final rawCode = (_property(event, 'error') ?? '').toString();
      switch (rawCode) {
        case 'not-allowed':
        case 'service-not-allowed':
          return 'Trình duyệt chưa được cấp quyền micro. Hãy cho phép quyền microphone rồi thử lại.';
        case 'audio-capture':
          return 'Không tìm thấy micro khả dụng trên thiết bị.';
        case 'no-speech':
          return 'Không nhận được giọng nói. Bạn hãy thử nói rõ hơn.';
        case 'network':
          return 'Lỗi mạng khi nhận diện giọng nói. Vui lòng thử lại.';
        case 'aborted':
          return 'Nhận diện giọng nói đã dừng.';
        default:
          return 'Không thể nhận diện giọng nói trên trình duyệt hiện tại.';
      }
    } catch (_) {
      return 'Không thể nhận diện giọng nói trên trình duyệt hiện tại.';
    }
  }

  dynamic _property(dynamic object, String name) {
    if (object == null) {
      return null;
    }

    if (object is js.JsObject) {
      return object[name];
    }

    if (object is js.JsArray && name == 'length') {
      return object.length;
    }

    if (object is Map) {
      return object[name];
    }

    try {
      final jsObject = js.JsObject.fromBrowserObject(object);
      return jsObject[name];
    } catch (_) {
      return null;
    }
  }

  dynamic _index(dynamic object, int index) {
    if (object == null || index < 0) {
      return null;
    }

    if (object is List) {
      if (index >= object.length) {
        return null;
      }
      return object[index];
    }

    if (object is js.JsArray) {
      if (index >= object.length) {
        return null;
      }
      return object[index];
    }

    final valueByString = _property(object, index.toString());
    if (valueByString != null) {
      return valueByString;
    }

    try {
      final jsObject = js.JsObject.fromBrowserObject(object);
      return jsObject[index];
    } catch (_) {
      return null;
    }
  }

  int _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }
}

WebSpeechToText createWebSpeechToText() => _BrowserWebSpeechToText();
