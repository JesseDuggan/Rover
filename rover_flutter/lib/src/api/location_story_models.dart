import '../location/rover_location.dart';

class LocationStoryRequest {
  const LocationStoryRequest({
    required this.location,
    required this.radiusMeters,
    required this.routeGeometry,
    required this.interests,
    required this.selectedPlaceIds,
    this.routeId,
    this.profileId,
    this.narrationStyle,
    this.routeSegmentId,
    this.directionalContext,
  });

  final RoverLatLng location;
  final int radiusMeters;
  final List<RoverLatLng> routeGeometry;
  final List<String> interests;
  final List<String> selectedPlaceIds;
  final String? routeId;
  final String? profileId;
  final String? narrationStyle;
  final String? routeSegmentId;
  final String? directionalContext;

  Map<String, Object?> toJson() {
    return {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'radiusMeters': radiusMeters,
      'routeId': routeId,
      'profileId': profileId,
      'routeGeometry': routeGeometry
          .map(
            (point) => {
              'latitude': point.latitude,
              'longitude': point.longitude,
            },
          )
          .toList(),
      'interests': interests,
      'selectedPlaceIds': selectedPlaceIds,
      'narrationStyle': narrationStyle,
      'routeSegmentId': routeSegmentId,
      'directionalContext': directionalContext,
    };
  }
}

class LocationStoryContext {
  const LocationStoryContext({
    required this.rankedPlaces,
    required this.sourceWarnings,
    required this.providerStatus,
  });

  final List<LocationPlaceSummary> rankedPlaces;
  final List<String> sourceWarnings;
  final List<LocationProviderStatus> providerStatus;

  factory LocationStoryContext.fromJson(Map<String, dynamic> json) {
    return LocationStoryContext(
      rankedPlaces: (json['rankedPlaces'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocationPlaceSummary.fromJson)
          .toList(),
      sourceWarnings: (json['sourceWarnings'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      providerStatus: (json['providerStatus'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocationProviderStatus.fromJson)
          .toList(),
    );
  }
}

class LocationPlaceSummary {
  const LocationPlaceSummary({
    required this.canonicalId,
    required this.name,
    required this.coordinates,
    required this.categories,
    required this.facts,
    required this.storyWorthinessReasons,
    required this.sourceReferences,
    this.address,
    this.shortDescription,
    this.openingStatus,
    this.accessibilityInformation,
    this.distanceFromUserMeters,
    this.directionFromUser,
    this.confidenceScore = 0,
    this.storyWorthinessScore = 0,
  });

  final String canonicalId;
  final String name;
  final RoverLatLng coordinates;
  final String? address;
  final List<String> categories;
  final String? shortDescription;
  final String? openingStatus;
  final String? accessibilityInformation;
  final List<LocationFactSummary> facts;
  final double? distanceFromUserMeters;
  final String? directionFromUser;
  final double confidenceScore;
  final double storyWorthinessScore;
  final List<String> storyWorthinessReasons;
  final List<LocationSourceReference> sourceReferences;

  factory LocationPlaceSummary.fromJson(Map<String, dynamic> json) {
    return LocationPlaceSummary(
      canonicalId: json['canonicalId'] as String? ?? '',
      name: json['name'] as String? ?? 'Nearby place',
      coordinates: _coordinates(json['coordinates']),
      address: json['address'] as String?,
      categories: (json['categories'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      shortDescription: json['shortDescription'] as String?,
      openingStatus: json['openingStatus'] as String?,
      accessibilityInformation: json['accessibilityInformation'] as String?,
      facts: (json['facts'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocationFactSummary.fromJson)
          .toList(),
      distanceFromUserMeters: (json['distanceFromUserMeters'] as num?)
          ?.toDouble(),
      directionFromUser: json['directionFromUser'] as String?,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0,
      storyWorthinessScore:
          (json['storyWorthinessScore'] as num?)?.toDouble() ?? 0,
      storyWorthinessReasons:
          (json['storyWorthinessReasons'] as List? ?? const [])
              .whereType<String>()
              .toList(),
      sourceReferences: (json['sourceReferences'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocationSourceReference.fromJson)
          .toList(),
    );
  }

  static RoverLatLng _coordinates(Object? value) {
    if (value is Map) {
      return RoverLatLng(
        latitude: (value['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (value['longitude'] as num?)?.toDouble() ?? 0,
      );
    }
    return const RoverLatLng(latitude: 0, longitude: 0);
  }
}

class LocationFactSummary {
  const LocationFactSummary({
    required this.factId,
    required this.factType,
    required this.factText,
    required this.confidenceScore,
    required this.isSuitableForNarration,
  });

  final String factId;
  final String factType;
  final String factText;
  final double confidenceScore;
  final bool isSuitableForNarration;

  factory LocationFactSummary.fromJson(Map<String, dynamic> json) {
    return LocationFactSummary(
      factId: json['factId'] as String? ?? '',
      factType: json['factType'] as String? ?? 'Fact',
      factText: json['factText'] as String? ?? '',
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0,
      isSuitableForNarration: json['isSuitableForNarration'] as bool? ?? false,
    );
  }
}

class LocationStoryResponse {
  const LocationStoryResponse({
    required this.storyTitle,
    required this.shortSpokenNarration,
    required this.factIdsUsed,
    required this.sourceReferences,
    required this.confidence,
    required this.requiredAttribution,
    required this.warnings,
    this.tellMeMore,
    this.placeId,
    this.storyPack,
    this.offlineCached = false,
    this.cachedAtUtc,
    this.lastVerifiedUtc,
    this.expiresUtc,
  });

  final String storyTitle;
  final String shortSpokenNarration;
  final String? tellMeMore;
  final String? placeId;
  final List<String> factIdsUsed;
  final List<LocationSourceReference> sourceReferences;
  final double confidence;
  final List<String> requiredAttribution;
  final List<String> warnings;
  final Map<String, dynamic>? storyPack;
  final bool offlineCached;
  final DateTime? cachedAtUtc;
  final DateTime? lastVerifiedUtc;
  final DateTime? expiresUtc;

  StoryPackV2Metadata? get storyPackV2 {
    final pack = storyPack;
    if (pack == null || pack['schemaVersion'] != '2.0') {
      return null;
    }
    return StoryPackV2Metadata.fromJson(pack);
  }

  Map<String, Object?> toJson() => {
    'storyTitle': storyTitle,
    'shortSpokenNarration': shortSpokenNarration,
    'tellMeMore': tellMeMore,
    'placeId': placeId,
    'factIdsUsed': factIdsUsed,
    'sourceReferences': sourceReferences
        .map((source) => source.toJson())
        .toList(growable: false),
    'confidence': confidence,
    'requiredAttribution': requiredAttribution,
    'warnings': warnings,
    'storyPack': storyPack,
    'offlineCached': offlineCached,
    'cachedAtUtc': cachedAtUtc?.toIso8601String(),
    'lastVerifiedUtc': lastVerifiedUtc?.toIso8601String(),
    'expiresUtc': expiresUtc?.toIso8601String(),
  };

  factory LocationStoryResponse.fromJson(Map<String, dynamic> json) {
    return LocationStoryResponse(
      storyTitle: json['storyTitle'] as String? ?? 'Nearby story',
      shortSpokenNarration: json['shortSpokenNarration'] as String? ?? '',
      tellMeMore: json['tellMeMore'] as String?,
      placeId: json['placeId'] as String?,
      factIdsUsed: (json['factIdsUsed'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      sourceReferences: (json['sourceReferences'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocationSourceReference.fromJson)
          .toList(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      requiredAttribution: (json['requiredAttribution'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      warnings: (json['warnings'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      storyPack: _stringMap(json['storyPack']),
      offlineCached: json['offlineCached'] as bool? ?? false,
      cachedAtUtc: _dateTime(json['cachedAtUtc']),
      lastVerifiedUtc: _dateTime(json['lastVerifiedUtc']),
      expiresUtc: _dateTime(json['expiresUtc']),
    );
  }
}

class StoryPackV2Metadata {
  const StoryPackV2Metadata({
    required this.storyId,
    required this.entityId,
    required this.categories,
    required this.interestTags,
    required this.narrationVariants,
    required this.followUpPrompts,
    required this.relatedStoryPackIds,
    this.primaryCategory,
    this.geographicAnchor,
    this.evidenceQualityScore,
    this.freshnessClassification,
    this.retrievedUtc,
    this.cacheEligibility,
    this.narrationStatus,
  });

  final String storyId;
  final String entityId;
  final StoryGeographicAnchorMetadata? geographicAnchor;
  final String? primaryCategory;
  final List<String> categories;
  final List<String> interestTags;
  final List<StoryNarrationVariantMetadata> narrationVariants;
  final double? evidenceQualityScore;
  final String? freshnessClassification;
  final DateTime? retrievedUtc;
  final StoryCacheEligibilityMetadata? cacheEligibility;
  final String? narrationStatus;
  final List<String> followUpPrompts;
  final List<String> relatedStoryPackIds;

  factory StoryPackV2Metadata.fromJson(Map<String, dynamic> json) {
    final interactionState = _stringMap(json['interactionState']);
    return StoryPackV2Metadata(
      storyId: json['storyId'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      geographicAnchor: StoryGeographicAnchorMetadata.tryParse(
        json['geographicAnchor'],
      ),
      primaryCategory: json['primaryCategory'] as String?,
      categories: (json['categories'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      interestTags: (json['interestTags'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      narrationVariants: (json['narrationVariants'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StoryNarrationVariantMetadata.fromJson)
          .toList(growable: false),
      evidenceQualityScore: (json['evidenceQualityScore'] as num?)?.toDouble(),
      freshnessClassification: json['freshnessClassification'] as String?,
      retrievedUtc: _dateTime(json['retrievedUtc']),
      cacheEligibility: StoryCacheEligibilityMetadata.tryParse(
        json['cacheEligibility'],
      ),
      narrationStatus: interactionState?['narrationStatus'] as String?,
      followUpPrompts: (json['followUpPrompts'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      relatedStoryPackIds: (json['relatedStoryPackIds'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class StoryGeographicAnchorMetadata {
  const StoryGeographicAnchorMetadata({
    required this.latitude,
    required this.longitude,
    this.routeId,
    this.routeSegmentId,
    this.directionalContext,
  });

  final double latitude;
  final double longitude;
  final String? routeId;
  final String? routeSegmentId;
  final String? directionalContext;

  static StoryGeographicAnchorMetadata? tryParse(Object? value) {
    final json = _stringMap(value);
    if (json == null) return null;
    return StoryGeographicAnchorMetadata(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      routeId: json['routeId'] as String?,
      routeSegmentId: json['routeSegmentId'] as String?,
      directionalContext: json['directionalContext'] as String?,
    );
  }
}

class StoryNarrationVariantMetadata {
  const StoryNarrationVariantMetadata({
    required this.variantId,
    required this.variantType,
    required this.sectionType,
    required this.targetDurationSeconds,
    required this.estimatedDurationSeconds,
    required this.sentenceIds,
    required this.evidenceIds,
    this.prefetchedAudioReference,
  });

  final String variantId;
  final String variantType;
  final String sectionType;
  final int targetDurationSeconds;
  final int estimatedDurationSeconds;
  final List<String> sentenceIds;
  final List<String> evidenceIds;
  final String? prefetchedAudioReference;

  factory StoryNarrationVariantMetadata.fromJson(Map<String, dynamic> json) =>
      StoryNarrationVariantMetadata(
        variantId: json['variantId'] as String? ?? '',
        variantType: json['variantType'] as String? ?? '',
        sectionType: json['sectionType'] as String? ?? '',
        targetDurationSeconds:
            (json['targetDurationSeconds'] as num?)?.toInt() ?? 0,
        estimatedDurationSeconds:
            (json['estimatedDurationSeconds'] as num?)?.toInt() ?? 0,
        sentenceIds: (json['sentenceIds'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        evidenceIds: (json['evidenceIds'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        prefetchedAudioReference: json['prefetchedAudioReference'] as String?,
      );
}

class StoryCacheEligibilityMetadata {
  const StoryCacheEligibilityMetadata({
    required this.offlineEligible,
    required this.audioCacheEligible,
    required this.retentionClass,
    required this.reason,
  });

  final bool offlineEligible;
  final bool audioCacheEligible;
  final String retentionClass;
  final String reason;

  static StoryCacheEligibilityMetadata? tryParse(Object? value) {
    final json = _stringMap(value);
    if (json == null) return null;
    return StoryCacheEligibilityMetadata(
      offlineEligible: json['offlineEligible'] as bool? ?? false,
      audioCacheEligible: json['audioCacheEligible'] as bool? ?? false,
      retentionClass: json['retentionClass'] as String? ?? 'restricted',
      reason: json['reason'] as String? ?? '',
    );
  }
}

class LocationProviderStatus {
  const LocationProviderStatus({
    required this.providerName,
    required this.enabled,
    required this.succeeded,
    required this.resultCount,
    this.warning,
  });

  final String providerName;
  final bool enabled;
  final bool succeeded;
  final int resultCount;
  final String? warning;

  factory LocationProviderStatus.fromJson(Map<String, dynamic> json) {
    return LocationProviderStatus(
      providerName: json['providerName'] as String? ?? 'Unknown',
      enabled: json['enabled'] as bool? ?? false,
      succeeded: json['succeeded'] as bool? ?? false,
      resultCount: json['resultCount'] as int? ?? 0,
      warning: json['warning'] as String?,
    );
  }
}

class LocationSourceReference {
  const LocationSourceReference({
    required this.providerName,
    required this.attribution,
    this.providerRecordId,
    this.sourceTitle,
    this.sourceUrl,
    this.license,
    this.retrievedUtc,
    this.expiresUtc,
    this.confidenceScore,
  });

  final String providerName;
  final String attribution;
  final String? providerRecordId;
  final String? sourceTitle;
  final String? sourceUrl;
  final String? license;
  final DateTime? retrievedUtc;
  final DateTime? expiresUtc;
  final double? confidenceScore;

  Map<String, Object?> toJson() => {
    'providerName': providerName,
    'providerRecordId': providerRecordId,
    'sourceTitle': sourceTitle,
    'sourceUrl': sourceUrl,
    'attribution': attribution,
    'license': license,
    'retrievedUtc': retrievedUtc?.toIso8601String(),
    'expiresUtc': expiresUtc?.toIso8601String(),
    'confidenceScore': confidenceScore,
  };

  factory LocationSourceReference.fromJson(Map<String, dynamic> json) {
    return LocationSourceReference(
      providerName: json['providerName'] as String? ?? 'Unknown',
      attribution: json['attribution'] as String? ?? '',
      providerRecordId: json['providerRecordId'] as String?,
      sourceTitle: json['sourceTitle'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      license: json['license'] as String?,
      retrievedUtc: _dateTime(json['retrievedUtc']),
      expiresUtc: _dateTime(json['expiresUtc']),
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble(),
    );
  }
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}
