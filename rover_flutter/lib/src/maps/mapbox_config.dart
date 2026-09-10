class MapboxConfig {
  static const variableName = 'MAPBOX_PUBLIC_TOKEN';

  const MapboxConfig({
    this.publicToken = const String.fromEnvironment(variableName),
  });

  final String publicToken;

  bool get hasPublicToken => publicToken.trim().isNotEmpty;
  bool get tokenLooksPublic => publicToken.trim().startsWith('pk.');
  bool get hasUsablePublicToken => hasPublicToken && tokenLooksPublic;

  String? get developmentMessage {
    if (hasUsablePublicToken) {
      return null;
    }

    if (hasPublicToken) {
      return 'Mapbox token is configured but does not look like a public pk. token.';
    }

    return 'Mapbox is not configured. Add --dart-define=$variableName=<public-token> to render the live map.';
  }
}
