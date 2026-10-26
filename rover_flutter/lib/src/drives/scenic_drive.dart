import '../api/rover_api_client.dart';
import '../location/rover_location.dart';
export 'drive_interest_catalog.dart';

class DrivePreferences {
  const DrivePreferences({
    this.preferLocalRoads = false,
    this.avoidTolls = false,
    this.maxDetourMinutes = 15,
    this.includeRestStops = false,
    this.includeChargingStops = false,
  });
  final bool preferLocalRoads,
      avoidTolls,
      includeRestStops,
      includeChargingStops;
  final int maxDetourMinutes;
  Map<String, dynamic> toJson() => {
    'preferLocalRoads': preferLocalRoads,
    'avoidTolls': avoidTolls,
    'maxDetourMinutes': maxDetourMinutes,
    'includeRestStops': includeRestStops,
    'includeChargingStops': includeChargingStops,
  };
  factory DrivePreferences.fromJson(Map<String, dynamic> json) =>
      DrivePreferences(
        preferLocalRoads: json['preferLocalRoads'] == true,
        avoidTolls: json['avoidTolls'] == true,
        maxDetourMinutes: (json['maxDetourMinutes'] as int? ?? 15).clamp(5, 60),
        includeRestStops: json['includeRestStops'] == true,
        includeChargingStops: json['includeChargingStops'] == true,
      );
}

RoverLatLng _point(Map<String, dynamic> json) => RoverLatLng(
  latitude: (json['latitude'] as num).toDouble(),
  longitude: (json['longitude'] as num).toDouble(),
);
Map<String, double> _coordinates(RoverLatLng p) => {
  'latitude': p.latitude,
  'longitude': p.longitude,
};

class DrivePlace {
  const DrivePlace({
    required this.id,
    required this.name,
    required this.location,
    this.address,
    this.attribution = '',
  });
  final String id;
  final String name;
  final String? address;
  final String attribution;
  final RoverLatLng location;
  factory DrivePlace.fromJson(Map<String, dynamic> json) => DrivePlace(
    id: json['placeId'] as String,
    name: json['name'] as String,
    location: _point(json['location'] as Map<String, dynamic>),
    address: json['address'] as String?,
    attribution: json['attribution'] as String? ?? '',
  );
}

class DriveSearch {
  const DriveSearch(this.places, this.warnings);
  final List<DrivePlace> places;
  final List<String> warnings;
}

class DriveRequest {
  const DriveRequest({
    required this.origin,
    required this.destination,
    required this.query,
    required this.returnToStart,
    required this.availableMinutes,
    required this.minutesPerStop,
    required this.interests,
    this.preferences = const DrivePreferences(),
  });
  final RoverLatLng origin;
  final DrivePlace destination;
  final String query;
  final bool returnToStart;
  final int availableMinutes;
  final int minutesPerStop;
  final List<String> interests;
  final DrivePreferences preferences;
  Map<String, dynamic> toJson() => {
    'origin': _coordinates(origin),
    'destination': {
      'query': query,
      'placeId': destination.id,
      'isDestination': true,
    },
    'returnToStart': returnToStart,
    'availableMinutes': availableMinutes,
    'minutesPerStop': minutesPerStop,
    'interests': interests,
    'maxOptionalStops': 6,
    'preferences': preferences.toJson(),
  };
}

class DrivePlan {
  const DrivePlan({
    required this.origin,
    required this.destination,
    required this.returnToStart,
    required this.stops,
    required this.geometry,
    required this.drivingMinutes,
    required this.distanceMeters,
    required this.stopMinutes,
    required this.bufferMinutes,
    required this.totalMinutes,
    required this.availableMinutes,
    required this.fitsBudget,
    required this.warnings,
    this.preferences = const DrivePreferences(),
  });
  final RoverLatLng origin;
  final DrivePlace destination;
  final bool returnToStart;
  final List<DrivePlace> stops;
  final List<RoverLatLng> geometry;
  final int drivingMinutes,
      distanceMeters,
      stopMinutes,
      bufferMinutes,
      totalMinutes,
      availableMinutes;
  final bool fitsBudget;
  final List<String> warnings;
  final DrivePreferences preferences;
  factory DrivePlan.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as Map<String, dynamic>;
    return DrivePlan(
      origin: _point(json['origin'] as Map<String, dynamic>),
      destination: DrivePlace.fromJson(
        json['destination'] as Map<String, dynamic>,
      ),
      returnToStart: json['returnToStart'] as bool,
      stops: (json['stops'] as List)
          .map((p) => DrivePlace.fromJson(p as Map<String, dynamic>))
          .toList(),
      geometry: (route['geometry'] as List)
          .map((p) => _point(p as Map<String, dynamic>))
          .toList(),
      drivingMinutes: route['drivingMinutes'] as int,
      distanceMeters: route['distanceMeters'] as int,
      stopMinutes: json['stopMinutes'] as int,
      bufferMinutes: json['bufferMinutes'] as int,
      totalMinutes: json['totalMinutes'] as int,
      availableMinutes: json['availableMinutes'] as int,
      fitsBudget: json['fitsBudget'] as bool,
      warnings: (json['warnings'] as List).cast<String>(),
      preferences: DrivePreferences.fromJson(
        json['preferences'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
  List<DrivePlace> get visits => [
    ...stops,
    destination,
    if (returnToStart)
      DrivePlace(id: 'start', name: 'Starting location', location: origin),
  ];
  int get navigationSections => (visits.length / 4).ceil();
  // Each section contains at most three intermediate waypoints.
  Uri directions({DrivePlace? leg, int section = 0}) {
    if (section < 0 || section >= navigationSections) {
      throw RangeError.index(section, List.filled(navigationSections, 0));
    }
    String position(RoverLatLng p) => '${p.latitude},${p.longitude}';
    final points = visits
        .skip(section * 4)
        .take(4)
        .map((p) => p.location)
        .toList();
    final start = section == 0 ? origin : visits[section * 4 - 1].location;
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'travelmode': 'driving',
      if (leg == null) 'origin': position(start),
      'destination': position(leg?.location ?? points.last),
      if (leg != null) 'dir_action': 'navigate',
      if (leg == null && points.length > 1)
        'waypoints': points.take(points.length - 1).map(position).join('|'),
      if (preferences.preferLocalRoads || preferences.avoidTolls)
        'avoid': [
          if (preferences.preferLocalRoads) 'highways',
          if (preferences.avoidTolls) 'tolls',
        ].join(','),
    });
  }
}

abstract interface class ScenicDriveRepository {
  Future<DriveSearch> search(String query, RoverLatLng origin);
  Future<DrivePlan> plan(DriveRequest request);
}

class HttpScenicDriveRepository implements ScenicDriveRepository {
  HttpScenicDriveRepository({RoverApiClient? client})
    : _client = client ?? RoverApiClient();
  final RoverApiClient _client;
  @override
  Future<DriveSearch> search(String query, RoverLatLng origin) async {
    final json = await _client.searchDrivePlaces(
      query,
      origin.latitude,
      origin.longitude,
    );
    return DriveSearch(
      (json['places'] as List)
          .map((p) => DrivePlace.fromJson(p as Map<String, dynamic>))
          .toList(),
      (json['warnings'] as List).cast<String>(),
    );
  }

  @override
  Future<DrivePlan> plan(DriveRequest request) async =>
      DrivePlan.fromJson(await _client.planScenicDrive(request.toJson()));
}
