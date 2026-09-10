import 'package:flutter/foundation.dart';

class RoverApiConfig {
  const RoverApiConfig({
    required String baseUrl,
    this.developmentUser,
    this.connectionTimeout = const Duration(seconds: 6),
    this.responseTimeout = const Duration(seconds: 45),
    this.allowDevelopmentOverride = true,
  }) : configuredBaseUrl = baseUrl;

  static const suppliedBaseUrl = String.fromEnvironment('ROVER_API_BASE_URL');
  static const defaultDevelopmentUser = String.fromEnvironment(
    'ROVER_DEV_USER',
  );

  static String? _developmentOverride;

  final String configuredBaseUrl;
  final String? developmentUser;
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
        platform: defaultTargetPlatform,
        isWeb: kIsWeb,
      ),
      developmentUser: defaultDevelopmentUser,
    );
  }

  static String resolveBaseUrl({
    required String suppliedBaseUrl,
    required TargetPlatform platform,
    bool isWeb = false,
  }) {
    if (suppliedBaseUrl.trim().isNotEmpty) {
      return normalizeBaseUrl(suppliedBaseUrl);
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
