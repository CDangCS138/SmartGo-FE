import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smartgo/domain/entities/path_finding.dart';
import 'package:smartgo/presentation/blocs/route/route_bloc.dart';
import 'package:smartgo/presentation/blocs/route/route_event.dart';
import 'package:smartgo/presentation/blocs/route/route_state.dart';

class PathFindingWidget extends StatefulWidget {
  final String fromStationCode;
  final String toStationCode;
  const PathFindingWidget({
    super.key,
    required this.fromStationCode,
    required this.toStationCode,
  });
  @override
  State<PathFindingWidget> createState() => _PathFindingWidgetState();
}

class _PathFindingWidgetState extends State<PathFindingWidget> {
  String _criteria = 'BALANCED';
  int _numPaths = 3;
  @override
  void initState() {
    super.initState();
    _findPaths();
  }

  void _findPaths() {
    context.read<RouteBloc>().add(
          FindPathEvent(
            fromStationCode: widget.fromStationCode,
            toStationCode: widget.toStationCode,
            criteria: _criteria,
            numPaths: _numPaths,
            maxTransfers: 3,
            timeOfDay: DateTime.now().hour,
            congestionAware: true,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildControls(),
        const SizedBox(height: 16),
        Expanded(
          child: BlocBuilder<RouteBloc, RouteState>(
            builder: (context, state) {
              if (state is PathFindingLoading) {
                return Center(
                  child: CircularProgressIndicator(color: scheme.primary),
                );
              } else if (state is PathsFound) {
                return _buildMultiplePathsResult(state.paths);
              } else if (state is PathFindingError) {
                return _buildError(state.message);
              }
              return const Center(
                child: Text(
                  'Chọn tùy chọn và nhấn tìm đường',
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _criteria,
                  dropdownColor: scheme.surface,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu chí tối ưu',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'TIME',
                      child: Text('Nhanh nhất (TIME)'),
                    ),
                    DropdownMenuItem(
                      value: 'COST',
                      child: Text('Rẻ nhất (COST)'),
                    ),
                    DropdownMenuItem(
                      value: 'DISTANCE',
                      child: Text('Ngắn nhất (DISTANCE)'),
                    ),
                    DropdownMenuItem(
                      value: 'BALANCED',
                      child: Text('Cân bằng (BALANCED)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _criteria = value;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  Text(
                    'Số lộ trình',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  DropdownButton<int>(
                    value: _numPaths,
                    dropdownColor: scheme.surface,
                    style: TextStyle(color: scheme.onSurface, fontSize: 16),
                    underline: Container(),
                    items: [1, 2, 3, 4, 5].map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _numPaths = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _findPaths,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Tìm đường'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiplePathsResult(List<PathResult> paths) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: paths.length,
      itemBuilder: (context, index) {
        final path = paths[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getOptimizationColor(path.optimizationType),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getOptimizationLabel(path.optimizationType),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (path.optimizationScore != null)
                      Text(
                        'Điểm: ${(path.optimizationScore! * 100).toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPathSummary(path),
                const SizedBox(height: 8),
                _buildSegmentsList(path),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPathSummary(PathResult path) {
    final stationAccessLegs = path.stationAccessWalkingLegs;
    final stationAccessDistanceKm = stationAccessLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.distanceKm,
    );
    final stationAccessMinutes = stationAccessLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.estimatedTimeMinutes,
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryItem(
                Icons.access_time,
                path.formattedTime,
                'Thời gian',
              ),
            ),
            Expanded(
              child: _buildSummaryItem(
                Icons.straighten,
                path.formattedDistance,
                'Khoảng cách',
              ),
            ),
            Expanded(
              child: _buildSummaryItem(
                Icons.attach_money,
                path.formattedCost,
                'Chi phí',
              ),
            ),
            Expanded(
              child: _buildSummaryItem(
                Icons.compare_arrows,
                '${path.numberOfTransfers}',
                'Chuyển',
              ),
            ),
          ],
        ),
        if (path.hasWalkingLegs)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.directions_walk, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Đi bộ ${path.formattedWalkingDistance} (${path.formattedWalkingTime})',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        if (stationAccessLegs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.alt_route, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Đi bộ vào trạm ${stationAccessDistanceKm.toStringAsFixed(2)} km (${stationAccessMinutes.toStringAsFixed(0)} phút)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentsList(PathResult path) {
    final scheme = Theme.of(context).colorScheme;
    final stationAccessLegs = path.stationAccessWalkingLegs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chi tiết hành trình',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        ...path.segments.map((segment) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          segment.routeCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          segment.routeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${segment.from} → ${segment.to}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${segment.time} phút',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.straighten, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${segment.distance.toStringAsFixed(1)} km',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.attach_money,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${segment.cost.toStringAsFixed(0)} đ',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        if (path.walkingLegs.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Chặng đi bộ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ...path.walkingLegs.map((leg) {
            final distance = '${leg.distanceKm.toStringAsFixed(2)} km';
            final duration =
                '${leg.estimatedTimeMinutes.toStringAsFixed(0)} phút';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: scheme.surfaceContainerLow,
              child: ListTile(
                leading: Icon(Icons.directions_walk, color: scheme.primary),
                title: Text(leg.displayType),
                subtitle: Text('${leg.stationName}\n$distance • $duration'),
                isThreeLine: true,
              ),
            );
          }),
        ],
        if (stationAccessLegs.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Đi bộ vào trạm từ đường chính',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ...stationAccessLegs.map((leg) {
            final distance = '${leg.distanceKm.toStringAsFixed(2)} km';
            final duration =
                '${leg.estimatedTimeMinutes.toStringAsFixed(0)} phút';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: scheme.surfaceContainerLow,
              child: ListTile(
                leading: Icon(Icons.alt_route, color: scheme.primary),
                title: Text(leg.stationName),
                subtitle: Text('$distance • $duration'),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildError(String message) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: scheme.error),
          const SizedBox(height: 16),
          const Text(
            'Lỗi',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _findPaths,
            child: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Color _getOptimizationColor(String? type) {
    switch (type) {
      case 'fastest':
        return Colors.orange;
      case 'cheapest':
        return Colors.green;
      case 'shortest':
        return Colors.blue;
      case 'balanced':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getOptimizationLabel(String? type) {
    switch (type) {
      case 'fastest':
        return 'NHANH NHẤT';
      case 'cheapest':
        return 'RẺ NHẤT';
      case 'shortest':
        return 'NGẮN NHẤT';
      case 'balanced':
        return 'CÂN BẰNG';
      default:
        return 'KHÔNG XÁC ĐỊNH';
    }
  }
}
