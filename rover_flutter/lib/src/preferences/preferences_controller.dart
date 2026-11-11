import 'package:flutter/widgets.dart';

import 'preferences_repository.dart';
import 'rover_preferences.dart';
import 'story_preparation_preferences.dart';

class PreferencesController extends ChangeNotifier {
  PreferencesController(this._repository);

  final PreferencesRepository _repository;

  RoverPreferences _preferences = const RoverPreferences();
  RoverPreferences _persisted = const RoverPreferences();
  bool _isLoaded = false;
  Future<void> _pendingSave = Future.value();

  RoverPreferences get preferences => _preferences;

  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _preferences = await _repository.load();
    _persisted = _preferences;
    _isLoaded = true;
    StoryPreparationPreferences.current = _preferences;
    notifyListeners();
  }

  Future<void> save(RoverPreferences preferences) async {
    _preferences = preferences;
    StoryPreparationPreferences.current = _preferences;
    notifyListeners();
    final write = _pendingSave.then((_) => _repository.save(preferences));
    _pendingSave = write.catchError((Object _) {});
    try {
      await write;
      _persisted = preferences;
    } catch (_) {
      if (identical(_preferences, preferences)) {
        _preferences = _persisted;
        StoryPreparationPreferences.current = _preferences;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> continueAsGuest() async {
    await save(
      _preferences.copyWith(completedOnboarding: true, continueAsGuest: true),
    );
  }

  Future<void> reset() async {
    await _pendingSave;
    await _repository.reset();
    _preferences = const RoverPreferences();
    _persisted = _preferences;
    StoryPreparationPreferences.current = _preferences;
    notifyListeners();
  }
}

class PreferencesScope extends InheritedNotifier<PreferencesController> {
  const PreferencesScope({
    required PreferencesController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static PreferencesController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PreferencesScope>();
    assert(scope != null, 'No PreferencesScope found in context.');
    return scope!.notifier!;
  }
}
