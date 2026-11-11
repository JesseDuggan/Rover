import 'rover_preferences.dart';

/// Current app profile snapshot, updated by PreferencesController, including
/// account changes and resets. Explicit journey interests override this default.
class StoryPreparationPreferences {
  static RoverPreferences current = const RoverPreferences();

  static Map<String, Object?> apply(Map<String, Object?> body) => {
    'interests': current.interests,
    'contentDepth': current.contentDepth,
    ...body,
  };
}
