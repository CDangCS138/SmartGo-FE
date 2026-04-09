import 'package:flutter/material.dart';

import 'motion_tap.dart';

class SearchPillBar extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;

  const SearchPillBar({
    super.key,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MotionTap(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      builder: (context, isPressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isPressed
                ? scheme.primary.withValues(alpha: 0.32)
                : scheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: isPressed ? 0.015 : 0.04),
              blurRadius: isPressed ? 5 : 8,
              offset: Offset(0, isPressed ? 1 : 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.tune_rounded,
              color: scheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
