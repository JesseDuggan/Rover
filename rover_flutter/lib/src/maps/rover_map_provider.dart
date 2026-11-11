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
    this.routingProvider = 'Unknown',
  });

  final GoogleMapsConfig google;
  final MapboxConfig mapbox;
  final String preferredProvider;
  final String routingProvider;

  RoverMapMode get mode =>
      google.hasApiKey && preferredProvider != 'development'
      ? RoverMapMode.google
      : RoverMapMode.development;

  bool get mockMode => mode == RoverMapMode.development;
  String? get developmentMessage => google.developmentMessage;
}
