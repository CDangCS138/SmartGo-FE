import 'package:flutter/material.dart';

import 'map/map_icons.dart';

enum MarkerType { normal, start, end, selected, custom }

class MapStationMarker extends StatelessWidget {
  final MarkerType type;
  final String? label;
  final Color? customColor;
  final IconData? icon;
  final VoidCallback? onTap;

  const MapStationMarker({
    super.key,
    this.type = MarkerType.normal,
    this.label,
    this.customColor,
    this.icon,
    this.onTap,
  });

  Color get _bgColor {
    if (type == MarkerType.custom && customColor != null) {
      return customColor!;
    }
    switch (type) {
      case MarkerType.start:
        return const Color(0xFF22C55E); // Green
      case MarkerType.end:
        return const Color(0xFFEF4444); // Red
      case MarkerType.selected:
        return const Color(0xFF0D9488); // Teal
      case MarkerType.normal:
      default:
        return const Color(0xFF3B82F6); // Blue
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: label != null
              ? Text(
                  label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Icon(
                  icon ?? MapIcons.bus,
                  color: Colors.white,
                  size: 14,
                ),
        ),
      ),
    );
  }
}
