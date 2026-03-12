import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routes/app_routes.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on,
                  size: 60,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SmartGo',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Smart Urban Transportation',
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 60),
              _buildFeature(
                context: context,
                icon: Icons.location_on_outlined,
                title: 'Tối ưu hóa hành trình của bạn',
                description:
                    'Tìm hiểu thời gian đến tin hiệu thực tế và tránh tắc đường với dữ liệu giao thông trực tiếp.',
              ),
              const SizedBox(height: 24),
              _buildFeature(
                context: context,
                icon: Icons.directions_outlined,
                title: 'Tích hợp đa phương thức',
                description:
                    'Kết hợp xe buýt, tàu điện ngầm và đi bộ để có hành trình hiệu quả nhất.',
              ),
              const SizedBox(height: 24),
              _buildFeature(
                context: context,
                icon: Icons.access_time_outlined,
                title: 'Thông tin thời gian thực',
                description:
                    'Nhận cập nhật trực tiếp về vị trí xe buýt, tình trạng đến tin hiệu và tình hình giao thông.',
              ),
              const SizedBox(height: 24),
              _buildFeature(
                context: context,
                icon: Icons.people_outline,
                title: 'Cộng đồng thông minh',
                description:
                    'Cùng nhau cải thiện giao thông đô thị cho mọi người',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.home),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Bắt đầu',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.primary, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
