import 'package:flutter/material.dart';

import 'tts_icon_button.dart';
import 'voice_input_icon_button.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final String? Function(String?)? validator;
  final bool enableTts;
  final bool enableVoiceInput;
  final String ttsTooltip;
  final String ttsEmptyMessage;
  final String voiceInputTooltip;
  final String voiceInputUnavailableMessage;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.validator,
    this.enableTts = false,
    this.enableVoiceInput = false,
    this.ttsTooltip = 'Đọc nội dung ô nhập',
    this.ttsEmptyMessage = 'Ô nhập hiện chưa có nội dung để đọc.',
    this.voiceInputTooltip = 'Nhập bằng giọng nói',
    this.voiceInputUnavailableMessage =
        'Thiết bị chưa hỗ trợ nhập liệu bằng giọng nói.',
  });

  @override
  Widget build(BuildContext context) {
    final suffixActions = <Widget>[];

    if (enableVoiceInput && controller != null) {
      suffixActions.add(
        VoiceInputIconButton(
          controller: controller!,
          tooltip: voiceInputTooltip,
          unavailableMessage: voiceInputUnavailableMessage,
          onTextChanged: onChanged,
        ),
      );
    }

    if (enableTts && controller != null) {
      suffixActions.add(
        TtsIconButton(
          controller: controller!,
          tooltip: ttsTooltip,
          emptyMessage: ttsEmptyMessage,
        ),
      );
    }

    if (suffixIcon != null) {
      suffixActions.add(suffixIcon!);
    }

    final hasSuffixActions = suffixActions.isNotEmpty;
    final suffixWidth = hasSuffixActions
        ? (44.0 * suffixActions.length).clamp(44.0, 180.0)
        : 0.0;

    final resolvedSuffix = !hasSuffixActions
        ? null
        : SizedBox(
            width: suffixWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: suffixActions,
            ),
          );

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      onTap: onTap,
      readOnly: readOnly,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIconConstraints: hasSuffixActions
            ? const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
                maxWidth: 180,
              )
            : null,
        suffixIcon: resolvedSuffix,
      ),
    );
  }
}
