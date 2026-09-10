class GenerateRouteStoryPackRequest {
  const GenerateRouteStoryPackRequest({
    this.profileId,
    this.audience,
    this.language,
    this.forceRefresh = false,
  });

  final String? profileId;
  final String? audience;
  final String? language;
  final bool forceRefresh;

  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'audience': audience,
    'language': language,
    'forceRefresh': forceRefresh,
  };
}

class NextRouteStoryRequest {
  const NextRouteStoryRequest({
    required this.routeProgressMeters,
    this.secondsUntilNextManeuver,
    this.preferredLength = 'Standard',
    this.excludedStoryIds = const [],
  });

  final double routeProgressMeters;
  final int? secondsUntilNextManeuver;
  final String preferredLength;
  final List<String> excludedStoryIds;

  Map<String, Object?> toJson() => {
    'routeProgressMeters': routeProgressMeters,
    'secondsUntilNextManeuver': secondsUntilNextManeuver,
    'preferredLength': preferredLength,
    'excludedStoryIds': excludedStoryIds,
  };
}

class RouteStoryQuestionRequest {
  const RouteStoryQuestionRequest({
    required this.question,
    required this.routeProgressMeters,
    this.secondsUntilNextManeuver,
  });

  final String question;
  final double routeProgressMeters;
  final int? secondsUntilNextManeuver;

  Map<String, Object?> toJson() => {
    'question': question,
    'routeProgressMeters': routeProgressMeters,
    'secondsUntilNextManeuver': secondsUntilNextManeuver,
  };
}

class RouteStoryPlaybackEventRequest {
  const RouteStoryPlaybackEventRequest({
    required this.storyId,
    required this.kind,
    required this.occurredUtc,
    this.positionSeconds,
  });

  final String storyId;
  final String kind;
  final DateTime occurredUtc;
  final int? positionSeconds;

  Map<String, Object?> toJson() => {
    'storyId': storyId,
    'kind': kind,
    'occurredUtc': occurredUtc.toUtc().toIso8601String(),
    'positionSeconds': positionSeconds,
  };
}

class RouteStorySource {
  const RouteStorySource({
    required this.sourceId,
    required this.providerName,
    required this.attribution,
    required this.retrievedUtc,
    required this.confidence,
    this.title,
    this.url,
  });

  final String sourceId;
  final String providerName;
  final String? title;
  final String? url;
  final String attribution;
  final DateTime retrievedUtc;
  final double confidence;

  factory RouteStorySource.fromJson(Map<String, dynamic> json) =>
      RouteStorySource(
        sourceId: json['sourceId'] as String? ?? '',
        providerName: json['providerName'] as String? ?? '',
        title: json['title'] as String?,
        url: json['url'] as String?,
        attribution: json['attribution'] as String? ?? '',
        retrievedUtc:
            DateTime.tryParse(json['retrievedUtc'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'providerName': providerName,
    'title': title,
    'url': url,
    'attribution': attribution,
    'retrievedUtc': retrievedUtc.toUtc().toIso8601String(),
    'confidence': confidence,
  };
}

class RouteStoryClaim {
  const RouteStoryClaim({
    required this.claimId,
    required this.text,
    required this.sourceIds,
    required this.confidence,
  });

  final String claimId;
  final String text;
  final List<String> sourceIds;
  final double confidence;

  factory RouteStoryClaim.fromJson(Map<String, dynamic> json) =>
      RouteStoryClaim(
        claimId: json['claimId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        sourceIds: _strings(json['sourceIds']),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );

  Map<String, Object?> toJson() => {
    'claimId': claimId,
    'text': text,
    'sourceIds': sourceIds,
    'confidence': confidence,
  };
}

class RouteStoryNarrationVariant {
  const RouteStoryNarrationVariant({
    required this.length,
    required this.estimatedDurationSeconds,
    required this.narration,
    required this.claimIds,
  });

  final String length;
  final int estimatedDurationSeconds;
  final String narration;
  final List<String> claimIds;

  factory RouteStoryNarrationVariant.fromJson(Map<String, dynamic> json) =>
      RouteStoryNarrationVariant(
        length: json['length'] as String? ?? 'Quick',
        estimatedDurationSeconds:
            (json['estimatedDurationSeconds'] as num?)?.toInt() ?? 0,
        narration: json['narration'] as String? ?? '',
        claimIds: _strings(json['claimIds']),
      );

  Map<String, Object?> toJson() => {
    'length': length,
    'estimatedDurationSeconds': estimatedDurationSeconds,
    'narration': narration,
    'claimIds': claimIds,
  };
}

class AdaptiveRouteStory {
  const AdaptiveRouteStory({
    required this.storyId,
    required this.segmentId,
    required this.placeId,
    required this.title,
    required this.intent,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.opensAtRouteMeters,
    required this.closesAtRouteMeters,
    required this.variants,
    required this.claims,
    required this.sources,
    required this.evidenceScore,
    this.expiresUtc,
  });

  final String storyId;
  final String segmentId;
  final String placeId;
  final String title;
  final String intent;
  final String category;
  final double latitude;
  final double longitude;
  final double opensAtRouteMeters;
  final double closesAtRouteMeters;
  final List<RouteStoryNarrationVariant> variants;
  final List<RouteStoryClaim> claims;
  final List<RouteStorySource> sources;
  final double evidenceScore;
  final DateTime? expiresUtc;

  factory AdaptiveRouteStory.fromJson(Map<String, dynamic> json) {
    final anchor = _map(json['anchor']);
    return AdaptiveRouteStory(
      storyId: json['storyId'] as String? ?? '',
      segmentId: json['segmentId'] as String? ?? '',
      placeId: json['placeId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      intent: json['intent'] as String? ?? 'GeneralLocationQuestion',
      category: json['category'] as String? ?? '',
      latitude: (anchor['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (anchor['longitude'] as num?)?.toDouble() ?? 0,
      opensAtRouteMeters: (json['opensAtRouteMeters'] as num?)?.toDouble() ?? 0,
      closesAtRouteMeters:
          (json['closesAtRouteMeters'] as num?)?.toDouble() ?? 0,
      variants: _maps(json['variants'])
          .map(RouteStoryNarrationVariant.fromJson)
          .toList(),
      claims: _maps(json['claims']).map(RouteStoryClaim.fromJson).toList(),
      sources: _maps(json['sources']).map(RouteStorySource.fromJson).toList(),
      evidenceScore: (json['evidenceScore'] as num?)?.toDouble() ?? 0,
      expiresUtc: DateTime.tryParse(json['expiresUtc'] as String? ?? ''),
    );
  }

  Map<String, Object?> toJson() => {
    'storyId': storyId,
    'segmentId': segmentId,
    'placeId': placeId,
    'title': title,
    'intent': intent,
    'category': category,
    'anchor': {'latitude': latitude, 'longitude': longitude},
    'opensAtRouteMeters': opensAtRouteMeters,
    'closesAtRouteMeters': closesAtRouteMeters,
    'variants': variants.map((variant) => variant.toJson()).toList(),
    'claims': claims.map((claim) => claim.toJson()).toList(),
    'sources': sources.map((source) => source.toJson()).toList(),
    'evidenceScore': evidenceScore,
    'expiresUtc': expiresUtc?.toUtc().toIso8601String(),
  };
}

class AdaptiveRouteStoryPack {
  const AdaptiveRouteStoryPack({
    required this.schemaVersion,
    required this.packId,
    required this.idempotencyKey,
    required this.walkSessionId,
    required this.routeId,
    required this.routeRevision,
    required this.promptVersion,
    required this.generatedUtc,
    required this.expiresUtc,
    required this.stories,
    required this.warnings,
  });

  final String schemaVersion;
  final String packId;
  final String idempotencyKey;
  final String walkSessionId;
  final String routeId;
  final int routeRevision;
  final String promptVersion;
  final DateTime generatedUtc;
  final DateTime expiresUtc;
  final List<AdaptiveRouteStory> stories;
  final List<String> warnings;

  factory AdaptiveRouteStoryPack.fromJson(Map<String, dynamic> json) =>
      AdaptiveRouteStoryPack(
        schemaVersion: json['schemaVersion'] as String? ?? '',
        packId: json['packId'] as String? ?? '',
        idempotencyKey: json['idempotencyKey'] as String? ?? '',
        walkSessionId: json['walkSessionId'] as String? ?? '',
        routeId: json['routeId'] as String? ?? '',
        routeRevision: (json['routeRevision'] as num?)?.toInt() ?? 0,
        promptVersion: json['promptVersion'] as String? ?? '',
        generatedUtc:
            DateTime.tryParse(json['generatedUtc'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        expiresUtc:
            DateTime.tryParse(json['expiresUtc'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        stories: _maps(json['stories'])
            .map(AdaptiveRouteStory.fromJson)
            .toList(),
        warnings: _strings(json['warnings']),
      );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'packId': packId,
    'idempotencyKey': idempotencyKey,
    'walkSessionId': walkSessionId,
    'routeId': routeId,
    'routeRevision': routeRevision,
    'promptVersion': promptVersion,
    'generatedUtc': generatedUtc.toUtc().toIso8601String(),
    'expiresUtc': expiresUtc.toUtc().toIso8601String(),
    'stories': stories.map((story) => story.toJson()).toList(),
    'warnings': warnings,
  };
}

class AdaptiveRouteStoryPackState {
  const AdaptiveRouteStoryPackState({
    required this.walkSessionId,
    required this.routeRevision,
    required this.status,
    required this.updatedUtc,
    required this.heardStoryIds,
    required this.savedStoryIds,
    this.pack,
    this.error,
    this.lastPlaybackEvent,
  });

  final String walkSessionId;
  final int routeRevision;
  final String status;
  final DateTime updatedUtc;
  final AdaptiveRouteStoryPack? pack;
  final String? error;
  final List<String> heardStoryIds;
  final List<String> savedStoryIds;
  final String? lastPlaybackEvent;

  factory AdaptiveRouteStoryPackState.fromJson(Map<String, dynamic> json) =>
      AdaptiveRouteStoryPackState(
        walkSessionId: json['walkSessionId'] as String? ?? '',
        routeRevision: (json['routeRevision'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'Pending',
        updatedUtc:
            DateTime.tryParse(json['updatedUtc'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        pack: json['pack'] is Map<String, dynamic>
            ? AdaptiveRouteStoryPack.fromJson(
                json['pack'] as Map<String, dynamic>,
              )
            : null,
        error: json['error'] as String?,
        heardStoryIds: _strings(json['heardStoryIds']),
        savedStoryIds: _strings(json['savedStoryIds']),
        lastPlaybackEvent: json['lastPlaybackEvent'] as String?,
      );

  Map<String, Object?> toJson() => {
    'walkSessionId': walkSessionId,
    'routeRevision': routeRevision,
    'status': status,
    'updatedUtc': updatedUtc.toUtc().toIso8601String(),
    'pack': pack?.toJson(),
    'error': error,
    'heardStoryIds': heardStoryIds,
    'savedStoryIds': savedStoryIds,
    'lastPlaybackEvent': lastPlaybackEvent,
  };
}

class AdaptiveRouteStorySelection {
  const AdaptiveRouteStorySelection({
    required this.story,
    required this.variant,
    required this.reason,
  });

  final AdaptiveRouteStory story;
  final RouteStoryNarrationVariant variant;
  final String reason;

  factory AdaptiveRouteStorySelection.fromJson(Map<String, dynamic> json) =>
      AdaptiveRouteStorySelection(
        story: AdaptiveRouteStory.fromJson(_map(json['story'])),
        variant: RouteStoryNarrationVariant.fromJson(_map(json['variant'])),
        reason: json['reason'] as String? ?? '',
      );
}

class AdaptiveRouteStoryAnswer {
  const AdaptiveRouteStoryAnswer({
    required this.intent,
    required this.requestedLength,
    required this.suspiciousInput,
    this.selection,
    this.unavailableReason,
  });

  final String intent;
  final String requestedLength;
  final bool suspiciousInput;
  final AdaptiveRouteStorySelection? selection;
  final String? unavailableReason;

  factory AdaptiveRouteStoryAnswer.fromJson(Map<String, dynamic> json) {
    final classification = _map(json['classification']);
    return AdaptiveRouteStoryAnswer(
      intent: classification['intent'] as String? ?? 'GeneralLocationQuestion',
      requestedLength:
          classification['requestedLength'] as String? ?? 'Standard',
      suspiciousInput: classification['suspiciousInput'] as bool? ?? false,
      selection: json['selection'] is Map<String, dynamic>
          ? AdaptiveRouteStorySelection.fromJson(
              json['selection'] as Map<String, dynamic>,
            )
          : null,
      unavailableReason: json['unavailableReason'] as String?,
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList()
    : <Map<String, dynamic>>[];

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];
