import 'dart:convert';

class RoverPreferences {
  const RoverPreferences({
    this.firstName = '',
    this.interests = const [],
    this.walkingPace = '',
    this.availableTime = '',
    this.mobility = '',
    this.contentDepth = '',
    this.storyDensity = 'Highlights',
    this.excludedStoryCategories = const [],
    this.audioPreference = '',
    this.notifications = '',
    this.distanceUnit = '',
    this.language = '',
    this.completedOnboarding = false,
    this.continueAsGuest = false,
    this.developmentApiBaseUrl = '',
  });

  final String firstName;
  final List<String> interests;
  final String walkingPace;
  final String availableTime;
  final String mobility;
  final String contentDepth;
  final String storyDensity;
  final List<String> excludedStoryCategories;
  final String audioPreference;
  final String notifications;
  final String distanceUnit;
  final String language;
  final bool completedOnboarding;
  final bool continueAsGuest;
  final String developmentApiBaseUrl;

  bool get hasPersonalDetails =>
      firstName.trim().isNotEmpty || interests.isNotEmpty;

  RoverPreferences copyWith({
    String? firstName,
    List<String>? interests,
    String? walkingPace,
    String? availableTime,
    String? mobility,
    String? contentDepth,
    String? storyDensity,
    List<String>? excludedStoryCategories,
    String? audioPreference,
    String? notifications,
    String? distanceUnit,
    String? language,
    bool? completedOnboarding,
    bool? continueAsGuest,
    String? developmentApiBaseUrl,
  }) {
    return RoverPreferences(
      firstName: firstName ?? this.firstName,
      interests: interests ?? this.interests,
      walkingPace: walkingPace ?? this.walkingPace,
      availableTime: availableTime ?? this.availableTime,
      mobility: mobility ?? this.mobility,
      contentDepth: contentDepth ?? this.contentDepth,
      storyDensity: storyDensity ?? this.storyDensity,
      excludedStoryCategories:
          excludedStoryCategories ?? this.excludedStoryCategories,
      audioPreference: audioPreference ?? this.audioPreference,
      notifications: notifications ?? this.notifications,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      language: language ?? this.language,
      completedOnboarding: completedOnboarding ?? this.completedOnboarding,
      continueAsGuest: continueAsGuest ?? this.continueAsGuest,
      developmentApiBaseUrl:
          developmentApiBaseUrl ?? this.developmentApiBaseUrl,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'firstName': firstName,
      'interests': interests,
      'walkingPace': walkingPace,
      'availableTime': availableTime,
      'mobility': mobility,
      'contentDepth': contentDepth,
      'storyDensity': storyDensity,
      'excludedStoryCategories': excludedStoryCategories,
      'audioPreference': audioPreference,
      'notifications': notifications,
      'distanceUnit': distanceUnit,
      'language': language,
      'completedOnboarding': completedOnboarding,
      'continueAsGuest': continueAsGuest,
      'developmentApiBaseUrl': developmentApiBaseUrl,
    };
  }

  factory RoverPreferences.fromMap(Map<String, Object?> map) {
    return RoverPreferences(
      firstName: map['firstName'] as String? ?? '',
      interests:
          (map['interests'] as List<dynamic>?)?.cast<String>() ?? const [],
      walkingPace: map['walkingPace'] as String? ?? '',
      availableTime: map['availableTime'] as String? ?? '',
      mobility: map['mobility'] as String? ?? '',
      contentDepth: map['contentDepth'] as String? ?? '',
      storyDensity: map['storyDensity'] as String? ?? 'Highlights',
      excludedStoryCategories:
          (map['excludedStoryCategories'] as List<dynamic>?)?.cast<String>() ??
          const [],
      audioPreference: map['audioPreference'] as String? ?? '',
      notifications: map['notifications'] as String? ?? '',
      distanceUnit: map['distanceUnit'] as String? ?? '',
      language: map['language'] as String? ?? '',
      completedOnboarding: map['completedOnboarding'] as bool? ?? false,
      continueAsGuest: map['continueAsGuest'] as bool? ?? false,
      developmentApiBaseUrl: map['developmentApiBaseUrl'] as String? ?? '',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory RoverPreferences.fromJson(String source) {
    return RoverPreferences.fromMap(jsonDecode(source) as Map<String, Object?>);
  }
}
