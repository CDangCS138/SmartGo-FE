import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/ui_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/services/storage_service.dart';
import '../../../data/datasources/favorite_routes_remote_data_source.dart';
import '../../../data/datasources/user_favorites_remote_data_source.dart';
import '../../../data/models/favorite_route_model.dart';
import '../../../data/models/route_model.dart';
import '../../../data/models/station_model.dart';
import '../../../domain/entities/path_finding.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../blocs/station/station_bloc.dart';
import '../../blocs/station/station_state.dart';
import '../../widgets/loading_indicator.dart';
import '../route/route_detail_screen.dart';
import '../station/station_detail_screen.dart';

class FavoriteRoutesScreen extends StatefulWidget {
  const FavoriteRoutesScreen({super.key});

  @override
  State<FavoriteRoutesScreen> createState() => _FavoriteRoutesScreenState();
}

class _FavoriteRoutesScreenState extends State<FavoriteRoutesScreen> {
  late final FavoriteRoutesRemoteDataSource _dataSource;
  late final UserFavoritesRemoteDataSource _favoritesDataSource;
  late final StorageService _storageService;
  bool _isLoading = false;
  String? _error;
  List<FavoriteRouteModel> _favorites = const [];
  List<RouteModel> _favoriteRoutes = const [];
  List<StationModel> _favoriteStations = const [];
  final Set<String> _deletingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _dataSource = FavoriteRoutesRemoteDataSource(client: getIt<http.Client>());
    _favoritesDataSource =
        UserFavoritesRemoteDataSource(client: getIt<http.Client>());
    _storageService = getIt<StorageService>();
    _loadFavorites();
  }

  Future<void> _loadFavorites({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _error = null;
      });
    }

    setState(() {
      _isLoading = true;
      if (!refresh) {
        _error = null;
      }
    });

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      setState(() {
        _favorites = const [];
        _isLoading = false;
        _error = 'Vui lòng đăng nhập để xem tuyến yêu thích.';
      });
      return;
    }

    try {
      final accessToken = _resolveAccessToken(authState);
      final user = await _favoritesDataSource.getUserById(
        userId: authState.user.id,
        accessToken: accessToken,
      );
      final favoriteIds = user.favoriteRouteIds;
      final orderedRoutes = _orderRoutesByIds(
        user.favoriteRoutes,
        user.favoriteRouteIds,
      );
      final orderedStations = _orderStationsByIds(
        user.favoriteStations,
        user.favoriteStationIds,
      );
      final resolvedRoutes =
          orderedRoutes.isNotEmpty ? orderedRoutes : user.favoriteRoutes;
      final resolvedStations =
          orderedStations.isNotEmpty ? orderedStations : user.favoriteStations;

      if (favoriteIds.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _favorites = const [];
          _favoriteRoutes = resolvedRoutes;
          _favoriteStations = resolvedStations;
          _isLoading = false;
        });
        return;
      }

      final response = await _dataSource.getFavoriteRoutes(
        page: 1,
        limit: 200,
      );
      if (!mounted) {
        return;
      }
      final favoritesById = {
        for (final item in response.data) item.id: item,
      };
      final orderedFavorites = <FavoriteRouteModel>[];
      for (final id in favoriteIds) {
        final match = favoritesById[id];
        if (match != null) {
          orderedFavorites.add(match);
        }
      }
      setState(() {
        _favorites = orderedFavorites;
        _favoriteRoutes = resolvedRoutes;
        _favoriteStations = resolvedStations;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteFavorite(FavoriteRouteModel favorite) async {
    if (_deletingIds.contains(favorite.id)) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xóa tuyến yêu thích'),
          content: Text('Bạn chắc chắn muốn xóa "${favorite.routeName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      _deletingIds.add(favorite.id);
    });

    try {
      if (!mounted) {
        return;
      }
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) {
        _showError('Vui lòng đăng nhập để xóa tuyến yêu thích.');
        return;
      }

      final accessToken = _resolveAccessToken(authState);
      final user = await _favoritesDataSource.getUserById(
        userId: authState.user.id,
        accessToken: accessToken,
      );
      final nextRouteIds = user.favoriteRouteIds.toSet()..remove(favorite.id);

      await _dataSource.deleteFavoriteRoute(id: favorite.id);
      await _favoritesDataSource.updateFavorites(
        userId: authState.user.id,
        favoriteRouteIds: nextRouteIds.toList(),
        favoriteStationIds: user.favoriteStationIds,
        accessToken: accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _favorites =
            _favorites.where((item) => item.id != favorite.id).toList();
      });
      _showInfo('Đã xóa tuyến yêu thích');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Không thể xóa: $error');
    } finally {
      if (!mounted) {
        // ignore: control_flow_in_finally
        return;
      }
      setState(() {
        _deletingIds.remove(favorite.id);
      });
    }
  }

  void _openFavorite(FavoriteRouteModel favorite) {
    context.go(AppRoutes.pathFindingDemo, extra: favorite);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _resolveStationLabel(String? stationCode, StationState stationState) {
    if (stationCode == null || stationCode.trim().isEmpty) {
      return 'Không rõ trạm';
    }

    if (stationState is StationLoaded) {
      for (final station in stationState.stations) {
        if (station.stationCode == stationCode || station.id == stationCode) {
          return station.stationName;
        }
      }
    }

    return stationCode;
  }

  String _formatCoordinates(PathCoordinates coordinates) {
    return '${coordinates.latitude.toStringAsFixed(5)}, ${coordinates.longitude.toStringAsFixed(5)}';
  }

  Color _accentColor(FavoriteRouteModel favorite) {
    final hash = favorite.routeName.hashCode;
    const palette = [
      Color(0xFF0F9B8E),
      Color(0xFF2563EB),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
    ];
    return palette[hash.abs() % palette.length];
  }

  List<RouteModel> _orderRoutesByIds(
    List<RouteModel> routes,
    List<String> ids,
  ) {
    if (routes.isEmpty || ids.isEmpty) {
      return const [];
    }

    final routeById = {for (final route in routes) route.id: route};
    final ordered = <RouteModel>[];
    for (final id in ids) {
      final match = routeById[id];
      if (match != null) {
        ordered.add(match);
      }
    }
    return ordered;
  }

  List<StationModel> _orderStationsByIds(
    List<StationModel> stations,
    List<String> ids,
  ) {
    if (stations.isEmpty || ids.isEmpty) {
      return const [];
    }

    final stationById = {for (final station in stations) station.id: station};
    final ordered = <StationModel>[];
    for (final id in ids) {
      final match = stationById[id];
      if (match != null) {
        ordered.add(match);
      }
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stationState = context.watch<StationBloc>().state;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
              child: Row(
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
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            size: 16,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Tuyến yêu thích',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed:
                        _isLoading ? null : () => _loadFavorites(refresh: true),
                    icon: const Icon(
                      Icons.refresh,
                      color: UIConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              color: Colors.white,
              child: const TabBar(
                labelColor: Color(0xFF0F172A),
                unselectedLabelColor: Color(0xFF94A3B8),
                indicatorColor: UIConstants.primaryTeal,
                tabs: [
                  Tab(text: 'Lộ trình'),
                  Tab(text: 'Tuyến'),
                  Tab(text: 'Trạm'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildFavoritePathsTab(stationState, scheme),
                  _buildFavoriteRoutesTab(scheme),
                  _buildFavoriteStationsTab(scheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritePathsTab(
    StationState stationState,
    ColorScheme scheme,
  ) {
    if (_isLoading) {
      return const LoadingIndicator();
    }

    if (_error != null) {
      return _buildErrorState(scheme);
    }

    if (_favorites.isEmpty) {
      return _buildEmptyState(
        icon: Icons.favorite_border,
        message: 'Chưa có lộ trình yêu thích',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFavorites(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 20),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _favorites.length,
        itemBuilder: (context, index) {
          final favorite = _favorites[index];
          return _buildFavoritePathCard(favorite, stationState);
        },
      ),
    );
  }

  Widget _buildFavoriteRoutesTab(ColorScheme scheme) {
    if (_isLoading) {
      return const LoadingIndicator();
    }

    if (_error != null) {
      return _buildErrorState(scheme);
    }

    if (_favoriteRoutes.isEmpty) {
      return _buildEmptyState(
        icon: Icons.route_outlined,
        message: 'Chưa có tuyến yêu thích',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFavorites(refresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _favoriteRoutes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final route = _favoriteRoutes[index];
          return _buildRouteFavoriteCard(route);
        },
      ),
    );
  }

  Widget _buildFavoriteStationsTab(ColorScheme scheme) {
    if (_isLoading) {
      return const LoadingIndicator();
    }

    if (_error != null) {
      return _buildErrorState(scheme);
    }

    if (_favoriteStations.isEmpty) {
      return _buildEmptyState(
        icon: Icons.place_outlined,
        message: 'Chưa có trạm yêu thích',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFavorites(refresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _favoriteStations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final station = _favoriteStations[index];
          return _buildStationFavoriteCard(station);
        },
      ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: scheme.error),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Đã xảy ra lỗi.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadFavorites(refresh: true),
            child: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritePathCard(
    FavoriteRouteModel favorite,
    StationState stationState,
  ) {
    final accent = _accentColor(favorite);
    final isStation = favorite.usesStationCode;
    final fromLabel = isStation
        ? _resolveStationLabel(
            favorite.fromStationCode,
            stationState,
          )
        : favorite.fromCoordinates != null
            ? _formatCoordinates(
                favorite.fromCoordinates!,
              )
            : 'Điểm A';
    final toLabel = isStation
        ? _resolveStationLabel(
            favorite.toStationCode,
            stationState,
          )
        : favorite.toCoordinates != null
            ? _formatCoordinates(
                favorite.toCoordinates!,
              )
            : 'Điểm B';
    final isDeleting = _deletingIds.contains(favorite.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () => _openFavorite(favorite),
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
              Container(
                height: 4,
                width: double.infinity,
                color: accent,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 40,
                          width: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.favorite,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            favorite.routeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isStation
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            isStation ? 'Trạm' : 'Tọa độ',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isStation
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF047857),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isDeleting)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            onPressed: () => _deleteFavorite(favorite),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFFCBD5E1),
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildPointRow(
                      icon: Icons.trip_origin,
                      label: fromLabel,
                      color: const Color(0xFF14B8A6),
                    ),
                    const SizedBox(height: 6),
                    _buildPointRow(
                      icon: Icons.place_rounded,
                      label: toLabel,
                      color: const Color(0xFFFB7185),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteFavoriteCard(RouteModel route) {
    final accent = _routeAccentColor(route);

    return GestureDetector(
      onTap: () => _openRouteDetail(route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F0F172A),
              blurRadius: 16,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                route.routeCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.routeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${route.startPoint} → ${route.endPoint}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCBD5E1),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationFavoriteCard(StationModel station) {
    final address = _formatStationAddress(station);

    return GestureDetector(
      onTap: () => _openStationDetail(station),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F0F172A),
              blurRadius: 16,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.place_rounded,
                color: Color(0xFF0F766E),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.stationName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCBD5E1),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _openRouteDetail(RouteModel route) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RouteDetailScreen(route: route),
      ),
    );
  }

  void _openStationDetail(StationModel station) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StationDetailScreen(station: station),
      ),
    );
  }

  Color _routeAccentColor(RouteModel route) {
    final hash = route.routeCode.hashCode ^ route.routeName.hashCode;
    const palette = [
      Color(0xFF0F9B8E),
      Color(0xFF2563EB),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
    ];
    return palette[hash.abs() % palette.length];
  }

  String _formatStationAddress(StationModel station) {
    final addressParts = <String>[];
    if (station.addressNo.trim().isNotEmpty) {
      addressParts.add(station.addressNo.trim());
    }
    if (station.streetName.trim().isNotEmpty) {
      addressParts.add(station.streetName.trim());
    }

    if (addressParts.isEmpty) {
      return station.stationCode;
    }

    return addressParts.join(' ');
  }

  Widget _buildPointRow({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  String? _resolveAccessToken(AuthAuthenticated authState) {
    if (authState.accessToken.isNotEmpty) {
      return authState.accessToken;
    }
    return _storageService.getAuthToken();
  }
}
