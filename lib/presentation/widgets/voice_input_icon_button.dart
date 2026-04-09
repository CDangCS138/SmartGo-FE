import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/services/web_speech_to_text.dart';

class VoiceInputIconButton extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onTextChanged;
  final bool appendToExistingText;
  final String tooltip;
  final String stopTooltip;
  final String unavailableMessage;
  final String errorMessage;
  final Color? iconColor;

  const VoiceInputIconButton({
    super.key,
    required this.controller,
    this.onTextChanged,
    this.appendToExistingText = true,
    this.tooltip = 'Nhập bằng giọng nói',
    this.stopTooltip = 'Dừng nhập giọng nói',
    this.unavailableMessage = 'Thiết bị chưa hỗ trợ nhập liệu bằng giọng nói.',
    this.errorMessage =
        'Không thể nhận diện giọng nói. Vui lòng thử lại trong môi trường yên tĩnh hơn.',
    this.iconColor,
  });

  @override
  State<VoiceInputIconButton> createState() => _VoiceInputIconButtonState();
}

class _VoiceInputIconButtonState extends State<VoiceInputIconButton> {
  final SpeechToText _speechToText = SpeechToText();
  final WebSpeechToText _webSpeechToText = createWebSpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;
  bool _hasShownUnavailableMessage = false;
  String _baseText = '';
  String? _resolvedLocaleId;

  @override
  void dispose() {
    if (kIsWeb) {
      _webSpeechToText.stopListening();
    } else {
      _speechToText.stop();
    }
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
      return;
    }
    await _startListening();
  }

  Future<bool> _ensureInitialized() async {
    if (_isInitialized) {
      return kIsWeb ? _webSpeechToText.isSupported : _speechToText.isAvailable;
    }

    if (kIsWeb) {
      _isInitialized = true;
      return _webSpeechToText.isSupported;
    }

    try {
      final available = await _speechToText.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        debugLogging: false,
      );

      _isInitialized = true;
      return available;
    } on MissingPluginException {
      _isInitialized = true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startListening() async {
    final isAvailable = await _ensureInitialized();
    if (!isAvailable) {
      _showUnavailableMessage();
      return;
    }

    _baseText = widget.controller.text.trim();

    if (kIsWeb) {
      await _startListeningOnWeb();
      return;
    }

    try {
      final localeId = await _resolveLocaleId();

      final started = await _speechToText.listen(
        onResult: _handleResult,
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
        listenFor: const Duration(seconds: 55),
        pauseFor: const Duration(seconds: 5),
      );

      if (!mounted) {
        return;
      }

      if (!started) {
        _showUnavailableMessage();
        return;
      }

      _hasShownUnavailableMessage = false;
      setState(() => _isListening = true);
    } on MissingPluginException {
      _showUnavailableMessage();
    } catch (_) {
      _showMessage(widget.errorMessage);
    }
  }

  Future<void> _startListeningOnWeb() async {
    final started = await _webSpeechToText.startListening(
      localeId: 'vi-VN',
      partialResults: true,
      onStatus: _handleStatus,
      onError: (errorMessage) {
        if (!mounted) {
          return;
        }

        setState(() => _isListening = false);
        _showMessage(errorMessage);
      },
      onResult: (recognizedText, isFinal) {
        if (!mounted) {
          return;
        }

        final mergedText = _mergeText(_baseText, recognizedText.trim());
        widget.controller.value = TextEditingValue(
          text: mergedText,
          selection: TextSelection.collapsed(offset: mergedText.length),
          composing: TextRange.empty,
        );
        widget.onTextChanged?.call(mergedText);

        if (isFinal) {
          setState(() => _isListening = false);
        }
      },
    );

    if (!mounted) {
      return;
    }

    if (!started) {
      _showUnavailableMessage();
      return;
    }

    _hasShownUnavailableMessage = false;
    setState(() => _isListening = true);
  }

  Future<void> _stopListening() async {
    try {
      if (kIsWeb) {
        await _webSpeechToText.stopListening();
      } else {
        await _speechToText.stop();
      }
    } on MissingPluginException {
      _showUnavailableMessage();
    } catch (_) {
      _showMessage(widget.errorMessage);
    }

    if (!mounted) {
      return;
    }

    setState(() => _isListening = false);
  }

  Future<String?> _resolveLocaleId() async {
    if (_resolvedLocaleId != null) {
      return _resolvedLocaleId;
    }

    List<LocaleName> locales;
    try {
      locales = await _speechToText.locales();
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }

    if (locales.isEmpty) {
      return null;
    }

    const preferredPrefixes = ['vi', 'en'];
    for (final prefix in preferredPrefixes) {
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith(prefix)) {
          _resolvedLocaleId = locale.localeId;
          return _resolvedLocaleId;
        }
      }
    }

    _resolvedLocaleId = locales.first.localeId;
    return _resolvedLocaleId;
  }

  void _handleResult(SpeechRecognitionResult result) {
    final recognizedText = result.recognizedWords.trim();
    final mergedText = _mergeText(_baseText, recognizedText);

    widget.controller.value = TextEditingValue(
      text: mergedText,
      selection: TextSelection.collapsed(offset: mergedText.length),
      composing: TextRange.empty,
    );
    widget.onTextChanged?.call(mergedText);

    if (result.finalResult && mounted) {
      setState(() => _isListening = false);
    }
  }

  void _handleStatus(String status) {
    if (!mounted) {
      return;
    }

    final normalized = status.toLowerCase();
    if (normalized == 'listening') {
      if (!_isListening) {
        setState(() => _isListening = true);
      }
      return;
    }

    if (normalized.contains('done') || normalized.contains('notlistening')) {
      if (_isListening) {
        setState(() => _isListening = false);
      }
    }
  }

  void _handleError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }

    setState(() => _isListening = false);

    if (error.errorMsg.isNotEmpty) {
      _showMessage(widget.errorMessage);
    }
  }

  String _mergeText(String baseText, String recognizedText) {
    if (recognizedText.isEmpty) {
      return baseText;
    }

    if (!widget.appendToExistingText || baseText.isEmpty) {
      return recognizedText;
    }

    if (recognizedText.toLowerCase().startsWith(baseText.toLowerCase())) {
      return recognizedText;
    }

    return '$baseText $recognizedText';
  }

  String get _platformUnavailableMessage {
    if (kIsWeb) {
      return 'Trình duyệt hiện tại chưa hỗ trợ nhập giọng nói. Hãy dùng Chrome hoặc Edge và cấp quyền microphone.';
    }
    return widget.unavailableMessage;
  }

  void _showUnavailableMessage() {
    if (_hasShownUnavailableMessage) {
      return;
    }
    _hasShownUnavailableMessage = true;
    _showMessage(_platformUnavailableMessage);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _isListening ? widget.stopTooltip : widget.tooltip,
      onPressed: _toggleListening,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: child,
        ),
        child: _isListening
            ? const Icon(
                Icons.mic_rounded,
                key: ValueKey('listening'),
                color: Colors.red,
              )
            : Icon(
                Icons.mic_none_rounded,
                key: const ValueKey('idle'),
                color: widget.iconColor,
              ),
      ),
    );
  }
}
