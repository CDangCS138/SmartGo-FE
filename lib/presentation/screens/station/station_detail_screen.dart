import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:smartgo/core/di/injection.dart';
import 'package:smartgo/data/datasources/user_favorites_remote_data_source.dart';
import 'package:smartgo/presentation/blocs/auth/auth_bloc.dart';
import 'package:smartgo/presentation/blocs/auth/auth_event.dart';
import 'package:smartgo/presentation/blocs/auth/auth_state.dart';
import '../../../domain/entities/station.dart';

/// Station detail screen showing full information about a bus stop
class StationDetailScreen extends StatefulWidget {
  final Station station;

  const StationDetailScreen({
    super.key,
    required this.station,
  });

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  late final UserFavoritesRemoteDataSource _favoritesDataSource;
  bool _isFavorite = false;
  bool _isUpdatingFavorite = false;

  @override
  void initState() {
    super.initState();
    _favoritesDataSource =
        UserFavoritesRemoteDataSource(client: getIt<http.Client>());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFavoriteFromAuth(context.read<AuthBloc>().state);
  }

  void _syncFavoriteFromAuth(AuthState state) {
    if (state is AuthAuthenticated) {
      final isFavorite =
          state.user.favoriteStationIds.contains(widget.station.id);
      if (isFavorite != _isFavorite) {
        setState(() {
          _isFavorite = isFavorite;
        });
      }
      return;
    }

    if (_isFavorite) {
      setState(() {
        _isFavorite = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isUpdatingFavorite) {
      return;
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      _showSnack('Vui lòng đăng nhập để lưu yêu thích', isError: true);
      return;
    }

    final currentRouteIds = authState.user.favoriteRouteIds;
    final currentStationIds = authState.user.favoriteStationIds;
    final nextStationIds = currentStationIds.toSet();

    final wasFavorite = nextStationIds.contains(widget.station.id);
    if (wasFavorite) {
      nextStationIds.remove(widget.station.id);
    } else {
      nextStationIds.add(widget.station.id);
    }

    setState(() {
      _isUpdatingFavorite = true;
      _isFavorite = !wasFavorite;
    });

    try {
      await _favoritesDataSource.updateFavorites(
        userId: authState.user.id,
        favoriteRouteIds: currentRouteIds,
        favoriteStationIds: nextStationIds.toList(),
      );
      if (!mounted) {
        return;
      }
      context.read<AuthBloc>().add(const GetCurrentUserEvent());
      _showSnack(
        wasFavorite ? 'Đã bỏ yêu thích trạm' : 'Đã lưu trạm yêu thích',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isFavorite = wasFavorite;
      });
      _showSnack('Không cập nhật được yêu thích: $error', isError: true);
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isUpdatingFavorite = false;
      });
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.error : scheme.inverseSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final scheme = Theme.of(context).colorScheme;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        _syncFavoriteFromAuth(state);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chi tiết trạm'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          actions: [
            if (_isUpdatingFavorite)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip:
                    _isFavorite ? 'Bỏ yêu thích trạm' : 'Lưu trạm yêu thích',
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? const Color(0xFFEF4444) : null,
                ),
                onPressed: _toggleFavorite,
              ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with station code
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: scheme.primary),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.onPrimary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        station.stationCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      station.stationName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Address
                    _buildInfoSection(
                      context,
                      icon: Icons.location_on,
                      title: 'Địa chỉ',
                      content: station.fullAddress,
                    ),

                    const SizedBox(height: 20),

                    // Coordinates
                    _buildInfoSection(
                      context,
                      icon: Icons.pin_drop,
                      title: 'Tọa độ',
                      content: 'Lat: ${station.latitude.toStringAsFixed(7)}\n'
                          'Lng: ${station.longitude.toStringAsFixed(7)}',
                    ),

                    const SizedBox(height: 20),

                    // Station Type
                    _buildInfoSection(
                      context,
                      icon: Icons.category,
                      title: 'Loại trạm',
                      content: _getStationTypeName(station.stationType),
                    ),

                    const SizedBox(height: 20),

                    // Status
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: scheme.primary, size: 20),
                        const SizedBox(width: 12),
                        const Text(
                          'Trạng thái: ',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(station.status),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getStatusName(station.status),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Facilities
                    const Text(
                      'Tiện ích',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildFacilities(context),

                    const SizedBox(height: 24),

                    // Additional Info
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Thông tin bổ sung',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                                'Ngày tạo', _formatDate(station.createdAt)),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                                'Cập nhật', _formatDate(station.updatedAt)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              // TODO: Open in maps app
                            },
                            icon: const Icon(Icons.map),
                            label: const Text('Chỉ đường'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // TODO: Plan route
                              context.pop();
                            },
                            icon: const Icon(Icons.directions_bus),
                            label: const Text('Tìm tuyến'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: scheme.secondary,
                              foregroundColor: scheme.onSecondary,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildInfoSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: scheme.primary,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFacilities(BuildContext context) {
    final station = widget.station;
    final hasShelter =
        station.stopCategory == 'Nhà chờ' || station.stopCategory == 'Bến xe';

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildFacilityChip(
          context,
          icon: Icons.roofing,
          label: 'Nhà chờ',
          available: hasShelter,
        ),
        _buildFacilityChip(
          context,
          icon: Icons.accessible,
          label: 'Xe lăn',
          available: station.hasWheelchair,
        ),
        _buildFacilityChip(
          context,
          icon: Icons.accessible_forward,
          label: 'Dốc',
          available: station.hasRamp,
        ),
      ],
    );
  }

  Widget _buildFacilityChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool available,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: available
            ? scheme.primary.withValues(alpha: 0.1)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: available ? scheme.primary : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: available ? scheme.primary : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: available ? scheme.primary : Colors.grey,
              fontWeight: available ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _getStationTypeName(StationType type) {
    switch (type) {
      case StationType.BUS_STOP:
        return 'Trạm xe buýt';
      case StationType.METRO_STATION:
        return 'Ga tàu điện';
      case StationType.FERRY_TERMINAL:
        return 'Bến phà';
      case StationType.TRANSIT_HUB:
        return 'Trung tâm giao thông';
      default:
        return 'Khác';
    }
  }

  String _getStatusName(StationStatus status) {
    switch (status) {
      case StationStatus.ACTIVE:
        return 'Hoạt động';
      case StationStatus.INACTIVE:
        return 'Ngừng hoạt động';
      case StationStatus.UNDER_MAINTENANCE:
        return 'Đang bảo trì';
      default:
        return 'Không xác định';
    }
  }

  Color _getStatusColor(StationStatus status) {
    switch (status) {
      case StationStatus.ACTIVE:
        return Colors.green;
      case StationStatus.INACTIVE:
        return Colors.red;
      case StationStatus.UNDER_MAINTENANCE:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
