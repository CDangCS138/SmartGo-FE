import 'package:equatable/equatable.dart';

class Station extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String stationCode;
  final String stationName;
  final double latitude;
  final double longitude;
  final String condition;
  final String stopCategory;
  final String streetName;
  final String addressNo;
  final bool hasWheelchair;
  final bool hasRamp;
  final StationType stationType;
  final StationStatus status;

  const Station({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.stationCode,
    required this.stationName,
    required this.latitude,
    required this.longitude,
    required this.condition,
    required this.stopCategory,
    required this.streetName,
    required this.addressNo,
    required this.hasWheelchair,
    required this.hasRamp,
    required this.stationType,
    required this.status,
  });

  String get fullAddress => '$addressNo $streetName'.trim();

  @override
  List<Object?> get props => [
        id,
        createdAt,
        updatedAt,
        stationCode,
        stationName,
        latitude,
        longitude,
        condition,
        stopCategory,
        streetName,
        addressNo,
        hasWheelchair,
        hasRamp,
        stationType,
        status,
      ];
}

enum StationType {
  BUS_STOP,
  METRO_STATION,
  FERRY_TERMINAL,
  TRANSIT_HUB,
  UNKNOWN;

  static StationType fromString(String value) {
    switch (value) {
      case 'BUS_STOP':
        return StationType.BUS_STOP;
      case 'METRO_STATION':
        return StationType.METRO_STATION;
      case 'FERRY_TERMINAL':
        return StationType.FERRY_TERMINAL;
      case 'TRANSIT_HUB':
        return StationType.TRANSIT_HUB;
      default:
        return StationType.UNKNOWN;
    }
  }

  String toJson() => name;
}

enum StationStatus {
  ACTIVE,
  INACTIVE,
  UNDER_MAINTENANCE,
  UNKNOWN;

  static StationStatus fromString(String value) {
    switch (value) {
      case 'ACTIVE':
        return StationStatus.ACTIVE;
      case 'INACTIVE':
        return StationStatus.INACTIVE;
      case 'UNDER_MAINTENANCE':
        return StationStatus.UNDER_MAINTENANCE;
      default:
        return StationStatus.UNKNOWN;
    }
  }

  String toJson() => name;
}
