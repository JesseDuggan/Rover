import 'dart:math';

/// Opaque diagnostic identity, saved with the journey. Never an access token.
abstract final class JourneyIdentity {
  static String create() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String restore(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value)
      ? value
      : create();
}
