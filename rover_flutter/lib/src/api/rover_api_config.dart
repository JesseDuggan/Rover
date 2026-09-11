import 'package:flutter/foundation.dart';

class RoverApiConfig {
  const RoverApiConfig({
    required String baseUrl,
    this.developmentUser,
    this.betaApiKey,
    this.connectionTimeout = const Duration(seconds: 6),
    this.responseTimeout = const Duration(seconds: 45),
    this.allowDevelopmentOverride = true,
  }) : configuredBaseUrl = baseUrl;

  static const apiEnvironment = String.fromEnvironment(
    'ROVER_API_ENVIRONMENT',
    defaultValue: 'local',
  );
  static const suppliedBaseUrl = String.fromEnvironment('ROVER_API_BASE_URL');
  static const betaBaseUrl = String.fromEnvironment(
    'ROVER_BETA_API_BASE_URL',
    defaultValue: 'https://rover-api.up.railway.app',
  );
  static const productionBaseUrl = String.fromEnvironment(
    'ROVER_PRODUCTION_API_BASE_URL',
  );
  static const defaultDevelopmentUser = String.fromEnvironment(
    'ROVER_DEV_USER',
  );
  static const suppliedBetaApiKey = String.fromEnvironment(
    'ROVER_BETA_API_KEY',
  );

  static String? _developmentOverride;

  final String configuredBaseUrl;
  final String? developmentUser;
  final String? betaApiKey;
  final Duration connectionTimeout;
  final Duration responseTimeout;
  final bool allowDevelopmentOverride;

  String get baseUrl =>
      kDebugMode && allowDevelopmentOverride && _developmentOverride != null
      ? _developmentOverride!
      : configuredBaseUrl;
  String get normalizedBaseUrl => normalizeBaseUrl(baseUrl);

  static String? get developmentOverride =>
      kDebugMode ? _developmentOverride : null;

  static void setDevelopmentOverride(String? value) {
    if (!kDebugMode) {
      return;
    }
    final candidate = value?.trim() ?? '';
    _developmentOverride = candidate.isEmpty
        ? null
        : normalizeBaseUrl(candidate);
  }

  factory RoverApiConfig.fromEnvironment() {
    return RoverApiConfig(
      baseUrl: resolveBaseUrl(
        suppliedBaseUrl: suppliedBaseUrl,
        environment: apiEnvironment,
        betaBaseUrl: betaBaseUrl,
        productionBaseUrl: productionBaseUrl,
        platform: defaultTargetPlatform,
        isWeb: kIsWeb,
      ),
      developmentUser: defaultDevelopmentUser,
      betaApiKey: suppliedBetaApiKey.trim().isEmpty
          ? null
          : suppliedBetaApiKey,
    );
  }

  static String resolveBaseUrl({
    required String suppliedBaseUrl,
    String environment = 'local',
    String betaBaseUrl = betaBaseUrl,
    String productionBaseUrl = productionBaseUrl,
    required TargetPlatform platform,
    bool isWeb = false,
  }) {
    if (suppliedBaseUrl.trim().isNotEmpty) {
      return normalizeBaseUrl(suppliedBaseUrl);
    }
    switch (environment.trim().toLowerCase()) {
      case 'beta':
        return normalizeBaseUrl(betaBaseUrl);
      case 'production':
      case 'prod':
        if (productionBaseUrl.trim().isEmpty) {
          throw ArgumentError.value(
            productionBaseUrl,
            'productionBaseUrl',
            'ROVER_PRODUCTION_API_BASE_URL is required for production builds',
          );
        }
        return normalizeBaseUrl(productionBaseUrl);
    }
    if (!isWeb && platform == TargetPlatform.android) {
      return 'http://10.0.2.2:5080';
    }
    return 'http://127.0.0.1:5080';
  }

  static String normalizeBaseUrl(String input) {
    var value = input.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(input, 'input', 'Invalid ROVER API base URL');
    }
    return value;
  }

  Uri uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBaseUrl$normalizedPath');
  }
}
