import 'dart:async';

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
  final TextEditingController _routeSearchController = TextEditingController();

  Timer? _routeSearchDebounce;
  RouteDirection _selectedDirection = RouteDirection.both;
  String _routeSearchQuery = '';

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
              routeCode: _routeSearchQuery,
            ),
          );
    });
  }

  @override
  void dispose() {
    _routeSearchDebounce?.cancel();
    _routeSearchController.dispose();
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
            routeCode: _routeSearchQuery,
          ),
        );
  }

  void _refreshRoutes() {
    context.read<RouteBloc>().add(
          RefreshRoutesEvent(
            direction: _selectedDirection,
            routeCode: _routeSearchQuery,
          ),
        );
  }

  void _onRouteSearchChanged(String _) {
    _routeSearchDebounce?.cancel();
    _routeSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      _triggerRouteSearch,
    );
  }

  void _triggerRouteSearch() {
    if (!mounted) {
      return;
    }

    final query = _routeSearchController.text.trim();
    if (query == _routeSearchQuery) {
      return;
    }

    setState(() {
      _routeSearchQuery = query;
    });

    context.read<RouteBloc>().add(
          FetchAllRoutesEvent(
            page: 1,
            limit: 200,
            direction: _selectedDirection,
            routeCode: _routeSearchQuery,
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
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 0,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.go(AppRoutes.home),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFF1F5F9)),
                            ),
                            child: const Icon(Icons.arrow_back,
                                size: 16, color: Color(0xFF334155)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Tuyến Xe Buýt',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    PopupMenuButton<RouteDirection>(
                      icon: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: const Icon(Icons.tune_rounded,
                            size: 16, color: Color(0xFF64748B)),
                      ),
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
                  ],
                ),
                const SizedBox(height: 12),
                // Search
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 18, color: Color(0xFF0D9488)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _routeSearchController,
                          onChanged: _onRouteSearchChanged,
                          onSubmitted: (_) => _triggerRouteSearch(),
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF1E293B)),
                          decoration: const InputDecoration(
                            hintText: 'Tìm theo mã tuyến (VD: 08, 150)…',
                            hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_routeSearchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _routeSearchController.clear();
                            _triggerRouteSearch();
                          },
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0xFF94A3B8)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<RouteBloc, RouteState>(
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
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_bus_rounded,
                              size: 48, color: Color(0xFFCBD5E1)),
                          SizedBox(height: 12),
                          Text('Không tìm thấy tuyến xe buýt',
                              style: TextStyle(
                                  color: Color(0xFF64748B), fontSize: 14)),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                    color: Color(0xFF64748B), fontSize: 12),
                                children: [
                                  const TextSpan(text: 'Hiển thị '),
                                  TextSpan(
                                    text: '${routes.length}',
                                    style: const TextStyle(
                                        color: Color(0xFF0F766E),
                                        fontWeight: FontWeight.w600),
                                  ),
                                  TextSpan(text: '/$totalCount tuyến'),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getDirectionText(),
                                  style: const TextStyle(
                                      color: Color(0xFF0D9488), fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: routes.length +
                              (state is RouteLoadingMore ||
                                      (state is RouteLoaded &&
                                          state.hasMorePages)
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
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: _buildRouteCard(route),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }

                return const Center(child: Text('Chọn tuyến để xem chi tiết'));
              },
            ),
          ),
        ],
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

  Color _getRouteColor(String code) {
    final colors = [
      const Color(0xFF0F9B8E), // teal
      const Color(0xFF2563EB), // blue
      const Color(0xFFF59E0B), // amber
      const Color(0xFF8B5CF6), // purple
      const Color(0xFFEC4899), // pink
    ];
    final hash = code.hashCode;
    return colors[hash % colors.length];
  }

  Widget _buildRouteCard(BusRoute route) {
    final routeColor = _getRouteColor(route.routeCode);

    return GestureDetector(
      onTap: () => _onRouteSelected(route),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F0F172A),
              blurRadius: 16,
              offset: Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 4, width: double.infinity, color: routeColor),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 40,
                        constraints: const BoxConstraints(minWidth: 40),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: routeColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          route.routeCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildStatusBadge(route.status),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded,
                          color: Color(0xFFCBD5E1), size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    route.routeName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                              color: const Color(0xFF14B8A6), width: 2),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: Color(0xFF14B8A6), shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(route.startPoint,
                            style: const TextStyle(
                                color: Color(0xFF64748B), fontSize: 13)),
                      ),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 7.5, top: 4, bottom: 4),
                    width: 1,
                    height: 12,
                    color: const Color(0xFFE2E8F0),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place_rounded,
                          size: 16, color: Color(0xFFFB7185)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(route.endPoint,
                            style: const TextStyle(
                                color: Color(0xFF64748B), fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFF8FAFC)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildInfoChip(Icons.schedule_rounded,
                          '${route.operatingTime.from} - ${route.operatingTime.to}'),
                      _buildInfoChip(Icons.timer_outlined, route.tripTime),
                      _buildInfoChip(Icons.straighten_rounded,
                          '${route.totalDistance} km'),
                      _buildInfoChip(Icons.repeat_rounded, route.frequency),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(RouteStatus status) {
    Color bgColor;
    Color fgColor;
    String text = 'Hoạt động';

    switch (status) {
      case RouteStatus.active:
        bgColor = const Color(0xFFECFDF5);
        fgColor = const Color(0xFF047857);
        break;
      case RouteStatus.inactive:
        bgColor = const Color(0xFFF1F5F9);
        fgColor = const Color(0xFF475569);
        text = 'Tạm ngừng';
        break;
      case RouteStatus.underMaintenance:
        bgColor = const Color(0xFFFFFBEB);
        fgColor = const Color(0xFFD97706);
        break;
      case RouteStatus.suspended:
        bgColor = const Color(0xFFFEF2F2);
        fgColor = const Color(0xFFBE123C);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fgColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: fgColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
