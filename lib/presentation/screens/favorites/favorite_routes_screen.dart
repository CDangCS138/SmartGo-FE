import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/ui_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/routes/app_routes.dart';
import '../../../data/datasources/favorite_routes_remote_data_source.dart';
import '../../../data/models/favorite_route_model.dart';
import '../../../domain/entities/path_finding.dart';
import '../../blocs/station/station_bloc.dart';
import '../../blocs/station/station_state.dart';
import '../../widgets/loading_indicator.dart';

class FavoriteRoutesScreen extends StatefulWidget {
  const FavoriteRoutesScreen({super.key});

  @override
  State<FavoriteRoutesScreen> createState() => _FavoriteRoutesScreenState();
}

class _FavoriteRoutesScreenState extends State<FavoriteRoutesScreen> {
  late final FavoriteRoutesRemoteDataSource _dataSource;
  bool _isLoading = false;
  String? _error;
  List<FavoriteRouteModel> _favorites = const [];
  final Set<String> _deletingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _dataSource = FavoriteRoutesRemoteDataSource(client: getIt<http.Client>());
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

    try {
      final response = await _dataSource.getFavoriteRoutes(
        page: 1,
        limit: 200,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _favorites = response.data;
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
          title: const Text('Xoa tuyen yeu thich'),
          content: Text('Ban chac chan muon xoa "${favorite.routeName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Huy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xoa'),
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
      await _dataSource.deleteFavoriteRoute(id: favorite.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _favorites =
            _favorites.where((item) => item.id != favorite.id).toList();
      });
      _showInfo('Da xoa tuyen yeu thich');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Khong the xoa: $error');
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
      return 'Khong ro tram';
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stationState = context.watch<StationBloc>().state;

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
                      'Tuyen yeu thich',
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
                  icon: const Icon(Icons.refresh,
                      color: UIConstants.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const LoadingIndicator()
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 64, color: scheme.error),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => _loadFavorites(refresh: true),
                              child: const Text('Thu lai'),
                            ),
                          ],
                        ),
                      )
                    : _favorites.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.favorite_border,
                                  size: 48,
                                  color: Color(0xFFCBD5E1),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Chua co tuyen yeu thich',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadFavorites(refresh: true),
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.only(top: 12, bottom: 20),
                              itemCount: _favorites.length,
                              itemBuilder: (context, index) {
                                final favorite = _favorites[index];
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
                                        : 'Diem A';
                                final toLabel = isStation
                                    ? _resolveStationLabel(
                                        favorite.toStationCode,
                                        stationState,
                                      )
                                    : favorite.toCoordinates != null
                                        ? _formatCoordinates(
                                            favorite.toCoordinates!,
                                          )
                                        : 'Diem B';
                                final isDeleting =
                                    _deletingIds.contains(favorite.id);

                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: GestureDetector(
                                    onTap: () => _openFavorite(favorite),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                            color: const Color(0xFFF1F5F9)),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            height: 4,
                                            width: double.infinity,
                                            color: accent,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      height: 40,
                                                      width: 40,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: accent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(16),
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isStation
                                                            ? const Color(
                                                                0xFFF1F5F9)
                                                            : const Color(
                                                                0xFFECFDF5),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(100),
                                                      ),
                                                      child: Text(
                                                        isStation
                                                            ? 'Tram'
                                                            : 'Toa do',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: isStation
                                                              ? const Color(
                                                                  0xFF475569)
                                                              : const Color(
                                                                  0xFF047857),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    if (isDeleting)
                                                      const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    else
                                                      IconButton(
                                                        onPressed: () =>
                                                            _deleteFavorite(
                                                                favorite),
                                                        icon: const Icon(
                                                          Icons.delete_outline,
                                                          size: 18,
                                                          color:
                                                              Color(0xFF94A3B8),
                                                        ),
                                                      ),
                                                    const Icon(
                                                      Icons
                                                          .chevron_right_rounded,
                                                      color: Color(0xFFCBD5E1),
                                                      size: 20,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                _buildPointRow(
                                                  icon: Icons.trip_origin,
                                                  label: fromLabel,
                                                  color:
                                                      const Color(0xFF14B8A6),
                                                ),
                                                const SizedBox(height: 6),
                                                _buildPointRow(
                                                  icon: Icons.place_rounded,
                                                  label: toLabel,
                                                  color:
                                                      const Color(0xFFFB7185),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
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
}
