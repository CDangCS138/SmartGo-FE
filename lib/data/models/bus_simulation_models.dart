import 'package:equatable/equatable.dart';

enum BusSimulationStatus {
  scheduled,
  running,
  completed,
  unknown;

  static BusSimulationStatus fromString(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'SCHEDULED':
        return BusSimulationStatus.scheduled;
      case 'RUNNING':
        return BusSimulationStatus.running;
      case 'COMPLETED':
        return BusSimulationStatus.completed;
      default:
        return BusSimulationStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case BusSimulationStatus.scheduled:
        return 'SCHEDULED';
      case BusSimulationStatus.running:
        return 'RUNNING';
      case BusSimulationStatus.completed:
        return 'COMPLETED';
      case BusSimulationStatus.unknown:
        return 'UNKNOWN';
    }
  }
}

class BusStationEta extends Equatable {
  final String stationId;
  final int stationIndex;
  final String stationName;
  final double latitude;
  final double longitude;
  final DateTime? eta;
  final double minutesAway;
  final bool isReached;

  const BusStationEta({
    required this.stationId,
    required this.stationIndex,
    required this.stationName,
    required this.latitude,
    required this.longitude,
    required this.eta,
    required this.minutesAway,
    required this.isReached,
  });

  factory BusStationEta.fromJson(Map<String, dynamic> json) {
    return BusStationEta(
      stationId: _readStationId(json['stationId']),
      stationIndex: _readInt(json['stationIndex']),
      stationName: (json['stationName'] ?? '').toString(),
      latitude: _readDouble(json['latitude']),
      longitude: _readDouble(json['longitude']),
      eta: _readDateTime(json['eta']),
      minutesAway: _readDouble(json['minutesAway']),
      isReached: _readBool(json['isReached']),
    );
  }

  @override
  List<Object?> get props => [
        stationId,
        stationIndex,
        stationName,
        latitude,
        longitude,
        eta,
        minutesAway,
        isReached,
      ];
}

class BusSimulationTrip extends Equatable {
  final String tripId;
  final String routeId;
  final String routeCode;
  final String routeName;
  final DateTime? departureTime;
  final DateTime? expectedArrivalTime;
  final BusSimulationStatus status;
  final int tripDurationMinutes;
  final List<String> stationIds;

  const BusSimulationTrip({
    required this.tripId,
    required this.routeId,
    required this.routeCode,
    required this.routeName,
    required this.departureTime,
    required this.expectedArrivalTime,
    required this.status,
    required this.tripDurationMinutes,
    required this.stationIds,
  });

  factory BusSimulationTrip.fromJson(Map<String, dynamic> json) {
    return BusSimulationTrip(
      tripId: (json['tripId'] ?? '').toString(),
      routeId: (json['routeId'] ?? '').toString(),
      routeCode: (json['routeCode'] ?? '').toString(),
      routeName: (json['routeName'] ?? '').toString(),
      departureTime: _readDateTime(json['departureTime']),
      expectedArrivalTime: _readDateTime(json['expectedArrivalTime']),
      status: BusSimulationStatus.fromString(json['status']?.toString()),
      tripDurationMinutes: _readInt(json['tripDurationMinutes']),
      stationIds: _readStringList(json['stationIds']),
    );
  }

  @override
  List<Object?> get props => [
        tripId,
        routeId,
        routeCode,
        routeName,
        departureTime,
        expectedArrivalTime,
        status,
        tripDurationMinutes,
        stationIds,
      ];
}

class BusSimulationPosition extends Equatable {
  final String tripId;
  final String routeId;
  final String routeCode;
  final String routeName;
  final DateTime? timestamp;
  final double latitude;
  final double longitude;
  final int currentStationIndex;
  final String? currentStationId;
  final String? nextStationId;
  final double progressToNextStation;
  final BusSimulationStatus status;
  final DateTime? departureTime;
  final DateTime? expectedArrivalTime;
  final double elapsedMinutes;
  final double remainingMinutes;
  final List<BusStationEta> stationEtas;

  const BusSimulationPosition({
    required this.tripId,
    required this.routeId,
    required this.routeCode,
    required this.routeName,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.currentStationIndex,
    required this.currentStationId,
    required this.nextStationId,
    required this.progressToNextStation,
    required this.status,
    required this.departureTime,
    required this.expectedArrivalTime,
    required this.elapsedMinutes,
    required this.remainingMinutes,
    required this.stationEtas,
  });

  factory BusSimulationPosition.fromJson(Map<String, dynamic> json) {
    final rawStationEtas = json['stationEtas'];
    final stationEtas = rawStationEtas is List
        ? rawStationEtas
            .whereType<Map<String, dynamic>>()
            .map(BusStationEta.fromJson)
            .toList()
        : const <BusStationEta>[];

    return BusSimulationPosition(
      tripId: (json['tripId'] ?? '').toString(),
      routeId: (json['routeId'] ?? '').toString(),
      routeCode: (json['routeCode'] ?? '').toString(),
      routeName: (json['routeName'] ?? '').toString(),
      timestamp: _readDateTime(json['timestamp']),
      latitude: _readDouble(json['latitude']),
      longitude: _readDouble(json['longitude']),
      currentStationIndex: _readInt(json['currentStationIndex']),
      currentStationId: _readOptionalString(json['currentStationId']),
      nextStationId: _readStationIdOrNull(json['nextStationId']),
      progressToNextStation: _readDouble(json['progressToNextStation']),
      status: BusSimulationStatus.fromString(json['status']?.toString()),
      departureTime: _readDateTime(json['departureTime']),
      expectedArrivalTime: _readDateTime(json['expectedArrivalTime']),
      elapsedMinutes: _readDouble(json['elapsedMinutes']),
      remainingMinutes: _readDouble(json['remainingMinutes']),
      stationEtas: stationEtas,
    );
  }

  @override
  List<Object?> get props => [
        tripId,
        routeId,
        routeCode,
        routeName,
        timestamp,
        latitude,
        longitude,
        currentStationIndex,
        currentStationId,
        nextStationId,
        progressToNextStation,
        status,
        departureTime,
        expectedArrivalTime,
        elapsedMinutes,
        remainingMinutes,
        stationEtas,
      ];
}

class UpcomingBusAtStation extends Equatable {
  final String tripId;
  final String routeId;
  final String routeCode;
  final String routeName;
  final BusStationEta eta;

  const UpcomingBusAtStation({
    required this.tripId,
    required this.routeId,
    required this.routeCode,
    required this.routeName,
    required this.eta,
  });

  factory UpcomingBusAtStation.fromJson(Map<String, dynamic> json) {
    return UpcomingBusAtStation(
      tripId: (json['tripId'] ?? '').toString(),
      routeId: (json['routeId'] ?? '').toString(),
      routeCode: (json['routeCode'] ?? '').toString(),
      routeName: (json['routeName'] ?? '').toString(),
      eta: BusStationEta.fromJson(
        (json['eta'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
    );
  }

  @override
  List<Object?> get props => [tripId, routeId, routeCode, routeName, eta];
}

List<String> _readStringList(dynamic raw) {
  if (raw is! List) {
    return const <String>[];
  }
  return raw.map((item) => item.toString()).toList();
}

DateTime? _readDateTime(dynamic raw) {
  if (raw == null) {
    return null;
  }

  if (raw is DateTime) {
    return raw;
  }

  final text = raw.toString().trim();
  if (text.isEmpty) {
    return null;
  }

  return DateTime.tryParse(text);
}

double _readDouble(dynamic raw, {double fallback = 0}) {
  if (raw is num) {
    return raw.toDouble();
  }
  return double.tryParse(raw?.toString() ?? '') ?? fallback;
}

int _readInt(dynamic raw, {int fallback = 0}) {
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

bool _readBool(dynamic raw, {bool fallback = false}) {
  if (raw is bool) {
    return raw;
  }
  final normalized = (raw ?? '').toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') {
    return true;
  }
  if (normalized == 'false' || normalized == '0') {
    return false;
  }
  return fallback;
}

String _readStationId(dynamic raw) {
  return _readStationIdOrNull(raw) ?? '';
}

String? _readStationIdOrNull(dynamic raw) {
  if (raw == null) {
    return null;
  }

  if (raw is String) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  if (raw is Map<String, dynamic>) {
    final nested = raw['_id'] ?? raw['id'] ?? raw['stationId'];
    if (nested == null) {
      return null;
    }
    final value = nested.toString().trim();
    return value.isEmpty ? null : value;
  }

  final fallback = raw.toString().trim();
  if (fallback.isEmpty || fallback == '{}' || fallback == 'null') {
    return null;
  }
  return fallback;
}

String? _readOptionalString(dynamic raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty || value == 'null') {
    return null;
  }
  return value;
}
