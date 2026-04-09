import 'package:flutter/material.dart';

class MotionTap extends StatefulWidget {
  final Widget Function(BuildContext context, bool isPressed) builder;
  final VoidCallback? onTap;
  final Duration duration;
  final double pressedScale;
  final BorderRadius borderRadius;

  const MotionTap({
    super.key,
    required this.builder,
    this.onTap,
    this.duration = const Duration(milliseconds: 140),
    this.pressedScale = 0.985,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  State<MotionTap> createState() => _MotionTapState();
}

class _MotionTapState extends State<MotionTap> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value) {
      return;
    }
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      scale: _isPressed ? widget.pressedScale : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          child: widget.builder(context, _isPressed),
        ),
      ),
    );
  }
}
