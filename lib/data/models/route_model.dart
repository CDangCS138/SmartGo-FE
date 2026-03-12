import 'package:smartgo/domain/entities/route.dart';

class RouteModel extends BusRoute {
  const RouteModel({
    required super.id,
    required super.createdAt,
    required super.updatedAt,
    required super.routeCode,
    required super.routeName,
    required super.transportType,
    required super.status,
    required super.operatorName,
    required super.phoneNumber,
    required super.vehicleType,
    required super.startPoint,
    required super.endPoint,
    required super.frequency,
    required super.baseFare,
    required super.totalDistance,
    required super.isWheelchairAccessible,
    required super.operatingTime,
    required super.tripTime,
    required super.numTrips,
    required super.routeForwardCodes,
    required super.routeBackwardCodes,
  });
  factory RouteModel.fromJson(Map<String, dynamic> json) {
    // Handle operatingTime as object OR as separate start/end fields
    OperatingTime operatingTime;
    if (json['operatingTime'] != null) {
      operatingTime = OperatingTimeModel.fromJson(
          json['operatingTime'] as Map<String, dynamic>);
    } else {
      operatingTime = OperatingTimeModel(
        from: (json['operatingTimeStart'] ?? '') as String,
        to: (json['operatingTimeEnd'] ?? '') as String,
      );
    }

    // Handle routeForwardCodes/routeBackwardCodes OR stationIds + isOutbound
    Map<String, String> forwardCodes =
        (json['routeForwardCodes'] as Map<String, dynamic>?)
                ?.map((key, value) => MapEntry(key, (value ?? '') as String)) ??
            {};
    Map<String, String> backwardCodes =
        (json['routeBackwardCodes'] as Map<String, dynamic>?)
                ?.map((key, value) => MapEntry(key, (value ?? '') as String)) ??
            {};

    if (forwardCodes.isEmpty && backwardCodes.isEmpty) {
      final stationIds = (json['stationIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];
      if (stationIds.isNotEmpty) {
        final isOutbound = (json['isOutbound'] as bool?) ?? true;
        final codesMap = {for (final id in stationIds) id: ''};
        if (isOutbound) {
          forwardCodes = codesMap;
        } else {
          backwardCodes = codesMap;
        }
      }
    }

    return RouteModel(
      id: json['_id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      routeCode: (json['routeCode'] ?? '') as String,
      routeName: (json['routeName'] ?? '') as String,
      transportType: (json['transportType'] ?? '') as String,
      status: RouteStatus.fromString((json['status'] ?? 'active') as String),
      operatorName: (json['operatorName'] ?? '') as String,
      phoneNumber: (json['phoneNumber'] ?? '') as String,
      vehicleType: (json['vehicleType'] ?? '') as String,
      startPoint: (json['startPoint'] ?? '') as String,
      endPoint: (json['endPoint'] ?? '') as String,
      frequency: (json['frequency'] ?? '') as String,
      baseFare: (json['baseFare'] as List<dynamic>?)
              ?.map((e) => (e ?? '') as String)
              .toList() ??
          [],
      totalDistance: ((json['totalDistance'] as num?) ?? 0).toDouble(),
      isWheelchairAccessible:
          (json['isWheelchairAccessible'] as bool?) ?? false,
      operatingTime: operatingTime,
      tripTime: (json['tripTime'] ?? '') as String,
      numTrips: (json['numTrips'] ?? '') as String,
      routeForwardCodes: forwardCodes,
      routeBackwardCodes: backwardCodes,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'routeCode': routeCode,
      'routeName': routeName,
      'transportType': transportType,
      'status': status.toApiString(),
      'operatorName': operatorName,
      'phoneNumber': phoneNumber,
      'vehicleType': vehicleType,
      'startPoint': startPoint,
      'endPoint': endPoint,
      'frequency': frequency,
      'baseFare': baseFare,
      'totalDistance': totalDistance,
      'isWheelchairAccessible': isWheelchairAccessible,
      'operatingTime': OperatingTimeModel(
        from: operatingTime.from,
        to: operatingTime.to,
      ).toJson(),
      'tripTime': tripTime,
      'numTrips': numTrips,
      'routeForwardCodes': routeForwardCodes,
      'routeBackwardCodes': routeBackwardCodes,
    };
  }
}

class OperatingTimeModel extends OperatingTime {
  const OperatingTimeModel({
    required super.from,
    required super.to,
  });
  factory OperatingTimeModel.fromJson(Map<String, dynamic> json) {
    return OperatingTimeModel(
      from: (json['from'] ?? '') as String,
      to: (json['to'] ?? '') as String,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
    };
  }
}

class RouteListResponse {
  final int statusCode;
  final String message;
  final RouteListData data;
  const RouteListResponse({
    required this.statusCode,
    required this.message,
    required this.data,
  });
  factory RouteListResponse.fromJson(Map<String, dynamic> json) {
    return RouteListResponse(
      statusCode: json['statusCode'] as int,
      message: json['message'] as String,
      data: RouteListData.fromJson(json['data'] as Map<String, dynamic>),
    );
  }
}

class RouteListData {
  final int total;
  final int page;
  final int limit;
  final List<RouteModel> routes;
  const RouteListData({
    required this.total,
    required this.page,
    required this.limit,
    required this.routes,
  });
  factory RouteListData.fromJson(Map<String, dynamic> json) {
    return RouteListData(
      total: json['total'] as int,
      page: json['page'] as int,
      limit: json['limit'] as int,
      routes: (json['routes'] as List<dynamic>)
          .map((e) => RouteModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RouteResponse {
  final int statusCode;
  final String message;
  final RouteModel data;
  const RouteResponse({
    required this.statusCode,
    required this.message,
    required this.data,
  });
  factory RouteResponse.fromJson(Map<String, dynamic> json) {
    final dataField = json['data'] as Map<String, dynamic>;
    // API may return data.route (getById) or data directly
    final routeJson = dataField.containsKey('route')
        ? dataField['route'] as Map<String, dynamic>
        : dataField;
    return RouteResponse(
      statusCode: json['statusCode'] as int,
      message: json['message'] as String,
      data: RouteModel.fromJson(routeJson),
    );
  }
}
