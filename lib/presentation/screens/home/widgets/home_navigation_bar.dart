import 'package:flutter/material.dart';

class HomeNavigationBar extends StatelessWidget {
  static final ValueNotifier<bool> isVisible = ValueNotifier<bool>(true);
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const HomeNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x190F172A),
                blurRadius: 40,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavBarItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Trang chủ',
                  isActive: currentIndex == 0,
                  onTap: () => onDestinationSelected(0),
                ),
                _NavBarItem(
                  icon: Icons.search_rounded,
                  activeIcon: Icons.search_rounded,
                  label: 'Tìm đường',
                  isActive: currentIndex == 1,
                  onTap: () => onDestinationSelected(1),
                ),
                _NavBarItem(
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map_rounded,
                  label: 'Bản đồ',
                  isActive: currentIndex == 2,
                  onTap: () => onDestinationSelected(2),
                ),
                _NavBarItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Tài khoản',
                  isActive: currentIndex == 3,
                  onTap: () => onDestinationSelected(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      isActive ? const Color(0xFF0D9488) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: isActive
                      ? const [
                          BoxShadow(
                            color: Color(0x590F9B8E),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  isActive ? activeIcon : icon,
                  size: 18,
                  color: isActive ? Colors.white : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF94A3B8),
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
