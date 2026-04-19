import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:smartgo/core/routes/app_routes.dart';
import 'package:smartgo/domain/entities/route.dart';
import 'package:smartgo/presentation/blocs/route/route_bloc.dart';
import 'package:smartgo/presentation/blocs/route/route_event.dart';
import 'package:smartgo/presentation/blocs/route/route_state.dart';
import 'package:smartgo/presentation/screens/route/route_detail_screen.dart';
import 'package:smartgo/presentation/widgets/loading_indicator.dart';

class RouteListScreen extends StatefulWidget {
  const RouteListScreen({super.key});

  @override
  State<RouteListScreen> createState() => _RouteListScreenState();
}

class _RouteListScreenState extends State<RouteListScreen> {
  final ScrollController _scrollController = ScrollController();
  RouteDirection _selectedDirection = RouteDirection.both;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Always fetch all routes on enter (legacy behavior).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RouteBloc>().add(
            FetchAllRoutesEvent(
              limit: 200,
              direction: _selectedDirection,
              routeCode: '',
            ),
          );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<RouteBloc>().add(const LoadMoreRoutesEvent());
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _onDirectionChanged(RouteDirection? direction) {
    if (direction == null || direction == _selectedDirection) {
      return;
    }

    setState(() {
      _selectedDirection = direction;
    });

    context.read<RouteBloc>().add(
          FetchAllRoutesEvent(
            page: 1,
            limit: 200,
            direction: direction,
            routeCode: '',
          ),
        );
  }

  void _refreshRoutes() {
    context.read<RouteBloc>().add(
          RefreshRoutesEvent(
            direction: _selectedDirection,
            routeCode: '',
          ),
        );
  }

  void _onRouteSelected(BusRoute route) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RouteDetailScreen(route: route),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tuyến Xe Buýt'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
        actions: [
          PopupMenuButton<RouteDirection>(
            icon: const Icon(Icons.filter_list),
            onSelected: _onDirectionChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: RouteDirection.both,
                child: Text('Cả hai chiều'),
              ),
              PopupMenuItem(
                value: RouteDirection.forward,
                child: Text('Chiều đi'),
              ),
              PopupMenuItem(
                value: RouteDirection.backward,
                child: Text('Chiều về'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshRoutes,
          ),
        ],
      ),
      body: BlocBuilder<RouteBloc, RouteState>(
        builder: (context, state) {
          if (state is RouteLoading) {
            return const LoadingIndicator();
          }

          if (state is RouteError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: scheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshRoutes,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          if (state is RouteLoaded || state is RouteLoadingMore) {
            final routes = state is RouteLoaded
                ? state.routes
                : (state as RouteLoadingMore).currentRoutes;
            final totalCount =
                state is RouteLoaded ? state.totalCount : routes.length;

            if (routes.isEmpty) {
              return Center(
                child: Text(
                  'Không có tuyến xe buýt nào',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: scheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_bus,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hiển thị ${routes.length}/$totalCount tuyến',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _getDirectionText(),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: routes.length +
                        (state is RouteLoadingMore ||
                                (state is RouteLoaded && state.hasMorePages)
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index >= routes.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: LoadingIndicator(size: 28),
                          ),
                        );
                      }

                      final route = routes[index];
                      return _buildRouteCard(route);
                    },
                  ),
                ),
              ],
            );
          }

          return const Center(child: Text('Chọn tuyến để xem chi tiết'));
        },
      ),
    );
  }

  String _getDirectionText() {
    switch (_selectedDirection) {
      case RouteDirection.forward:
        return 'Chiều đi';
      case RouteDirection.backward:
        return 'Chiều về';
      case RouteDirection.both:
        return 'Cả hai chiều';
    }
  }

  Widget _buildRouteCard(BusRoute route) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => _onRouteSelected(route),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route code and status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      route.routeCode,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(route.status),
                  const Spacer(),
                  if (route.isWheelchairAccessible)
                    Icon(Icons.accessible, color: scheme.primary, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              // Route name
              Text(
                route.routeName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              // Start and end points
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      route.startPoint,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: scheme.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      route.endPoint,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Additional info
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildInfoChip(
                    Icons.access_time,
                    '${route.operatingTime.from} - ${route.operatingTime.to}',
                  ),
                  _buildInfoChip(Icons.timer, route.tripTime),
                  _buildInfoChip(Icons.straighten, '${route.totalDistance} km'),
                  _buildInfoChip(Icons.schedule, route.frequency),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(RouteStatus status) {
    Color color;
    String text;

    switch (status) {
      case RouteStatus.active:
        color = Colors.green;
        text = 'Hoạt động';
        break;
      case RouteStatus.inactive:
        color = Colors.grey;
        text = 'Ngừng';
        break;
      case RouteStatus.underMaintenance:
        color = Colors.orange;
        text = 'Bảo trì';
        break;
      case RouteStatus.suspended:
        color = Colors.red;
        text = 'Tạm dừng';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
