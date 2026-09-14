import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/adventure/adventure_request.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';

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

RoamSession demoSession() {
  final roam = MockRouteGenerationService.activeSanFranciscoDemo();
  return RoamSession(
    roam: roam,
    status: RoamSessionStatus.notStarted,
    currentStopIndex: 0,
    completedStopIds: const {},
    skippedStopIds: const {},
    simulatedLocation: roam.stops.first.coordinates,
    audioStatus: AudioPlaybackStatus.stopped,
    screenAwake: false,
    arrivedAtCurrentStop: true,
    timeRemainingMinutes: roam.totalEstimatedMinutes,
    progressPercentage: 0,
    routeProgressPercentage: 0,
    distanceToNextStopMeters: 0,
    routeRevision: 1,
    savedDiscoveryIds: const {},
  );
}
