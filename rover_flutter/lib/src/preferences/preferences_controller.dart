import 'package:flutter/widgets.dart';

import 'preferences_repository.dart';
import 'rover_preferences.dart';

class PreferencesController extends ChangeNotifier {
  PreferencesController(this._repository);

  final PreferencesRepository _repository;

  RoverPreferences _preferences = const RoverPreferences();
  bool _isLoaded = false;

  RoverPreferences get preferences => _preferences;

  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _preferences = await _repository.load();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> save(RoverPreferences preferences) async {
    _preferences = preferences;
    await _repository.save(preferences);
    notifyListeners();
  }

  Future<void> continueAsGuest() async {
    await save(
      _preferences.copyWith(completedOnboarding: true, continueAsGuest: true),
    );
  }

  Future<void> reset() async {
    await _repository.reset();
    _preferences = const RoverPreferences();
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
