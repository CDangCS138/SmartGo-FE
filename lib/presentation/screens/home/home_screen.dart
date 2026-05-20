import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../domain/entities/route.dart';
import '../../../core/constants/ui_constants.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/route/route_bloc.dart';
import '../../blocs/route/route_event.dart';
import '../../blocs/route/route_state.dart';
import '../../blocs/station/station_bloc.dart';
import '../../blocs/station/station_event.dart';
import '../../blocs/station/station_state.dart';
import '../route/route_detail_screen.dart';
import 'widgets/appear_motion.dart';
import 'widgets/live_map_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<Color> _routeColors = [
    Color(0xFF0F9B8E),
    Color(0xFF2563EB),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshHomeData(initialLoad: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final routeState = context.watch<RouteBloc>().state;

    final greetingName =
        authState is AuthAuthenticated ? authState.user.name : 'Khách';

    final routes = _extractRoutes(routeState);

    return Scaffold(
      backgroundColor: UIConstants.scaffoldBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHeader(greetingName),
                _buildSearch(),
                _buildFavoriteRoutesShortcut(),
                _buildShortcuts(),
                _buildLiveMapPreview(),
                _buildPopularRoutes(routes),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  List<BusRoute> _extractRoutes(RouteState state) {
    if (state is RouteLoaded) {
      return state.routes;
    }
    if (state is RouteLoadingMore) {
      return state.currentRoutes;
    }
    return const <BusRoute>[];
  }

  void _refreshHomeData({bool initialLoad = false}) {
    final routeBloc = context.read<RouteBloc>();
    final stationBloc = context.read<StationBloc>();

    if (initialLoad) {
      if (routeBloc.state is! RouteLoaded &&
          routeBloc.state is! RouteLoading &&
          routeBloc.state is! RouteLoadingMore) {
        routeBloc.add(const FetchAllRoutesEvent(page: 1, limit: 200));
      }

      if (stationBloc.state is! StationLoaded &&
          stationBloc.state is! StationLoading) {
        stationBloc.add(const FetchAllStationsEvent(page: 1, limit: 5000));
      }
      return;
    }

    routeBloc.add(const RefreshRoutesEvent());
    stationBloc
        .add(const FetchAllStationsEvent(page: 1, limit: 5000, refresh: true));
  }

  Widget _buildHeader(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Xin chào 👋',
                style: TextStyle(
                  color: UIConstants.textSecondary,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Bạn đi đâu hôm nay?',
                style: TextStyle(
                  color: UIConstants.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push(AppRoutes.notifications),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                    border: Border.all(color: UIConstants.borderLight),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        color: UIConstants.textSecondary,
                        size: 20,
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: UIConstants.tealLight,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.go(AppRoutes.profile),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                    border: Border.all(color: UIConstants.borderLight),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: UIConstants.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: GestureDetector(
        onTap: () => context.go(AppRoutes.routePlanning),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: UIConstants.mediumShadow,
            border: Border.all(color: UIConstants.borderLight),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: UIConstants.primaryTeal,
                size: 20,
              ),
              SizedBox(width: 12),
              Text(
                'Tìm tuyến, trạm hoặc địa điểm…',
                style: TextStyle(
                  color: UIConstants.textMuted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteRoutesShortcut() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => context.go(AppRoutes.favoriteRoutes),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: UIConstants.mediumShadow,
            border: Border.all(color: UIConstants.borderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: UIConstants.favoriteBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.favorite_border,
                  color: UIConstants.favoriteFg,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tuyến yêu thích',
                      style: TextStyle(
                        color: UIConstants.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Mở nhanh các lộ trình đã lưu',
                      style: TextStyle(
                        color: UIConstants.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: UIConstants.iconMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcuts() {
    final shortcuts = [
      _buildShortcutItem(
        icon: Icons.route_outlined,
        label: 'Tìm đường',
        bg: UIConstants.routeBg,
        fg: UIConstants.routeFg,
        onTap: () => context.go(AppRoutes.pathFindingDemo),
      ),
      _buildShortcutItem(
        icon: Icons.map_outlined,
        label: 'Bản đồ',
        bg: UIConstants.mapBg,
        fg: UIConstants.mapFg,
        onTap: () => context.go(AppRoutes.liveMap),
      ),
      _buildShortcutItem(
        icon: Icons.receipt_long_outlined,
        label: 'Vé của tôi',
        bg: UIConstants.billsBg,
        fg: UIConstants.billsFg,
        onTap: () => context.go(AppRoutes.bills),
      ),
      _buildShortcutItem(
        icon: Icons.list_alt_rounded,
        label: 'Tuyến xe',
        bg: UIConstants.routesBg,
        fg: UIConstants.routesFg,
        onTap: () => context.go(AppRoutes.routes),
      ),
      _buildShortcutItem(
        icon: Icons.auto_awesome_outlined,
        label: 'Trợ lý AI',
        bg: UIConstants.aiBg,
        fg: UIConstants.aiFg,
        onTap: () => context.go(AppRoutes.chatbot),
      ),
      _buildShortcutItem(
        icon: Icons.directions_bus_outlined,
        label: 'Bus',
        bg: UIConstants.busBg,
        fg: UIConstants.busFg,
        onTap: () => context.go(AppRoutes.busSimulations),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: GridView.count(
        padding: EdgeInsets.zero,
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: shortcuts,
      ),
    );
  }

  Widget _buildShortcutItem({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 8,
          horizontal: 4,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: UIConstants.borderLight),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: fg, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: UIConstants.textPrimary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMapPreview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bản đồ trực tiếp',
                style: TextStyle(
                  color: UIConstants.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              GestureDetector(
                onTap: () => context.go(AppRoutes.liveMap),
                child: const Text(
                  'Mở rộng',
                  style: TextStyle(
                    color: UIConstants.primaryTeal,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const AppearMotion(
            delay: Duration(milliseconds: 170),
            child: LiveMapCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularRoutes(List<BusRoute> routes) {
    final validRoutes = routes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tuyến xe buýt phổ biến',
                style: TextStyle(
                  color: UIConstants.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              GestureDetector(
                onTap: () => context.go(AppRoutes.routes),
                child: const Text(
                  'Xem tất cả',
                  style: TextStyle(
                    color: UIConstants.primaryTeal,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (validRoutes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Chưa có dữ liệu tuyến',
                style: TextStyle(color: UIConstants.textSecondary),
              ),
            )
          else
            ...validRoutes.take(5).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final route = entry.value;
              final color = _routeColors[index % _routeColors.length];
              return AppearMotion(
                delay: Duration(milliseconds: 100 + (index * 20)),
                child: _buildPopularRouteCard(route, color),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPopularRouteCard(BusRoute route, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RouteDetailScreen(route: route),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: UIConstants.softShadow,
          border: Border.all(color: UIConstants.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                route.routeCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.routeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: UIConstants.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: UIConstants.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sắp đến • ${route.tripTime}',
                        style: const TextStyle(
                          color: UIConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        ' • ',
                        style: TextStyle(
                          color: UIConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${route.totalDistance} km',
                        style: const TextStyle(
                          color: UIConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: UIConstants.iconMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
