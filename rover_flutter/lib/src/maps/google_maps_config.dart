class GoogleMapsConfig {
  static const variableName = 'GOOGLE_MAPS_ANDROID_API_KEY';

  const GoogleMapsConfig({
    this.apiKey = const String.fromEnvironment(variableName),
  });

  final String apiKey;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  String? get developmentMessage => hasApiKey
      ? null
      : 'Google Maps is not configured. Add --dart-define=$variableName=<android-restricted-key> to render the preferred live map.';
}
