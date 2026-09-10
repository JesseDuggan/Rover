import 'google_maps_config.dart';
import 'mapbox_config.dart';

enum RoverMapMode { development, google, mapbox }

class RoverMapProvider {
  const RoverMapProvider({
    this.google = const GoogleMapsConfig(),
    this.mapbox = const MapboxConfig(),
    this.preferredProvider = const String.fromEnvironment(
      'ROVER_MAP_PROVIDER',
      defaultValue: 'google',
    ),
    this.routingProvider = 'Mock',
  });

  final GoogleMapsConfig google;
  final MapboxConfig mapbox;
  final String preferredProvider;
  final String routingProvider;

  RoverMapMode get mode {
    final preferred = preferredProvider.trim().toLowerCase();
    if (preferred == 'development') {
      return RoverMapMode.development;
    }
    if (preferred == 'mapbox') {
      return mapbox.hasUsablePublicToken
          ? RoverMapMode.mapbox
          : RoverMapMode.development;
    }
    if (preferred == 'google') {
      if (google.hasApiKey) {
        return RoverMapMode.google;
      }
      return mapbox.hasUsablePublicToken
          ? RoverMapMode.mapbox
          : RoverMapMode.development;
    }

    if (google.hasApiKey) {
      return RoverMapMode.google;
    }
    return mapbox.hasUsablePublicToken
        ? RoverMapMode.mapbox
        : RoverMapMode.development;
  }

  bool get mockMode => mode == RoverMapMode.development;
  String? get developmentMessage {
    final preferred = preferredProvider.trim().toLowerCase();
    if (preferred == 'mapbox') {
      return mapbox.developmentMessage;
    }
    if (google.hasApiKey || mapbox.hasUsablePublicToken) {
      return null;
    }
    return '${google.developmentMessage} Mapbox fallback is also unavailable.';
  }
}
