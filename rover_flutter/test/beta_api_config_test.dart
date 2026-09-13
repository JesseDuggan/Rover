import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/rover_api_config.dart';

void main() {
  const config = RoverApiConfig(
    baseUrl: 'https://rover.example',
    betaApiKey: ' test-beta ',
  );
  test('beta credential is available for API and speech requests', () {
    for (final path in ['/api/walks', '/api/speech/render']) {
      expect(
        config.betaKeyFor(Uri.parse('https://rover.example$path')),
        'test-beta',
      );
    }
  });
  test('beta credential is excluded from health and other origins', () {
    for (final url in [
      'https://rover.example/health',
      'https://other.example/api/walks',
      'http://rover.example/api/walks',
      'https://rover.example:8443/api/walks',
    ]) {
      expect(config.betaKeyFor(Uri.parse(url)), isNull);
    }
  });
  test('missing beta credential preserves unauthenticated development', () {
    const empty = RoverApiConfig(baseUrl: 'https://rover.example');
    expect(
      empty.betaKeyFor(Uri.parse('https://rover.example/api/walks')),
      isNull,
    );
  });
}
