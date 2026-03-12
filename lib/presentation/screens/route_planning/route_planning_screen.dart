import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/routes/app_routes.dart';

class RoutePlanningScreen extends StatefulWidget {
  const RoutePlanningScreen({super.key});

  @override
  State<RoutePlanningScreen> createState() => _RoutePlanningScreenState();
}

class _RoutePlanningScreenState extends State<RoutePlanningScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  late TabController _tabController;

  String _selectedOption = 'Nhanh nhất';

  // Mock route data
  final List<Map<String, dynamic>> _routes = [
    {
      'totalTime': '35 phút',
      'reliability': '78%',
      'isRecommended': true,
      'warning': 'Tàu Metro chậm 3 phút do kiểm tra kỹ thuật',
      'segments': [
        {
          'type': 'walk',
          'duration': '5 phút',
          'icon': Icons.directions_walk,
          'distance': '450m',
        },
        {
          'type': 'bus',
          'duration': '28 phút',
          'icon': Icons.directions_bus,
          'number': '52',
          'name': 'Xe buýt 52 hướng Đại học Quốc gia - 15 trạm',
          'route': 'Tuyến: 52    Samco City | 47',
          'price': '7,000đ',
          'schedules': ['12 phút', '27 phút', '42 phút'],
          'delay': 'Chậm 5 phút',
        },
        {
          'type': 'walk',
          'duration': '2 phút',
          'icon': Icons.directions_walk,
          'distance': '130m',
        },
      ],
      'totalDistance': '450m',
      'price': '7,000đ',
      'transfers': '0 lần',
    },
    {
      'totalTime': '42 phút',
      'reliability': '78%',
      'isRecommended': false,
      'isGreen': true,
      'segments': [
        {
          'type': 'walk',
          'duration': '3 phút',
          'icon': Icons.directions_walk,
        },
        {
          'type': 'bike',
          'duration': '18 phút',
          'icon': Icons.directions_bike,
        },
        {
          'type': 'metro',
          'duration': '15 phút',
          'icon': Icons.train,
          'number': 'F3',
        },
      ],
      'totalDistance': '200m',
      'price': '0đ',
      'transfers': '2 lần',
      'badges': ['100% xanh', 'Khám phá sông nước', 'Tập thể dục'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fromController.text = 'Ngã ba Thành Thái';
    _toController.text = 'ĐH BÁCH KHOA TP HCM';
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.primary,
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        title: const Text('Lập kế hoạch hành trình'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: Column(
        children: [
          // Search section
          Container(
            color: scheme.primary,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // From field
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _fromController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.location_on_outlined),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Swap button
                Center(
                  child: IconButton(
                    onPressed: () {
                      final temp = _fromController.text;
                      _fromController.text = _toController.text;
                      _toController.text = temp;
                    },
                    icon: const Icon(Icons.swap_vert),
                    color: scheme.onPrimary,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // To field
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _toController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.navigation_outlined),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Options
                Row(
                  children: [
                    const Icon(Icons.tune, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _selectedOption,
                        dropdownColor: scheme.primary,
                        style: TextStyle(color: scheme.onPrimary),
                        underline: Container(),
                        icon: Icon(Icons.keyboard_arrow_down,
                            color: scheme.onPrimary),
                        items: ['Nhanh nhất', 'Ít chuyển nhất', 'Rẻ nhất']
                            .map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedOption = newValue!;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Search button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.secondary,
                      foregroundColor: scheme.onSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Tìm tuyến đường',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Traffic warning
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ùn tắc nghiêm trọng tại ngã tư Thủ Đức do sự cố xe',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Text(
                  'Mưa lớn gây ngập ở quận 2, một số tuyến xe buýt chậm 10-15 phút',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Tabs
                  TabBar(
                    controller: _tabController,
                    labelColor: scheme.primary,
                    unselectedLabelColor: scheme.onSurfaceVariant,
                    indicatorColor: scheme.primary,
                    tabs: const [
                      Tab(text: 'Tuyến đường'),
                      Tab(text: 'Timeline'),
                      Tab(text: 'Bản đồ'),
                    ],
                  ),

                  // Tab views
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRoutesTab(),
                        _buildTimelineTab(),
                        _buildMapTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _routes.length,
      itemBuilder: (context, index) {
        final route = _routes[index];
        return _buildRouteCard(route);
      },
    );
  }

  Widget _buildRouteCard(Map<String, dynamic> route) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: route['isRecommended'] == true
              ? Colors.orange
              : Colors.grey.shade200,
          width: route['isRecommended'] == true ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.access_time, size: 20, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Text(
                route['totalTime'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              if (route['isRecommended'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Rẻ nhất',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (route['isGreen'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Xanh',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    route['reliability'],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (route['warning'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.yellow.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      route['warning'],
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Route segments
          Column(
            children: [
              for (var i = 0; i < route['segments'].length; i++) ...[
                _buildSegment(route['segments'][i]),
                if (i < route['segments'].length - 1) const SizedBox(height: 8),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Footer
          Row(
            children: [
              Text(
                'Đi bộ',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                route['totalDistance'],
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Tổng chi phí:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                route['price'],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Chuyển tuyến:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                route['transfers'],
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          if (route['badges'] != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (var badge in route['badges'])
                  Chip(
                    label: Text(
                      badge,
                      style: const TextStyle(fontSize: 11),
                    ),
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegment(Map<String, dynamic> segment) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: segment['type'] == 'walk'
                    ? Colors.grey.shade200
                    : segment['type'] == 'bus'
                        ? scheme.secondary
                        : segment['type'] == 'metro'
                            ? scheme.primary
                            : segment['type'] == 'bike'
                                ? scheme.primary
                                : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                segment['icon'],
                color: segment['type'] == 'walk'
                    ? Colors.grey.shade700
                    : Colors.white,
                size: 24,
              ),
            ),
            if (segment != _routes[0]['segments'].last)
              Container(
                width: 2,
                height: 30,
                color: Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    segment['duration'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (segment['number'] != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 14),
                  ],
                ],
              ),
              if (segment['name'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  segment['name'],
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              if (segment['route'] != null) ...[
                const SizedBox(height: 2),
                Text(
                  segment['route'],
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              if (segment['price'] != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Giá vé: ${segment['price']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              if (segment['schedules'] != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Lịch trình sắp tới:\n${segment['schedules'].join(', ')}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
              if (segment['delay'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  segment['delay'],
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.error,
                  ),
                ),
              ],
              if (segment['distance'] != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Khoảng cách: ${segment['distance']}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _routes.map((route) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    route['totalTime'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    route['price'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(route['reliability']),
                    ],
                  ),
                ],
              ),
              if (route['warning'] != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          route['warning'],
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var segment in route['segments']) ...[
                    Icon(segment['icon'], size: 24),
                    const SizedBox(width: 4),
                    Text(segment['duration'],
                        style: const TextStyle(fontSize: 12)),
                    if (segment != route['segments'].last) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 14),
                      const SizedBox(width: 4),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Đi bộ'),
                  const SizedBox(width: 4),
                  Text(route['totalDistance'],
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Text('Chuyển tuyến:'),
                  const SizedBox(width: 4),
                  Text(route['transfers'],
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              if (route['badges'] != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var badge in route['badges'])
                      Chip(
                        label:
                            Text(badge, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMapTab() {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(10.8231, 106.6297),
            initialZoom: 13,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [
                    const LatLng(10.8131, 106.6197),
                    const LatLng(10.8231, 106.6297),
                    const LatLng(10.8331, 106.6397),
                  ],
                  color: scheme.primary,
                  strokeWidth: 4,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: const LatLng(10.8131, 106.6197),
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on,
                        color: Colors.white, size: 18),
                  ),
                ),
                Marker(
                  point: const LatLng(10.8331, 106.6397),
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.location_on,
                        color: scheme.onSecondary, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                backgroundColor: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
