import 'dart:io';

import 'package:flutter/foundation.dart';

import 'rover_preferences.dart';

abstract class PreferencesRepository {
  Future<RoverPreferences> load();

  Future<void> save(RoverPreferences preferences);

  Future<void> reset();
}

class FilePreferencesRepository implements PreferencesRepository {
  FilePreferencesRepository({File? file})
    : _file = kIsWeb
          ? null
          : file ??
                File(
                  '${Directory.systemTemp.path}'
                  '${Platform.pathSeparator}'
                  'rover_preferences.json',
                );

  final File? _file;
  RoverPreferences _webPreferences = const RoverPreferences();

  @override
  Future<RoverPreferences> load() async {
    final file = _file;

    if (file == null) {
      return _webPreferences;
    }

    if (!await file.exists()) {
      return const RoverPreferences();
    }

    final source = await file.readAsString();

    if (source.trim().isEmpty) {
      return const RoverPreferences();
    }

    return RoverPreferences.fromJson(source);
  }

  @override
  Future<void> reset() async {
    final file = _file;

    if (file == null) {
      _webPreferences = const RoverPreferences();
      return;
    }

    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> save(RoverPreferences preferences) async {
    final file = _file;

    if (file == null) {
      _webPreferences = preferences;
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(preferences.toJson());
  }
}

class MemoryPreferencesRepository implements PreferencesRepository {
  RoverPreferences _preferences;

  MemoryPreferencesRepository([this._preferences = const RoverPreferences()]);

  @override
  Future<RoverPreferences> load() async => _preferences;

  @override
  Future<void> reset() async {
    _preferences = const RoverPreferences();
  }

  @override
  Future<void> save(RoverPreferences preferences) async {
    _preferences = preferences;
  }
}
