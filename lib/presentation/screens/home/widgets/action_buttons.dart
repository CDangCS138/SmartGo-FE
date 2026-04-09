import 'package:flutter/material.dart';

import 'motion_tap.dart';

class ActionButtons extends StatelessWidget {
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  const ActionButtons({
    super.key,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;

        if (isCompact) {
          return Column(
            children: [
              _PrimaryGradientButton(
                text: 'Tìm đường tối ưu',
                icon: Icons.auto_graph_rounded,
                onTap: onPrimaryTap,
              ),
              const SizedBox(height: 12),
              _SecondarySoftButton(
                text: 'Lập lộ trình',
                icon: Icons.alt_route_rounded,
                onTap: onSecondaryTap,
                color: scheme,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _PrimaryGradientButton(
                text: 'Tìm đường tối ưu',
                icon: Icons.auto_graph_rounded,
                onTap: onPrimaryTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SecondarySoftButton(
                text: 'Lập lộ trình',
                icon: Icons.alt_route_rounded,
                onTap: onSecondaryTap,
                color: scheme,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PrimaryGradientButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryGradientButton({
    required this.text,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MotionTap(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      builder: (context, isPressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0x1F0F766E)
                  .withValues(alpha: isPressed ? 0.22 : 0.45),
              blurRadius: isPressed ? 5 : 9,
              offset: Offset(0, isPressed ? 1 : 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondarySoftButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme color;

  const _SecondarySoftButton({
    required this.text,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return MotionTap(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      builder: (context, isPressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: color.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPressed
                ? color.primary.withValues(alpha: 0.35)
                : color.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: color.shadow.withValues(alpha: isPressed ? 0.01 : 0.025),
              blurRadius: isPressed ? 3 : 6,
              offset: Offset(0, isPressed ? 1 : 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color.primary),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: color.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
