class GuestProfileRequest {
  const GuestProfileRequest({required this.installationId});

  final String installationId;

  Map<String, Object?> toJson() => {'installationId': installationId};
}

class UpdateProfilePreferencesRequest {
  const UpdateProfilePreferencesRequest({
    this.interests,
    this.walkingPace,
    this.accessibilityNeeds,
    this.distanceUnits,
    this.directionVoiceEnabled,
    this.narrationEnabled,
    this.speechRate,
    this.preferredNarrationLength,
    this.storyDensity,
    this.excludedStoryCategories,
    this.premiumVoiceEnabled,
    this.askRoverVoiceEnabled,
    this.autoPlayNarrationOnArrival,
    this.resumeNarrationAfterNavigation,
    this.deviceVoiceFallbackEnabled,
    this.saveWalkHistory,
    this.improveRecommendations,
    this.locationRetention,
  });

  final List<String>? interests;
  final String? walkingPace;
  final List<String>? accessibilityNeeds;
  final String? distanceUnits;
  final bool? directionVoiceEnabled;
  final bool? narrationEnabled;
  final double? speechRate;
  final String? preferredNarrationLength;
  final String? storyDensity;
  final List<String>? excludedStoryCategories;
  final bool? premiumVoiceEnabled;
  final bool? askRoverVoiceEnabled;
  final bool? autoPlayNarrationOnArrival;
  final bool? resumeNarrationAfterNavigation;
  final bool? deviceVoiceFallbackEnabled;
  final bool? saveWalkHistory;
  final bool? improveRecommendations;
  final String? locationRetention;

  Map<String, Object?> toJson() {
    return {
      'interests': interests,
      'walkingPace': walkingPace,
      'accessibilityNeeds': accessibilityNeeds,
      'distanceUnits': distanceUnits,
      'directionVoiceEnabled': directionVoiceEnabled,
      'narrationEnabled': narrationEnabled,
      'speechRate': speechRate,
      'preferredNarrationLength': preferredNarrationLength,
      'storyDensity': storyDensity,
      'excludedStoryCategories': excludedStoryCategories,
      'premiumVoiceEnabled': premiumVoiceEnabled,
      'askRoverVoiceEnabled': askRoverVoiceEnabled,
      'autoPlayNarrationOnArrival': autoPlayNarrationOnArrival,
      'resumeNarrationAfterNavigation': resumeNarrationAfterNavigation,
      'deviceVoiceFallbackEnabled': deviceVoiceFallbackEnabled,
      'saveWalkHistory': saveWalkHistory,
      'improveRecommendations': improveRecommendations,
      'locationRetention': locationRetention,
    };
  }
}

class SaveDiscoveryRequest {
  const SaveDiscoveryRequest({
    required this.discoveryId,
    required this.name,
    required this.category,
    required this.source,
  });

  final String discoveryId;
  final String name;
  final String category;
  final String source;

  Map<String, Object?> toJson() {
    return {
      'discoveryId': discoveryId,
      'name': name,
      'category': category,
      'source': source,
    };
  }
}

class GuestProfile {
  const GuestProfile({
    required this.profileId,
    required this.installationId,
    required this.preferences,
    required this.savedDiscoveries,
    required this.learnedPreferences,
    this.storyInteractionCount = 0,
  });

  final String profileId;
  final String installationId;
  final ProfilePreferences preferences;
  final List<SavedDiscovery> savedDiscoveries;
  final List<LearnedPreference> learnedPreferences;
  final int storyInteractionCount;

  factory GuestProfile.fromJson(Map<String, dynamic> json) {
    return GuestProfile(
      profileId: json['profileId'] as String,
      installationId: json['installationId'] as String,
      preferences: ProfilePreferences.fromJson(
        json['preferences'] as Map<String, dynamic>,
      ),
      savedDiscoveries: _list(json['savedDiscoveries'])
          .map((item) => SavedDiscovery.fromJson(item as Map<String, dynamic>))
          .toList(),
      learnedPreferences: _list(json['learnedPreferences'])
          .map(
            (item) => LearnedPreference.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      storyInteractionCount: json['storyInteractionCount'] as int? ?? 0,
    );
  }
}

class ProfilePreferences {
  const ProfilePreferences({
    required this.interests,
    required this.walkingPace,
    required this.accessibilityNeeds,
    required this.distanceUnits,
    required this.directionVoiceEnabled,
    required this.narrationEnabled,
    required this.speechRate,
    required this.preferredNarrationLength,
    required this.storyDensity,
    required this.excludedStoryCategories,
    required this.premiumVoiceEnabled,
    required this.askRoverVoiceEnabled,
    required this.autoPlayNarrationOnArrival,
    required this.resumeNarrationAfterNavigation,
    required this.deviceVoiceFallbackEnabled,
    required this.saveWalkHistory,
    required this.improveRecommendations,
    required this.locationRetention,
  });

  final List<String> interests;
  final String walkingPace;
  final List<String> accessibilityNeeds;
  final String distanceUnits;
  final bool directionVoiceEnabled;
  final bool narrationEnabled;
  final double speechRate;
  final String preferredNarrationLength;
  final String storyDensity;
  final List<String> excludedStoryCategories;
  final bool premiumVoiceEnabled;
  final bool askRoverVoiceEnabled;
  final bool autoPlayNarrationOnArrival;
  final bool resumeNarrationAfterNavigation;
  final bool deviceVoiceFallbackEnabled;
  final bool saveWalkHistory;
  final bool improveRecommendations;
  final String locationRetention;

  factory ProfilePreferences.fromJson(Map<String, dynamic> json) {
    return ProfilePreferences(
      interests: _stringList(json['interests']),
      walkingPace: json['walkingPace'] as String,
      accessibilityNeeds: _stringList(json['accessibilityNeeds']),
      distanceUnits: json['distanceUnits'] as String,
      directionVoiceEnabled: json['directionVoiceEnabled'] as bool,
      narrationEnabled: json['narrationEnabled'] as bool,
      speechRate: (json['speechRate'] as num).toDouble(),
      preferredNarrationLength: json['preferredNarrationLength'] as String,
      storyDensity: json['storyDensity'] as String? ?? 'Highlights',
      excludedStoryCategories: _stringList(json['excludedStoryCategories']),
      premiumVoiceEnabled: json['premiumVoiceEnabled'] as bool? ?? true,
      askRoverVoiceEnabled: json['askRoverVoiceEnabled'] as bool? ?? true,
      autoPlayNarrationOnArrival:
          json['autoPlayNarrationOnArrival'] as bool? ?? true,
      resumeNarrationAfterNavigation:
          json['resumeNarrationAfterNavigation'] as bool? ?? true,
      deviceVoiceFallbackEnabled:
          json['deviceVoiceFallbackEnabled'] as bool? ?? true,
      saveWalkHistory: json['saveWalkHistory'] as bool,
      improveRecommendations: json['improveRecommendations'] as bool,
      locationRetention: json['locationRetention'] as String,
    );
  }
}

class SavedDiscovery {
  const SavedDiscovery({
    required this.discoveryId,
    required this.name,
    required this.category,
    required this.savedAtUtc,
    required this.source,
  });

  final String discoveryId;
  final String name;
  final String category;
  final DateTime savedAtUtc;
  final String source;

  factory SavedDiscovery.fromJson(Map<String, dynamic> json) {
    return SavedDiscovery(
      discoveryId: json['discoveryId'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      savedAtUtc: DateTime.parse(json['savedAtUtc'] as String),
      source: json['source'] as String,
    );
  }
}

class LearnedPreference {
  const LearnedPreference({
    required this.topic,
    required this.score,
    required this.reason,
  });

  final String topic;
  final int score;
  final String reason;

  factory LearnedPreference.fromJson(Map<String, dynamic> json) {
    return LearnedPreference(
      topic: json['topic'] as String,
      score: json['score'] as int,
      reason: json['reason'] as String,
    );
  }
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) {
  return value is List
      ? value.map((item) => item.toString()).toList()
      : const [];
}
