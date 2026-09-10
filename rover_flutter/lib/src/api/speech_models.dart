class RenderSpeechRequest {
  const RenderSpeechRequest({
    required this.text,
    required this.purpose,
    this.locale = 'en-US',
    this.walkSessionId,
    this.stopId,
    this.idempotencyKey,
    this.cacheEligible = false,
    this.cacheExpiresUtc,
    this.storyId,
    this.variantId,
  });

  final String text;
  final String purpose;
  final String locale;
  final String? walkSessionId;
  final String? stopId;
  final String? idempotencyKey;
  final bool cacheEligible;
  final DateTime? cacheExpiresUtc;
  final String? storyId;
  final String? variantId;

  Map<String, Object?> toJson() {
    return {
      'text': text,
      'purpose': purpose,
      'locale': locale,
      'walkSessionId': walkSessionId,
      'stopId': stopId,
      'idempotencyKey': idempotencyKey,
      'cacheEligible': cacheEligible,
      'cacheExpiresUtc': cacheExpiresUtc?.toUtc().toIso8601String(),
      'storyId': storyId,
      'variantId': variantId,
    };
  }
}

class RenderedSpeechAudio {
  const RenderedSpeechAudio({
    required this.bytes,
    required this.contentType,
    required this.provider,
    required this.cacheStatus,
    required this.usedFallback,
    this.fallbackReason,
  });

  final List<int> bytes;
  final String contentType;
  final String provider;
  final String cacheStatus;
  final bool usedFallback;
  final String? fallbackReason;
}
