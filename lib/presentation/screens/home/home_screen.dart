import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../domain/entities/route.dart';
import '../../../domain/entities/station.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/route/route_bloc.dart';
import '../../blocs/route/route_event.dart';
import '../../blocs/route/route_state.dart';
import '../../blocs/station/station_bloc.dart';
import '../../blocs/station/station_event.dart';
import '../../blocs/station/station_state.dart';
import 'widgets/action_buttons.dart';
import 'widgets/appear_motion.dart';
import 'widgets/header_card.dart';
import 'widgets/home_navigation_bar.dart';
import 'widgets/live_map_card.dart';
import 'widgets/route_card.dart';
import 'widgets/search_pill_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshHomeData(initialLoad: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final authState = context.watch<AuthBloc>().state;
    final routeState = context.watch<RouteBloc>().state;
    final stationState = context.watch<StationBloc>().state;

    final greetingName =
        authState is AuthAuthenticated ? authState.user.name : 'Super Admin';

    final routes = _extractRoutes(routeState);
    final activeStations = stationState is StationLoaded
        ? stationState.stations
            .where((s) => s.status == StationStatus.ACTIVE)
            .toList()
        : const <Station>[];

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  AppearMotion(
                    delay: const Duration(milliseconds: 20),
                    child: HeaderCard(
                      title: 'Xin chào, $greetingName',
                      subtitle:
                          'Theo dõi vận hành thông minh, tối ưu lộ trình theo thời gian thực.',
                      routesCount: routes.length,
                      stationsCount: activeStations.length,
                      onNotificationTap: () {},
                      onProfileTap: () => context.push(AppRoutes.profile),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppearMotion(
                    delay: const Duration(milliseconds: 80),
                    child: SearchPillBar(
                      hint: 'Tìm điểm đi, điểm đến hoặc mã trạm...',
                      onTap: () => context.go(AppRoutes.routePlanning),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppearMotion(
                    delay: const Duration(milliseconds: 120),
                    child: ActionButtons(
                      onPrimaryTap: () => context.go(AppRoutes.pathFindingDemo),
                      onSecondaryTap: () => context.go(AppRoutes.routePlanning),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppearMotion(
                    delay: const Duration(milliseconds: 145),
                    child: FilledButton.tonalIcon(
                      onPressed: () => context.go(AppRoutes.chatbot),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: const Text('Hỏi SmartGo AI Assistant'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppearMotion(
                    delay: const Duration(milliseconds: 170),
                    child: LiveMapCard(
                      stations: activeStations,
                      onTapViewAll: () => context.go(AppRoutes.liveMap),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _buildSectionHeader(
                    title: 'Tuyến đang hoạt động',
                    actionText: 'Xem tất cả',
                    onTap: () => context.go(AppRoutes.routes),
                  ),
                  const SizedBox(height: 14),
                  if (routes.isEmpty)
                    AppearMotion(
                      delay: const Duration(milliseconds: 210),
                      child: _buildEmptyState(
                        title: 'Chưa có dữ liệu tuyến',
                        subtitle:
                            'Hệ thống đang đồng bộ dữ liệu. Vui lòng thử lại sau.',
                      ),
                    )
                  else
                    ...routes.take(8).toList().asMap().entries.map(
                          (entry) => AppearMotion(
                            delay:
                                Duration(milliseconds: 220 + (entry.key * 24)),
                            child: RouteCard(
                              route: entry.value,
                              onTap: () => context.go(AppRoutes.routes),
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                  AppearMotion(
                    delay: const Duration(milliseconds: 260),
                    child: OutlinedButton.icon(
                      onPressed: _refreshHomeData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Làm mới dữ liệu'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: HomeNavigationBar(
        currentIndex: 0,
        onDestinationSelected: (index) {
          if (index == 0) {
            return;
          }
          if (index == 1) {
            context.go(AppRoutes.routePlanning);
            return;
          }
          context.go(AppRoutes.liveMap);
        },
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
        routeBloc.add(const FetchAllRoutesEvent(page: 1, limit: 20));
      }

      if (stationBloc.state is! StationLoaded &&
          stationBloc.state is! StationLoading) {
        stationBloc.add(const FetchAllStationsEvent(page: 1, limit: 50));
      }
      return;
    }

    routeBloc.add(const RefreshRoutesEvent());
    stationBloc
        .add(const FetchAllStationsEvent(page: 1, limit: 50, refresh: true));
  }

  Widget _buildSectionHeader({
    required String title,
    required String actionText,
    required VoidCallback onTap,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        TextButton(
          onPressed: onTap,
          child: Text(actionText),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
