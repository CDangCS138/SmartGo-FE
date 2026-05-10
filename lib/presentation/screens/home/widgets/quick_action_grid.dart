import 'package:flutter/material.dart';
import 'motion_tap.dart';

class QuickActionGrid extends StatelessWidget {
  final VoidCallback onPathFindingTap;
  final VoidCallback onLiveMapTap;
  final VoidCallback onChatbotTap;
  final VoidCallback onBusSimulationTap;

  const QuickActionGrid({
    super.key,
    required this.onPathFindingTap,
    required this.onLiveMapTap,
    required this.onChatbotTap,
    required this.onBusSimulationTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ActionItem(
              icon: Icons.directions_rounded,
              label: 'Tìm đường',
              color: const Color(0xFF2563EB), // Blue
              onTap: onPathFindingTap,
            ),
            _ActionItem(
              icon: Icons.map_rounded,
              label: 'Bản đồ',
              color: const Color(0xFF0F766E), // Teal
              onTap: onLiveMapTap,
            ),
            _ActionItem(
              icon: Icons.smart_toy_rounded,
              label: 'Trợ lý AI',
              color: const Color(0xFF9333EA), // Purple
              onTap: onChatbotTap,
            ),
            _ActionItem(
              icon: Icons.directions_bus_rounded,
              label: 'Bus',
              color: const Color(0xFFEA580C), // Orange
              onTap: onBusSimulationTap,
            ),
          ],
        );
      },
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MotionTap(
      onTap: onTap,
      builder: (context, isPressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.diagonal3Values(
            isPressed ? 0.95 : 1.0, isPressed ? 0.95 : 1.0, 1.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
