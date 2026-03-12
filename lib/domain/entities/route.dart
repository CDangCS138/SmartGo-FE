import 'package:equatable/equatable.dart';

class BusRoute extends Equatable {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String routeCode;
  final String routeName;
  final String transportType;
  final RouteStatus status;
  final String operatorName;
  final String phoneNumber;
  final String vehicleType;
  final String startPoint;
  final String endPoint;
  final String frequency;
  final List<String> baseFare;
  final double totalDistance;
  final bool isWheelchairAccessible;
  final OperatingTime operatingTime;
  final String tripTime;
  final String numTrips;
  final Map<String, String> routeForwardCodes;
  final Map<String, String> routeBackwardCodes;
  const BusRoute({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.routeCode,
    required this.routeName,
    required this.transportType,
    required this.status,
    required this.operatorName,
    required this.phoneNumber,
    required this.vehicleType,
    required this.startPoint,
    required this.endPoint,
    required this.frequency,
    required this.baseFare,
    required this.totalDistance,
    required this.isWheelchairAccessible,
    required this.operatingTime,
    required this.tripTime,
    required this.numTrips,
    required this.routeForwardCodes,
    required this.routeBackwardCodes,
  });
  @override
  List<Object?> get props => [
        id,
        createdAt,
        updatedAt,
        routeCode,
        routeName,
        transportType,
        status,
        operatorName,
        phoneNumber,
        vehicleType,
        startPoint,
        endPoint,
        frequency,
        baseFare,
        totalDistance,
        isWheelchairAccessible,
        operatingTime,
        tripTime,
        numTrips,
        routeForwardCodes,
        routeBackwardCodes,
      ];
}

class OperatingTime extends Equatable {
  final String from;
  final String to;
  const OperatingTime({
    required this.from,
    required this.to,
  });
  @override
  List<Object?> get props => [from, to];
}

enum RouteStatus {
  active,
  inactive,
  underMaintenance,
  suspended;

  static RouteStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return RouteStatus.active;
      case 'INACTIVE':
        return RouteStatus.inactive;
      case 'UNDER_MAINTENANCE':
        return RouteStatus.underMaintenance;
      case 'SUSPENDED':
        return RouteStatus.suspended;
      default:
        return RouteStatus.active;
    }
  }

  String toApiString() {
    switch (this) {
      case RouteStatus.active:
        return 'ACTIVE';
      case RouteStatus.inactive:
        return 'INACTIVE';
      case RouteStatus.underMaintenance:
        return 'UNDER_MAINTENANCE';
      case RouteStatus.suspended:
        return 'SUSPENDED';
    }
  }
}

enum RouteDirection {
  forward,
  backward,
  both;

  static RouteDirection fromString(String direction) {
    switch (direction.toLowerCase()) {
      case 'forward':
        return RouteDirection.forward;
      case 'backward':
        return RouteDirection.backward;
      case 'both':
        return RouteDirection.both;
      default:
        return RouteDirection.both;
    }
  }

  String toApiString() {
    return name;
  }
}
