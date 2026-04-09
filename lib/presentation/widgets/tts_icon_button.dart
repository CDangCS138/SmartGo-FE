import 'package:flutter/material.dart';

import '../../core/services/text_to_speech_service.dart';

class TtsIconButton extends StatefulWidget {
  final TextEditingController? controller;
  final String? text;
  final String tooltip;
  final String emptyMessage;
  final String errorMessage;
  final Color? iconColor;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  const TtsIconButton({
    super.key,
    required this.controller,
    this.tooltip = 'Đọc văn bản',
    this.emptyMessage = 'Ô nhập hiện chưa có nội dung để đọc.',
    this.errorMessage = 'Thiết bị không hỗ trợ đọc văn bản lúc này.',
    this.iconColor,
    this.iconSize,
    this.padding,
    this.constraints,
  }) : text = null;

  const TtsIconButton.fromText({
    super.key,
    required this.text,
    this.tooltip = 'Đọc văn bản',
    this.emptyMessage = 'Ô nhập hiện chưa có nội dung để đọc.',
    this.errorMessage = 'Thiết bị không hỗ trợ đọc văn bản lúc này.',
    this.iconColor,
    this.iconSize,
    this.padding,
    this.constraints,
  }) : controller = null;

  @override
  State<TtsIconButton> createState() => _TtsIconButtonState();
}

class _TtsIconButtonState extends State<TtsIconButton> {
  bool _isSpeaking = false;

  @override
  void dispose() {
    TextToSpeechService.instance.stop();
    super.dispose();
  }

  Future<void> _speakCurrentText() async {
    final text = (widget.text ?? widget.controller?.text ?? '').trim();
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.emptyMessage)),
        );
      }
      return;
    }

    setState(() => _isSpeaking = true);
    final success = await TextToSpeechService.instance.speak(text);

    if (!mounted) {
      return;
    }

    setState(() => _isSpeaking = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.errorMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      iconSize: widget.iconSize,
      padding: widget.padding,
      constraints: widget.constraints,
      onPressed: _isSpeaking ? null : _speakCurrentText,
      icon: _isSpeaking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.volume_up_rounded, color: widget.iconColor),
    );
  }
}
