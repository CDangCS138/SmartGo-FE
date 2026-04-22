import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/services/text_to_speech_service.dart';
import '../../../domain/entities/path_finding.dart';
import '../../../domain/entities/station.dart';
import '../../blocs/route/route_bloc.dart';
import '../../blocs/route/route_event.dart';
import '../../blocs/route/route_state.dart';
import '../../blocs/station/station_bloc.dart';
import '../../blocs/station/station_event.dart';
import '../../blocs/station/station_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/tts_icon_button.dart';
import '../../widgets/voice_input_icon_button.dart';

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

  Station? _fromStation;
  Station? _toStation;
  LatLng? _fromPoint;
  LatLng? _toPoint;

  List<Station> _stations = [];
  List<_LocationSuggestion> _fromSuggestions = [];
  List<_LocationSuggestion> _toSuggestions = [];

  final http.Client _httpClient = http.Client();
  Timer? _fromDebounce;
  Timer? _toDebounce;
  int _fromQueryToken = 0;
  int _toQueryToken = 0;
  bool _isSearchingAddress = false;

  RoutingCriteria _selectedCriteria = RoutingCriteria.BALANCED;
  int _maxTransfers = 3;
  bool _isLoading = false;
  bool _isSpeakingGuidance = false;
  List<PathResult> _paths = [];
  int _selectedPathIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStations();
  }

  @override
  void dispose() {
    TextToSpeechService.instance.stop();
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _httpClient.close();
    _fromController.dispose();
    _toController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _loadStations() {
    final currentState = context.read<StationBloc>().state;
    if (currentState is StationLoaded && currentState.stations.isNotEmpty) {
      setState(() {
        _stations = currentState.stations
            .where((s) => s.status == StationStatus.ACTIVE)
            .toList();
      });
      return;
    }

    context.read<StationBloc>().add(
          const FetchAllStationsEvent(page: 1, limit: 5000, refresh: true),
        );
  }

  void _onFromChanged(String text) {
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 280), () {
      _loadMixedSuggestions(text, isFrom: true);
    });

    if (_fromStation != null &&
        _fromController.text != _fromStation!.stationName) {
      _fromStation = null;
    }
  }

  void _onToChanged(String text) {
    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 280), () {
      _loadMixedSuggestions(text, isFrom: false);
    });

    if (_toStation != null && _toController.text != _toStation!.stationName) {
      _toStation = null;
    }
  }

  Future<void> _loadMixedSuggestions(String query,
      {required bool isFrom}) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (isFrom) {
          _fromSuggestions = [];
        } else {
          _toSuggestions = [];
        }
      });
      return;
    }

    final token = isFrom ? ++_fromQueryToken : ++_toQueryToken;

    final stationMatches = _stations
        .where((s) =>
            s.stationName.toLowerCase().contains(q.toLowerCase()) ||
            s.stationCode.toLowerCase().contains(q.toLowerCase()))
        .take(6)
        .map(
          (s) => _LocationSuggestion(
            title: s.stationName,
            subtitle: '${s.stationCode} • Trạm',
            point: LatLng(s.latitude, s.longitude),
            station: s,
            icon: Icons.directions_bus,
          ),
        )
        .toList();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSearchingAddress = true;
      if (isFrom) {
        _fromSuggestions = stationMatches;
      } else {
        _toSuggestions = stationMatches;
      }
    });

    final addressMatches = await _searchAddressSuggestions(q);
    if (!mounted) {
      return;
    }

    final latestToken = isFrom ? _fromQueryToken : _toQueryToken;
    if (token != latestToken) {
      return;
    }

    final merged = <_LocationSuggestion>[...stationMatches, ...addressMatches];
    setState(() {
      _isSearchingAddress = false;
      if (isFrom) {
        _fromSuggestions = merged;
      } else {
        _toSuggestions = merged;
      }
    });
  }

  Future<List<_LocationSuggestion>> _searchAddressSuggestions(
      String query) async {
    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': '$query, Ho Chi Minh City, Vietnam',
          'format': 'json',
          'limit': '5',
          'countrycodes': 'vn',
        },
      );

      final response = await _httpClient.get(
        uri,
        headers: {'User-Agent': 'SmartGo/1.0'},
      );

      if (response.statusCode != 200) {
        return const <_LocationSuggestion>[];
      }

      final List<dynamic> data = json.decode(response.body) as List<dynamic>;
      return data
          .map((item) {
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat == null || lon == null) {
              return null;
            }
            return _LocationSuggestion(
              title: item['display_name']?.toString() ?? 'Địa chỉ',
              subtitle: 'Địa chỉ',
              point: LatLng(lat, lon),
              station: null,
              icon: Icons.place_outlined,
            );
          })
          .whereType<_LocationSuggestion>()
          .toList();
    } catch (_) {
      return const <_LocationSuggestion>[];
    }
  }

  void _selectFromSuggestion(_LocationSuggestion suggestion) {
    setState(() {
      _fromController.text = suggestion.title;
      _fromPoint = suggestion.point;
      _fromStation = suggestion.station;
      _fromSuggestions = [];
    });
  }

  void _selectToSuggestion(_LocationSuggestion suggestion) {
    setState(() {
      _toController.text = suggestion.title;
      _toPoint = suggestion.point;
      _toStation = suggestion.station;
      _toSuggestions = [];
    });
  }

  void _swapLocations() {
    final tempText = _fromController.text;
    final tempPoint = _fromPoint;
    final tempStation = _fromStation;

    setState(() {
      _fromController.text = _toController.text;
      _toController.text = tempText;
      _fromPoint = _toPoint;
      _toPoint = tempPoint;
      _fromStation = _toStation;
      _toStation = tempStation;
      _fromSuggestions = [];
      _toSuggestions = [];
    });
  }

  void _findPath() {
    if (_fromPoint == null || _toPoint == null) {
      _showError('Vui lòng chọn đầy đủ điểm đi và điểm đến');
      return;
    }

    if ((_fromPoint!.latitude - _toPoint!.latitude).abs() < 0.000001 &&
        (_fromPoint!.longitude - _toPoint!.longitude).abs() < 0.000001) {
      _showError('Điểm đi và điểm đến không được trùng nhau');
      return;
    }

    setState(() {
      _isLoading = true;
      _paths = [];
      _selectedPathIndex = 0;
    });

    // Send both stationCode (if user selected stations) and coordinates (always).
    // This enables the backend to use either or both depending on its logic.
    context.read<RouteBloc>().add(
          FindPathEvent(
            fromStationCode: _fromStation?.stationCode,
            toStationCode: _toStation?.stationCode,
            fromLatitude: _fromPoint!.latitude,
            fromLongitude: _fromPoint!.longitude,
            toLatitude: _toPoint!.latitude,
            toLongitude: _toPoint!.longitude,
            criteria: _selectedCriteria.value,
            maxTransfers: _maxTransfers,
            numPaths: 3,
          ),
        );
  }

  void _resetForm() {
    if (_isSpeakingGuidance) {
      TextToSpeechService.instance.stop();
    }

    setState(() {
      _fromStation = null;
      _toStation = null;
      _fromPoint = null;
      _toPoint = null;
      _fromController.clear();
      _toController.clear();
      _fromSuggestions = [];
      _toSuggestions = [];
      _selectedCriteria = RoutingCriteria.BALANCED;
      _maxTransfers = 3;
      _isSpeakingGuidance = false;
      _paths = [];
      _selectedPathIndex = 0;
      _isSearchingAddress = false;
    });
  }

  void _showError(String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: scheme.error,
      ),
    );
  }

  void _showInfo(String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: scheme.inverseSurface,
      ),
    );
  }

  String _formatCostForSpeech(double value) {
    final rounded = value.round();
    final grouped = rounded.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
    return '$grouped đồng';
  }

  String _buildAccessibilityGuidance(PathResult path) {
    final startName = path.stations.isNotEmpty
        ? path.stations.first.stationName
        : _fromController.text.trim();
    final endName = path.stations.isNotEmpty
        ? path.stations.last.stationName
        : _toController.text.trim();

    final from = startName.isEmpty ? 'điểm xuất phát' : startName;
    final to = endName.isEmpty ? 'điểm đến' : endName;

    final buffer = StringBuffer();
    buffer.writeln('Đây là hướng dẫn di chuyển tổng hợp của SmartGo.');
    buffer.writeln('Bạn đi từ $from đến $to.');
    buffer.writeln(
      'Tổng thời gian dự kiến ${path.formattedTime}, tổng quãng đường ${path.formattedDistance}, tổng chi phí ${path.formattedCost}.',
    );

    if (path.numberOfTransfers <= 0) {
      buffer.writeln('Lộ trình này không cần chuyển tuyến.');
    } else {
      buffer.writeln(
        'Lộ trình này có ${path.numberOfTransfers} lần chuyển tuyến. Khi chuyển tuyến, hãy đi chậm và quan sát biển chỉ dẫn.',
      );
    }

    buffer.writeln('Hướng dẫn chi tiết từng bước như sau.');

    for (var i = 0; i < path.segments.length; i++) {
      final segment = path.segments[i];
      final durationText = segment.time > 0
          ? '${segment.time.toStringAsFixed(0)} phút'
          : 'chưa có ước lượng thời gian';
      final costText = segment.cost > 0
          ? 'chi phí khoảng ${_formatCostForSpeech(segment.cost)}'
          : 'không phát sinh thêm chi phí';
      final routeNameText = segment.routeName.trim().isEmpty
          ? ''
          : ', ${segment.routeName.trim()}';

      buffer.writeln(
        'Bước ${i + 1}. Từ ${segment.from} đến ${segment.to} bằng tuyến ${segment.routeCode}$routeNameText. Thời gian khoảng $durationText, $costText.',
      );

      if (i < path.segments.length - 1) {
        buffer.writeln(
          'Sau khi xuống trạm, bạn nên dừng lại vài giây để định hướng rồi mới di chuyển sang điểm tiếp theo.',
        );
      }
    }

    buffer.writeln(
      'Lưu ý hỗ trợ. Khi lên xuống phương tiện, hãy bám tay vịn, đi từng bước chậm. Nếu cần, hãy nhờ phụ xe hoặc người xung quanh hỗ trợ.',
    );
    buffer.writeln(
      'Ưu tiên thang máy, lối đi bằng phẳng, và khu vực có ánh sáng tốt nếu bạn đi lại khó khăn.',
    );
    buffer.writeln('Chúc bạn di chuyển an toàn và thuận lợi.');

    return buffer.toString();
  }

  Future<void> _speakSelectedPathGuidance() async {
    if (_paths.isEmpty) {
      _showError('Chưa có lộ trình để đọc hướng dẫn.');
      return;
    }

    final safeIndex =
        _selectedPathIndex >= 0 && _selectedPathIndex < _paths.length
            ? _selectedPathIndex
            : 0;
    final selectedPath = _paths[safeIndex];
    final guidanceText = _buildAccessibilityGuidance(selectedPath);

    setState(() => _isSpeakingGuidance = true);
    final success = await TextToSpeechService.instance.speak(guidanceText);

    if (!mounted) {
      return;
    }

    setState(() => _isSpeakingGuidance = false);

    if (!success) {
      _showError('Không thể đọc hướng dẫn lộ trình lúc này.');
    }
  }

  Future<void> _stopPathGuidance() async {
    await TextToSpeechService.instance.stop();
    if (!mounted) {
      return;
    }
    setState(() => _isSpeakingGuidance = false);
  }

  Widget _buildGuidanceCard(PathResult selectedPath) {
    final scheme = Theme.of(context).colorScheme;
    final startName = selectedPath.stations.isNotEmpty
        ? selectedPath.stations.first.stationName
        : (_fromController.text.trim().isEmpty
            ? 'Điểm đi'
            : _fromController.text.trim());
    final endName = selectedPath.stations.isNotEmpty
        ? selectedPath.stations.last.stationName
        : (_toController.text.trim().isEmpty
            ? 'Điểm đến'
            : _toController.text.trim());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Hướng dẫn giọng nói hỗ trợ di chuyển',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$startName → $endName. Nội dung đọc gồm tổng quan lộ trình, từng bước di chuyển và lưu ý an toàn.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _isSpeakingGuidance ? null : _speakSelectedPathGuidance,
                  icon: _isSpeakingGuidance
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.record_voice_over_rounded),
                  label: Text(
                    _isSpeakingGuidance
                        ? 'Đang đọc hướng dẫn...'
                        : 'Đọc hướng dẫn',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _isSpeakingGuidance ? _stopPathGuidance : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Dừng'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MultiBlocListener(
      listeners: [
        BlocListener<StationBloc, StationState>(
          listener: (context, state) {
            if (state is StationLoaded) {
              setState(() {
                _stations = state.stations
                    .where((s) => s.status == StationStatus.ACTIVE)
                    .toList();
              });
            } else if (state is StationError) {
              _showError(state.message);
            }
          },
        ),
        BlocListener<RouteBloc, RouteState>(
          listener: (context, state) {
            if (state is PathFindingLoading) {
              setState(() => _isLoading = true);
            } else if (state is PathsFound) {
              if (_isSpeakingGuidance) {
                TextToSpeechService.instance.stop();
              }
              setState(() {
                _isLoading = false;
                _isSpeakingGuidance = false;
                _paths = state.paths;
                _selectedPathIndex = 0;
              });
              _showInfo('Tìm thấy ${state.paths.length} lộ trình phù hợp');
            } else if (state is PathFindingError) {
              if (_isSpeakingGuidance) {
                TextToSpeechService.instance.stop();
              }
              setState(() {
                _isLoading = false;
                _isSpeakingGuidance = false;
                _paths = [];
              });
              _showError('Không tìm được lộ trình: ${state.message}');
            }
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: AppBar(
          title: const Text('Lập kế hoạch hành trình'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppRoutes.home),
          ),
          actions: [
            IconButton(
              onPressed: _resetForm,
              icon: const Icon(Icons.refresh),
              tooltip: 'Đặt lại',
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _buildSearchPanel(),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        TabBar(
                          controller: _tabController,
                          labelColor: scheme.primary,
                          unselectedLabelColor: scheme.onSurfaceVariant,
                          indicatorColor: scheme.primary,
                          tabs: const [
                            Tab(text: 'Lộ trình'),
                            Tab(text: 'Bản đồ'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildResultsTab(),
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
            if (_isLoading)
              Container(
                color: scheme.scrim.withValues(alpha: 0.25),
                child: const Center(child: LoadingIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPanel() {
    final scheme = Theme.of(context).colorScheme;

    final panelMaxHeight = MediaQuery.of(context).size.height * 0.55;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      constraints: BoxConstraints(maxHeight: panelMaxHeight),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildLocationField(
              controller: _fromController,
              hintText: 'Điểm đi (trạm hoặc địa chỉ)',
              prefixIcon: Icons.trip_origin,
              suggestions: _fromSuggestions,
              onChanged: _onFromChanged,
              onSuggestionTap: _selectFromSuggestion,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton.filledTonal(
                onPressed: _swapLocations,
                icon: const Icon(Icons.swap_vert),
                tooltip: 'Đảo chiều',
              ),
            ),
            const SizedBox(height: 8),
            _buildLocationField(
              controller: _toController,
              hintText: 'Điểm đến (trạm hoặc địa chỉ)',
              prefixIcon: Icons.place_outlined,
              suggestions: _toSuggestions,
              onChanged: _onToChanged,
              onSuggestionTap: _selectToSuggestion,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<RoutingCriteria>(
                    value: _selectedCriteria,
                    decoration: const InputDecoration(
                      labelText: 'Tiêu chí tối ưu',
                    ),
                    items: RoutingCriteria.values
                        .map(
                          (c) => DropdownMenuItem<RoutingCriteria>(
                            value: c,
                            child: Text(c.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _selectedCriteria = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _maxTransfers,
                    decoration: const InputDecoration(
                      labelText: 'Chuyển tuyến tối đa',
                    ),
                    items: const [0, 1, 2, 3, 4]
                        .map(
                          (v) => DropdownMenuItem<int>(
                            value: v,
                            child: Text(v.toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _maxTransfers = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppButton(
              text: 'Tìm lộ trình',
              icon: Icons.search,
              onPressed: _findPath,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    required List<_LocationSuggestion> suggestions,
    required ValueChanged<String> onChanged,
    required ValueChanged<_LocationSuggestion> onSuggestionTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final stationSuggestions =
        suggestions.where((item) => item.station != null).toList();
    final addressSuggestions =
        suggestions.where((item) => item.station == null).toList();
    final showSuggestionBox = _isSearchingAddress ||
        stationSuggestions.isNotEmpty ||
        addressSuggestions.isNotEmpty;
    final initialTabIndex = stationSuggestions.isNotEmpty ? 0 : 1;
    final showLoading = _isSearchingAddress;
    final showClear = controller.text.isNotEmpty;
    final actionCount = 2 + (showLoading ? 1 : 0) + (showClear ? 1 : 0);
    final suffixWidth = (44.0 * actionCount).clamp(88.0, 176.0);

    return Column(
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(prefixIcon),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
              maxWidth: 176,
            ),
            suffixIcon: SizedBox(
              width: suffixWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  VoiceInputIconButton(
                    controller: controller,
                    tooltip: 'Nhập địa điểm bằng giọng nói',
                    stopTooltip: 'Dừng nhập giọng nói',
                    onTextChanged: onChanged,
                  ),
                  TtsIconButton(
                    controller: controller,
                    tooltip: 'Đọc nội dung ô nhập',
                    emptyMessage: 'Bạn chưa nhập địa điểm để đọc.',
                  ),
                  if (showLoading)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  if (showClear)
                    IconButton(
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showSuggestionBox)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: DefaultTabController(
              length: 2,
              initialIndex: initialTabIndex,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'Trạm'),
                      Tab(text: 'Địa chỉ'),
                    ],
                    labelColor: scheme.primary,
                    unselectedLabelColor: scheme.onSurfaceVariant,
                    indicatorColor: scheme.primary,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildSuggestionList(
                            stationSuggestions, onSuggestionTap),
                        _buildSuggestionList(
                            addressSuggestions, onSuggestionTap),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionList(
    List<_LocationSuggestion> items,
    ValueChanged<_LocationSuggestion> onSuggestionTap,
  ) {
    final scheme = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      return Center(
        child: Text(
          'Không có dữ liệu',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: scheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          dense: true,
          leading: Icon(item.icon, color: scheme.primary),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(item.subtitle),
          onTap: () => onSuggestionTap(item),
        );
      },
    );
  }

  Widget _buildResultsTab() {
    if (_paths.isEmpty) {
      return _buildEmptyState(
        title: 'Chưa có kết quả lộ trình',
        subtitle: 'Chọn điểm đi/đến rồi nhấn Tìm lộ trình.',
      );
    }

    final safeIndex =
        _selectedPathIndex >= 0 && _selectedPathIndex < _paths.length
            ? _selectedPathIndex
            : 0;
    final selectedPath = _paths[safeIndex];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildGuidanceCard(selectedPath),
        const SizedBox(height: 12),
        ..._paths.asMap().entries.map((entry) {
          final index = entry.key;
          final path = entry.value;
          final isSelected = index == _selectedPathIndex;
          return _buildPathCard(path, index + 1, isSelected);
        }),
      ],
    );
  }

  Widget _buildPathCard(PathResult path, int order, bool isSelected) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        if (_isSpeakingGuidance) {
          TextToSpeechService.instance.stop();
        }
        setState(() {
          _selectedPathIndex = order - 1;
          _isSpeakingGuidance = false;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Lộ trình $order',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle, color: scheme.primary, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _metricChip(Icons.schedule, path.formattedTime),
                _metricChip(Icons.straighten, path.formattedDistance),
                _metricChip(Icons.payments_outlined, path.formattedCost),
                _metricChip(
                  Icons.compare_arrows,
                  '${path.numberOfTransfers} lần chuyển',
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...path.segments.map(
              (segment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.directions_bus, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${segment.from} → ${segment.to}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${segment.time.toStringAsFixed(0)} phút',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    final scheme = Theme.of(context).colorScheme;

    if (_paths.isEmpty || _selectedPathIndex >= _paths.length) {
      return _buildEmptyState(
        title: 'Bản đồ lộ trình trống',
        subtitle: 'Sau khi tìm đường, lộ trình sẽ hiển thị tại đây.',
      );
    }

    final path = _paths[_selectedPathIndex];
    final points = path.stations
        .map((s) => LatLng(s.latitude, s.longitude))
        .toList(growable: false);
    final intermediateStations = path.stations.length > 2
        ? path.stations.sublist(1, path.stations.length - 1)
        : const <PathStationInfo>[];

    if (points.isEmpty) {
      return _buildEmptyState(
        title: 'Không có tọa độ lộ trình',
        subtitle: 'Dữ liệu hiện tại chưa đủ để hiển thị trên bản đồ.',
      );
    }

    final center = points.first;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.smartgo.app',
        ),
        if (points.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 6,
                color: Colors.white,
              ),
              Polyline(
                points: points,
                strokeWidth: 4,
                color: scheme.primary,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (points.isNotEmpty)
              Marker(
                point: points.first,
                width: 38,
                height: 38,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white),
                ),
              ),
            if (points.length > 1)
              Marker(
                point: points.last,
                width: 38,
                height: 38,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.flag, color: Colors.white),
                ),
              ),
            ...intermediateStations.map(
              (s) => Marker(
                point: LatLng(s.latitude, s.longitude),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.directions_bus,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationSuggestion {
  final String title;
  final String subtitle;
  final IconData icon;
  final LatLng point;
  final Station? station;

  const _LocationSuggestion({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.point,
    this.station,
  });
}
