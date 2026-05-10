import 'package:flutter/material.dart';

class UIConstants {
  // Backgrounds
  static const Color scaffoldBackground = Color(0xFFF8FAFC);
  static const Color cardBackground = Colors.white;

  // Text Colors
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  // Primary Teal Theme
  static const Color primaryTeal = Color(0xFF0D9488);
  static const Color tealLight = Color(0xFF14B8A6);
  static const Color tealDark = Color(0xFF0F766E);

  // Status/Action Colors
  static const Color danger = Color(0xFFE11D48);

  // Icons & Borders
  static const Color borderLight = Color(0xFFF1F5F9);
  static const Color iconMuted = Color(0xFFCBD5E1);

  // Shortcut Colors
  static const Color routeBg = Color(0xFFF0FDFA);
  static const Color routeFg = Color(0xFF0D9488);

  static const Color mapBg = Color(0xFFEFF6FF);
  static const Color mapFg = Color(0xFF2563EB);

  static const Color aiBg = Color(0xFFF5F3FF);
  static const Color aiFg = Color(0xFF7C3AED);

  static const Color busBg = Color(0xFFFFFBEB);
  static const Color busFg = Color(0xFFD97706);

  // Shadows
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 16,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> mediumShadow = [
    BoxShadow(
      color: Color(0x0F0F172A),
      blurRadius: 24,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> navShadow = [
    BoxShadow(
      color: Color(0x1A0F172A),
      blurRadius: 40,
      offset: Offset(0, 8),
    ),
  ];
}
