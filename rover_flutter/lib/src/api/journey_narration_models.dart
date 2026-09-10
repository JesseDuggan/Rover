import '../location/rover_location.dart';
import 'location_story_models.dart';

class JourneyNarrationEvaluateRequest {
  const JourneyNarrationEvaluateRequest({
    required this.location,
    this.profileId,
    this.gpsAccuracyMeters,
    this.headingDegrees,
    this.speedMetersPerSecond,
    this.alreadyNarratedFactIds = const [],
    this.requestedAtUtc,
    this.secondsUntilNextManeuver,
    this.storyDurationSeconds,
    this.storyDensity = 'highlights',
    this.preferredStoryCategories = const [],
    this.excludedStoryCategories = const [],
    this.routeState = 'onRoute',
    this.userAttentionAvailable = true,
    this.recentDirectInteraction = false,
    this.connectivityAvailable = true,
    this.audioAlreadyQueued = false,
    this.batterySaverEnabled = false,
    this.thermalState,
    this.interruptedStoryId,
    this.interruptedStoryRouteId,
    this.interruptedStoryExpiresUtc,
    this.interruptedStoryStillRelevant = false,
  });

  final RoverLatLng location;
  final String? profileId;
  final double? gpsAccuracyMeters;
  final double? headingDegrees;
  final double? speedMetersPerSecond;
  final List<String> alreadyNarratedFactIds;
  final DateTime? requestedAtUtc;
  final int? secondsUntilNextManeuver;
  final int? storyDurationSeconds;
  final String storyDensity;
  final List<String> preferredStoryCategories;
  final List<String> excludedStoryCategories;
  final String routeState;
  final bool userAttentionAvailable;
  final bool recentDirectInteraction;
  final bool connectivityAvailable;
  final bool audioAlreadyQueued;
  final bool batterySaverEnabled;
  final String? thermalState;
  final String? interruptedStoryId;
  final String? interruptedStoryRouteId;
  final DateTime? interruptedStoryExpiresUtc;
  final bool interruptedStoryStillRelevant;

  Map<String, Object?> toJson() {
    return {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'profileId': profileId,
      'gpsAccuracyMeters': gpsAccuracyMeters,
      'headingDegrees': headingDegrees,
      'speedMetersPerSecond': speedMetersPerSecond,
      'alreadyNarratedFactIds': alreadyNarratedFactIds,
      'requestedAtUtc': requestedAtUtc?.toUtc().toIso8601String(),
      'secondsUntilNextManeuver': secondsUntilNextManeuver,
      'storyDurationSeconds': storyDurationSeconds,
      'storyDensity': storyDensity,
      'preferredStoryCategories': preferredStoryCategories,
      'excludedStoryCategories': excludedStoryCategories,
      'routeState': routeState,
      'userAttentionAvailable': userAttentionAvailable,
      'recentDirectInteraction': recentDirectInteraction,
      'connectivityAvailable': connectivityAvailable,
      'audioAlreadyQueued': audioAlreadyQueued,
      'batterySaverEnabled': batterySaverEnabled,
      'thermalState': thermalState,
      'interruptedStoryId': interruptedStoryId,
      'interruptedStoryRouteId': interruptedStoryRouteId,
      'interruptedStoryExpiresUtc': interruptedStoryExpiresUtc
          ?.toUtc()
          .toIso8601String(),
      'interruptedStoryStillRelevant': interruptedStoryStillRelevant,
    };
  }
}

class JourneyNarrationDecision {
  const JourneyNarrationDecision({
    required this.shouldNarrate,
    required this.kind,
    required this.priority,
    required this.cooldownSeconds,
    required this.factIdsUsed,
    required this.sourceReferences,
    required this.warnings,
    this.narrationText,
    this.placeId,
    this.schedulerApplied = false,
    this.scheduleAction = 'Narrate',
    this.scheduleReason,
    this.storyId,
    this.storyExpiresUtc,
    this.estimatedDurationSeconds,
    this.rankingScore,
    this.rankingReasons = const [],
    this.audioCacheEligible = false,
    this.retentionClass = 'restricted',
  });

  final bool shouldNarrate;
  final String kind;
  final String priority;
  final String? narrationText;
  final String? placeId;
  final List<String> factIdsUsed;
  final List<LocationSourceReference> sourceReferences;
  final int cooldownSeconds;
  final List<String> warnings;
  final bool schedulerApplied;
  final String scheduleAction;
  final String? scheduleReason;
  final String? storyId;
  final DateTime? storyExpiresUtc;
  final int? estimatedDurationSeconds;
  final double? rankingScore;
  final List<String> rankingReasons;
  final bool audioCacheEligible;
  final String retentionClass;

  factory JourneyNarrationDecision.fromJson(Map<String, dynamic> json) {
    return JourneyNarrationDecision(
      shouldNarrate: json['shouldNarrate'] as bool? ?? false,
      kind: json['kind'] as String? ?? 'QuietWalk',
      priority: json['priority'] as String? ?? 'ContextualStory',
      narrationText: json['narrationText'] as String?,
      placeId: json['placeId'] as String?,
      factIdsUsed: _stringList(json['factIdsUsed']),
      sourceReferences: (json['sourceReferences'] as List? ?? const [])
          .map(
            (item) =>
                LocationSourceReference.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      cooldownSeconds: json['cooldownSeconds'] as int? ?? 90,
      warnings: _stringList(json['warnings']),
      schedulerApplied: json['schedulerApplied'] as bool? ?? false,
      scheduleAction: json['scheduleAction'] as String? ?? 'Narrate',
      scheduleReason: json['scheduleReason'] as String?,
      storyId: json['storyId'] as String?,
      storyExpiresUtc: DateTime.tryParse(
        json['storyExpiresUtc'] as String? ?? '',
      ),
      estimatedDurationSeconds: json['estimatedDurationSeconds'] as int?,
      rankingScore: (json['rankingScore'] as num?)?.toDouble(),
      rankingReasons: _stringList(json['rankingReasons']),
      audioCacheEligible: json['audioCacheEligible'] as bool? ?? false,
      retentionClass: json['retentionClass'] as String? ?? 'restricted',
    );
  }

  static List<String> _stringList(Object? value) {
    return (value as List? ?? const []).map((item) => item.toString()).toList();
  }
}

class StoryInteractionRequest {
  const StoryInteractionRequest({
    required this.eventId,
    required this.storyId,
    required this.category,
    required this.kind,
    required this.occurredAtUtc,
  });

  final String eventId;
  final String storyId;
  final String category;
  final String kind;
  final DateTime occurredAtUtc;

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'storyId': storyId,
    'category': category,
    'kind': kind,
    'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
  };
}
