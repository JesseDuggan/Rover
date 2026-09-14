import '../adventure/roam.dart';
import '../location/rover_location.dart';

Map<String, dynamic> routeToJson(RoverRoam route) => {
  'title': route.title,
  'summary': route.summary,
  'walkingMinutes': route.walkingMinutes,
  'distanceMiles': route.distanceMiles,
  'startingPoint': route.startingPoint,
  'routeProvider': route.routeProvider,
  'walkSessionId': route.walkSessionId,
  'accessibilityNotes': route.accessibilityNotes,
  'warnings': route.warnings,
  'routeGeometry': route.routeGeometry.map(_pointToJson).toList(),
  'stops': route.stops
      .map(
        (stop) => {
          'id': stop.id,
          'name': stop.name,
          'image': stop.image,
          'shortDescription': stop.shortDescription,
          'estimatedVisitMinutes': stop.estimatedVisitMinutes,
          'category': stop.category,
          'whySelected': stop.whySelected,
          'distanceFromPreviousStopMeters': stop.distanceFromPreviousStopMeters,
          'arrivalRadiusMeters': stop.arrivalRadiusMeters,
          'audio': stop.audio,
          'narration': stop.narration,
          'contentType': stop.contentType,
          'contentSource': stop.contentSource,
          'sponsoredDisclosure': stop.sponsoredDisclosure,
          'address': stop.address,
          'websiteUrl': stop.websiteUrl,
          'phoneNumber': stop.phoneNumber,
          'menuUrl': stop.menuUrl,
          'discoveryProviderName': stop.discoveryProviderName,
          'providerPlaceId': stop.providerPlaceId,
          'sourceUrl': stop.sourceUrl,
          'coordinates': _pointToJson(stop.coordinates),
          'requiredAttribution': stop.requiredAttribution,
        },
      )
      .toList(),
  'routeManeuvers': route.routeManeuvers
      .map(
        (m) => {
          'sequenceNumber': m.sequenceNumber,
          'instruction': m.instruction,
          'distanceMeters': m.distanceMeters,
          'durationMinutes': m.durationMinutes,
          'maneuverType': m.maneuverType,
          'location': m.location == null ? null : _pointToJson(m.location!),
        },
      )
      .toList(),
};

RoverRoam routeFromJson(Map<String, dynamic> data) => RoverRoam(
  title: data['title'] as String,
  summary: data['summary'] as String,
  walkingMinutes: data['walkingMinutes'] as int,
  distanceMiles: (data['distanceMiles'] as num).toDouble(),
  startingPoint: data['startingPoint'] as String,
  routeProvider: data['routeProvider'] as String,
  walkSessionId: data['walkSessionId'] as String?,
  accessibilityNotes: List<String>.from(data['accessibilityNotes'] as List),
  warnings: List<String>.from(data['warnings'] as List),
  routeGeometry: (data['routeGeometry'] as List)
      .map((p) => _pointFromJson(p as Map<String, dynamic>))
      .toList(),
  stops: (data['stops'] as List).map((value) {
    final stop = value as Map<String, dynamic>;
    return RoverStop(
      id: stop['id'] as String,
      name: stop['name'] as String,
      image: stop['image'] as String,
      shortDescription: stop['shortDescription'] as String,
      estimatedVisitMinutes: stop['estimatedVisitMinutes'] as int,
      category: stop['category'] as String,
      whySelected: stop['whySelected'] as String,
      distanceFromPreviousStopMeters:
          stop['distanceFromPreviousStopMeters'] as int,
      arrivalRadiusMeters: stop['arrivalRadiusMeters'] as int,
      audio: stop['audio'] as String?,
      narration: stop['narration'] as String?,
      contentType: stop['contentType'] as String?,
      contentSource: stop['contentSource'] as String?,
      sponsoredDisclosure: stop['sponsoredDisclosure'] as String?,
      address: stop['address'] as String?,
      websiteUrl: stop['websiteUrl'] as String?,
      phoneNumber: stop['phoneNumber'] as String?,
      menuUrl: stop['menuUrl'] as String?,
      discoveryProviderName: stop['discoveryProviderName'] as String?,
      providerPlaceId: stop['providerPlaceId'] as String?,
      sourceUrl: stop['sourceUrl'] as String?,
      coordinates: _pointFromJson(stop['coordinates'] as Map<String, dynamic>),
      requiredAttribution: List<String>.from(
        stop['requiredAttribution'] as List,
      ),
    );
  }).toList(),
  routeManeuvers: (data['routeManeuvers'] as List).map((value) {
    final m = value as Map<String, dynamic>;
    return RoverRouteManeuver(
      sequenceNumber: m['sequenceNumber'] as int,
      instruction: m['instruction'] as String,
      distanceMeters: m['distanceMeters'] as int,
      durationMinutes: m['durationMinutes'] as int,
      maneuverType: m['maneuverType'] as String,
      location: m['location'] == null
          ? null
          : _pointFromJson(m['location'] as Map<String, dynamic>),
    );
  }).toList(),
);

Map<String, dynamic> _pointToJson(RoverLatLng p) => {
  'latitude': p.latitude,
  'longitude': p.longitude,
};
RoverLatLng _pointFromJson(Map<String, dynamic> p) => RoverLatLng(
  latitude: (p['latitude'] as num).toDouble(),
  longitude: (p['longitude'] as num).toDouble(),
);
