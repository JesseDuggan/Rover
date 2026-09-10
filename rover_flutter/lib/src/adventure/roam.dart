import 'dart:math' as math;

import '../location/rover_location.dart';
import 'adventure_request.dart';

class RoverStop {
  const RoverStop({
    required this.id,
    required this.name,
    required this.image,
    required this.shortDescription,
    required this.estimatedVisitMinutes,
    required this.coordinates,
    required this.category,
    required this.whySelected,
    this.distanceFromPreviousStopMeters = 0,
    this.arrivalRadiusMeters = 40,
    this.audio,
    this.narration,
    this.contentType,
    this.contentSource,
    this.sponsoredDisclosure,
    this.address,
    this.websiteUrl,
    this.phoneNumber,
    this.menuUrl,
    this.discoveryProviderName,
    this.providerPlaceId,
    this.sourceUrl,
    this.requiredAttribution = const [],
  });

  final String id;
  final String name;
  final String image;
  final String shortDescription;
  final int estimatedVisitMinutes;
  final RoverLatLng coordinates;
  final String category;
  final String whySelected;
  final int distanceFromPreviousStopMeters;
  final int arrivalRadiusMeters;
  final String? audio;
  final String? narration;
  final String? contentType;
  final String? contentSource;
  final String? sponsoredDisclosure;
  final String? address;
  final String? websiteUrl;
  final String? phoneNumber;
  final String? menuUrl;
  final String? discoveryProviderName;
  final String? providerPlaceId;
  final String? sourceUrl;
  final List<String> requiredAttribution;

  String? get attributionLabel => requiredAttribution.isEmpty
      ? null
      : requiredAttribution.toSet().join(', ');

  bool get isSponsored =>
      contentSource?.toLowerCase() == 'sponsored' ||
      sponsoredDisclosure != null;

  RoverStop copyWith({
    String? id,
    String? name,
    String? image,
    String? shortDescription,
    int? estimatedVisitMinutes,
    RoverLatLng? coordinates,
    String? category,
    String? whySelected,
    int? distanceFromPreviousStopMeters,
    int? arrivalRadiusMeters,
    String? audio,
    String? narration,
    String? contentType,
    String? contentSource,
    String? sponsoredDisclosure,
    String? address,
    String? websiteUrl,
    String? phoneNumber,
    String? menuUrl,
    String? discoveryProviderName,
    String? providerPlaceId,
    String? sourceUrl,
    List<String>? requiredAttribution,
  }) {
    return RoverStop(
      id: id ?? this.id,
      name: name ?? this.name,
      image: image ?? this.image,
      shortDescription: shortDescription ?? this.shortDescription,
      estimatedVisitMinutes:
          estimatedVisitMinutes ?? this.estimatedVisitMinutes,
      coordinates: coordinates ?? this.coordinates,
      category: category ?? this.category,
      whySelected: whySelected ?? this.whySelected,
      distanceFromPreviousStopMeters:
          distanceFromPreviousStopMeters ?? this.distanceFromPreviousStopMeters,
      arrivalRadiusMeters: arrivalRadiusMeters ?? this.arrivalRadiusMeters,
      audio: audio ?? this.audio,
      narration: narration ?? this.narration,
      contentType: contentType ?? this.contentType,
      contentSource: contentSource ?? this.contentSource,
      sponsoredDisclosure: sponsoredDisclosure ?? this.sponsoredDisclosure,
      address: address ?? this.address,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      menuUrl: menuUrl ?? this.menuUrl,
      discoveryProviderName:
          discoveryProviderName ?? this.discoveryProviderName,
      providerPlaceId: providerPlaceId ?? this.providerPlaceId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      requiredAttribution: requiredAttribution ?? this.requiredAttribution,
    );
  }
}

class OrderedRoverStop {
  const OrderedRoverStop({required this.sequence, required this.stop});

  final int sequence;
  final RoverStop stop;
}

class RoverRouteManeuver {
  const RoverRouteManeuver({
    required this.sequenceNumber,
    required this.instruction,
    required this.distanceMeters,
    required this.durationMinutes,
    required this.maneuverType,
    this.location,
  });

  final int sequenceNumber;
  final String instruction;
  final int distanceMeters;
  final int durationMinutes;
  final String maneuverType;
  final RoverLatLng? location;
}

class RoverRoam {
  const RoverRoam({
    required this.title,
    required this.summary,
    required this.walkingMinutes,
    required this.distanceMiles,
    required this.startingPoint,
    required this.stops,
    required this.routeGeometry,
    required this.accessibilityNotes,
    required this.warnings,
    this.routeProvider = 'Mock',
    this.routeManeuvers = const [],
    this.walkSessionId,
  });

  final String title;
  final String summary;
  final int walkingMinutes;
  final double distanceMiles;
  final String startingPoint;
  final List<RoverStop> stops;
  final List<RoverLatLng> routeGeometry;
  final List<String> accessibilityNotes;
  final List<String> warnings;
  final String routeProvider;
  final List<RoverRouteManeuver> routeManeuvers;
  final String? walkSessionId;

  int get contentMinutes {
    return stops.fold(0, (total, stop) => total + stop.estimatedVisitMinutes);
  }

  int get totalEstimatedMinutes => walkingMinutes + contentMinutes;

  List<OrderedRoverStop> get orderedStops {
    return [
      for (var index = 0; index < stops.length; index++)
        OrderedRoverStop(sequence: index + 1, stop: stops[index]),
    ];
  }

  RoverRoam copyWith({
    String? title,
    String? summary,
    int? walkingMinutes,
    double? distanceMiles,
    String? startingPoint,
    List<RoverStop>? stops,
    List<RoverLatLng>? routeGeometry,
    List<String>? accessibilityNotes,
    List<String>? warnings,
    String? routeProvider,
    List<RoverRouteManeuver>? routeManeuvers,
    String? walkSessionId,
  }) {
    final nextStops = stops ?? this.stops;
    final nextGeometry =
        routeGeometry ?? nextStops.map((stop) => stop.coordinates).toList();
    return RoverRoam(
      title: title ?? this.title,
      summary: summary ?? this.summary,
      walkingMinutes: walkingMinutes ?? _walkingMinutesFor(nextStops),
      distanceMiles: distanceMiles ?? _distanceFor(nextStops),
      startingPoint: startingPoint ?? this.startingPoint,
      stops: List.unmodifiable(nextStops),
      routeGeometry: List.unmodifiable(nextGeometry),
      accessibilityNotes: accessibilityNotes ?? this.accessibilityNotes,
      warnings: warnings ?? this.warnings,
      routeProvider: routeProvider ?? this.routeProvider,
      routeManeuvers: routeManeuvers ?? this.routeManeuvers,
      walkSessionId: walkSessionId ?? this.walkSessionId,
    );
  }

  RoverRoam removeStop(String stopId) {
    return copyWith(stops: stops.where((stop) => stop.id != stopId).toList());
  }

  RoverRoam replaceStop(String stopId, RoverStop replacement) {
    return copyWith(
      stops: [for (final stop in stops) stop.id == stopId ? replacement : stop],
    );
  }

  RoverRoam reorderStop(int oldIndex, int newIndex) {
    final updated = [...stops];
    final stop = updated.removeAt(oldIndex);
    updated.insert(newIndex.clamp(0, updated.length), stop);
    return copyWith(stops: updated);
  }

  bool fitsBudget(int availableMinutes) {
    return totalEstimatedMinutes <= availableMinutes;
  }

  static int _walkingMinutesFor(List<RoverStop> stops) {
    if (stops.length <= 1) {
      return 8;
    }
    return 8 + ((stops.length - 1) * 7);
  }

  static double _distanceFor(List<RoverStop> stops) {
    if (stops.length <= 1) {
      return 0.3;
    }
    var distance = 0.0;
    for (var index = 1; index < stops.length; index++) {
      distance += _distanceBetween(
        stops[index - 1].coordinates,
        stops[index].coordinates,
      );
    }
    return double.parse(math.max(0.3, distance).toStringAsFixed(1));
  }

  static double _distanceBetween(RoverLatLng a, RoverLatLng b) {
    final latMiles = (a.latitude - b.latitude).abs() * 69;
    final lngMiles =
        (a.longitude - b.longitude).abs() *
        69 *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt((latMiles * latMiles) + (lngMiles * lngMiles));
  }
}

class MockRouteGenerationService {
  const MockRouteGenerationService();

  RoverRoam generate(AdventureRequest request) {
    final roam = _generateSample(request);
    return _fitToBudget(roam, request.availableMinutes);
  }

  RoverRoam _generateSample(AdventureRequest request) {
    if (request.startingPoint.toLowerCase().contains('san francisco')) {
      return sanFrancisco90(startingPoint: request.startingPoint);
    }
    if (request.companions == 'Family' ||
        request.startingPoint.toLowerCase().contains('new york')) {
      return familyNewYork(startingPoint: request.startingPoint);
    }
    return shortLocalDiscovery(startingPoint: request.startingPoint);
  }

  RoverRoam _fitToBudget(RoverRoam roam, int availableMinutes) {
    var fitted = roam;
    while (!fitted.fitsBudget(availableMinutes) && fitted.stops.length > 1) {
      fitted = fitted.removeStop(fitted.stops.last.id);
    }
    return fitted;
  }

  RoverRoam regenerate(RoverRoam roam) {
    return roam.copyWith(
      title: '${roam.title} refreshed',
      warnings: const [
        'Fresh mock route generated. Check hours before heading out.',
      ],
    );
  }

  RoverStop replacementFor(RoverStop stop) {
    return RoverStop(
      id: '${stop.id}-swap',
      name: 'Nearby ${stop.category} surprise',
      image: 'mock://route/nearby-${stop.category.toLowerCase()}',
      shortDescription: 'A flexible alternate stop in the same spirit.',
      estimatedVisitMinutes: stop.estimatedVisitMinutes,
      coordinates: RoverLatLng(
        latitude: stop.coordinates.latitude + 0.0012,
        longitude: stop.coordinates.longitude - 0.0011,
      ),
      category: stop.category,
      whySelected: 'It keeps the ROAM on budget while changing the texture.',
      audio: stop.audio,
    );
  }

  static RoverRoam sanFrancisco90({String startingPoint = 'Ferry Building'}) {
    return RoverRoam(
      title: 'Bayfront stories and hidden corners',
      summary: 'A breezy San Francisco ROAM with food history, public art, and waterfront views.',
      walkingMinutes: 34,
      distanceMiles: 1.6,
      startingPoint: startingPoint,
      routeGeometry: _sfStops.map((stop) => stop.coordinates).toList(),
      accessibilityNotes: const [
        'Mostly flat waterfront route with curb cuts near major crossings.',
        'Ferry Building and plaza stops have step-free alternatives.',
      ],
      warnings: const ['Bay wind can pick up quickly. Bring a light layer.'],
      stops: _sfStops,
    );
  }

  static RoverRoam activeSanFranciscoDemo({
    String startingPoint = 'Union Square',
  }) {
    return RoverRoam(
      title: 'Union Square to Coit Tower story walk',
      summary: 'A demo ROAM from Union Square through nearby history, current city texture, movie lore, and a Coit Tower next-up finale.',
      walkingMinutes: 38,
      distanceMiles: 1.8,
      startingPoint: startingPoint,
      routeGeometry: _sfDemoStops.map((stop) => stop.coordinates).toList(),
      accessibilityNotes: const [
        'Demo mode follows a simplified route. Real hill grades and curb cuts need live routing later.',
        'Coit Tower approaches can be steep; choose accessible route mode for a gentler future route.',
      ],
      warnings: const [
        'Mock current-events note: downtown construction patterns can change quickly.',
      ],
      stops: _sfDemoStops,
    );
  }

  static RoverRoam familyNewYork({String startingPoint = 'Bryant Park'}) {
    return RoverRoam(
      title: 'Midtown family discovery loop',
      summary: 'A kid-friendly NYC route with short hops, visual landmarks, and snack flexibility.',
      walkingMinutes: 31,
      distanceMiles: 1.2,
      startingPoint: startingPoint,
      routeGeometry: _nycStops.map((stop) => stop.coordinates).toList(),
      accessibilityNotes: const [
        'Short blocks and frequent benches support mixed walking speeds.',
        'Use elevator entrances where available around transit corridors.',
      ],
      warnings: const ['Library exhibit rooms may close for private events.'],
      stops: _nycStops,
    );
  }

  static RoverRoam shortLocalDiscovery({
    String startingPoint = 'Current location',
  }) {
    return RoverRoam(
      title: 'Short local discovery walk',
      summary: 'A compact neighborhood wander for a quick reset without over-planning.',
      walkingMinutes: 18,
      distanceMiles: 0.7,
      startingPoint: startingPoint,
      routeGeometry: _localStops.map((stop) => stop.coordinates).toList(),
      accessibilityNotes: const [
        'Designed for a slower pace with nearby bailout points.',
      ],
      warnings: const [],
      stops: _localStops,
    );
  }
}

const _sfStops = [
  RoverStop(
    id: 'sf-ferry',
    name: 'Ferry Building Arcade',
    image: 'mock://sf/ferry-building',
    shortDescription: 'Food stalls, old transit stories, and bay light.',
    estimatedVisitMinutes: 14,
    coordinates: RoverLatLng(latitude: 37.79549, longitude: -122.39371),
    category: 'Food',
    audio: 'mock://audio/sf-ferry',
    whySelected: 'It anchors the route with history and easy food options.',
  ),
  RoverStop(
    id: 'sf-embarcadero',
    name: 'Embarcadero Ribbon',
    image: 'mock://sf/embarcadero',
    shortDescription: 'A flat waterfront stretch with big skyline payoffs.',
    estimatedVisitMinutes: 10,
    coordinates: RoverLatLng(latitude: 37.79712, longitude: -122.39711),
    category: 'Architecture',
    whySelected:
        'It keeps walking pleasant while connecting the stops cleanly.',
  ),
  RoverStop(
    id: 'sf-levi',
    name: 'Levi Plaza Steps',
    image: 'mock://sf/levi-plaza',
    shortDescription: 'Quiet brick paths and a small urban-water surprise.',
    estimatedVisitMinutes: 12,
    coordinates: RoverLatLng(latitude: 37.80167, longitude: -122.40121),
    category: 'Hidden gems',
    whySelected: 'It adds a calmer pocket after the busy waterfront.',
  ),
  RoverStop(
    id: 'sf-coit',
    name: 'Telegraph Hill Viewpoint',
    image: 'mock://sf/telegraph-hill',
    shortDescription:
        'A city-view finale without committing to the full climb.',
    estimatedVisitMinutes: 16,
    coordinates: RoverLatLng(latitude: 37.80239, longitude: -122.40582),
    category: 'Nature',
    audio: 'mock://audio/sf-view',
    whySelected: 'It gives the route a memorable ending within 90 minutes.',
  ),
];

const _sfDemoStops = [
  RoverStop(
    id: 'sf-demo-union-square',
    name: 'Union Square',
    image: 'mock://sf-demo/union-square',
    shortDescription: 'A lively plaza start with public art, cable-car energy, and city layers in every direction.',
    estimatedVisitMinutes: 10,
    coordinates: RoverLatLng(latitude: 37.78799, longitude: -122.40744),
    category: 'Current events',
    audio: 'mock://audio/sf-demo-union-square',
    whySelected: 'It gives the demo a recognizable San Francisco starting point and a clear sense of place.',
  ),
  RoverStop(
    id: 'sf-demo-lotta',
    name: 'Lotta\'s Fountain',
    image: 'mock://sf-demo/lottas-fountain',
    shortDescription: 'A compact history stop tied to the 1906 earthquake and the city rebuilding itself.',
    estimatedVisitMinutes: 9,
    coordinates: RoverLatLng(latitude: 37.78778, longitude: -122.40398),
    category: 'History',
    whySelected:
        'It adds nearby history without pulling the route away from downtown.',
  ),
  RoverStop(
    id: 'sf-demo-chinatown-gate',
    name: 'Dragon Gate',
    image: 'mock://sf-demo/dragon-gate',
    shortDescription: 'A pop-culture doorway into Chinatown, film backdrops, neon, and neighborhood storytelling.',
    estimatedVisitMinutes: 11,
    coordinates: RoverLatLng(latitude: 37.79075, longitude: -122.40560),
    category: 'Movies',
    audio: 'mock://audio/sf-demo-dragon-gate',
    whySelected:
        'It brings movie and pop-culture texture into the active demo route.',
  ),
  RoverStop(
    id: 'sf-demo-jackson-square',
    name: 'Jackson Square brick lanes',
    image: 'mock://sf-demo/jackson-square',
    shortDescription:
        'Old brick, design shops, and a quieter transition toward North Beach.',
    estimatedVisitMinutes: 8,
    coordinates: RoverLatLng(latitude: 37.79728, longitude: -122.40285),
    category: 'Architecture',
    whySelected: 'It gives the route a calmer middle while preserving the ordered walk toward Coit Tower.',
  ),
  RoverStop(
    id: 'sf-demo-coit-tower',
    name: 'Coit Tower',
    image: 'mock://sf-demo/coit-tower',
    shortDescription: 'The next-up landmark for murals, skyline views, and a classic San Francisco finish.',
    estimatedVisitMinutes: 14,
    coordinates: RoverLatLng(latitude: 37.80239, longitude: -122.40582),
    category: 'Pop culture',
    audio: 'mock://audio/sf-demo-coit',
    whySelected:
        'It demonstrates the Next Up experience with an unmistakable landmark.',
  ),
];

const _nycStops = [
  RoverStop(
    id: 'nyc-bryant',
    name: 'Bryant Park Reading Room',
    image: 'mock://nyc/bryant-park',
    shortDescription: 'A gentle start with chairs, books, and people-watching.',
    estimatedVisitMinutes: 12,
    coordinates: RoverLatLng(latitude: 40.75360, longitude: -73.98323),
    category: 'Nature',
    whySelected: 'It gives families room to settle before the busier stops.',
  ),
  RoverStop(
    id: 'nyc-library',
    name: 'Library Lions',
    image: 'mock://nyc/library-lions',
    shortDescription: 'A fast landmark story with a perfect photo pause.',
    estimatedVisitMinutes: 13,
    coordinates: RoverLatLng(latitude: 40.75318, longitude: -73.98225),
    category: 'History',
    audio: 'mock://audio/nyc-lions',
    whySelected: 'It blends history with a short, kid-friendly moment.',
  ),
  RoverStop(
    id: 'nyc-grand-central',
    name: 'Grand Central Whisper Corner',
    image: 'mock://nyc/grand-central',
    shortDescription: 'A playful sound trick and a ceiling worth craning for.',
    estimatedVisitMinutes: 16,
    coordinates: RoverLatLng(latitude: 40.75273, longitude: -73.97723),
    category: 'Architecture',
    whySelected: 'It adds wonder without making the route too long.',
  ),
  RoverStop(
    id: 'nyc-paley',
    name: 'Paley Park Pause',
    image: 'mock://nyc/paley-park',
    shortDescription: 'A tiny waterfall pocket for a softer landing.',
    estimatedVisitMinutes: 12,
    coordinates: RoverLatLng(latitude: 40.76005, longitude: -73.97547),
    category: 'Hidden gems',
    whySelected: 'It gives the family route a calmer final beat.',
  ),
];

const _localStops = [
  RoverStop(
    id: 'local-mural',
    name: 'Corner mural',
    image: 'mock://local/mural',
    shortDescription: 'A quick color hit with a neighborhood story prompt.',
    estimatedVisitMinutes: 7,
    coordinates: RoverLatLng(latitude: 40.75362, longitude: -73.98323),
    category: 'Art',
    whySelected: 'It makes a short walk feel intentionally discovered.',
  ),
  RoverStop(
    id: 'local-cafe',
    name: 'Window cafe',
    image: 'mock://local/cafe',
    shortDescription: 'A low-commitment snack or people-watching pause.',
    estimatedVisitMinutes: 8,
    coordinates: RoverLatLng(latitude: 40.75273, longitude: -73.98192),
    category: 'Food',
    whySelected: 'It adds comfort without requiring a reservation or ticket.',
  ),
  RoverStop(
    id: 'local-pocket-park',
    name: 'Pocket park bench',
    image: 'mock://local/pocket-park',
    shortDescription: 'A tiny green stop for breathing room.',
    estimatedVisitMinutes: 7,
    coordinates: RoverLatLng(latitude: 40.75173, longitude: -73.98145),
    category: 'Nature',
    audio: 'mock://audio/local-park',
    whySelected: 'It closes the route gently inside a short time budget.',
  ),
];
