import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'rover_preferences.dart';

abstract class PreferencesRepository {
  Future<RoverPreferences> load();

  Future<void> save(RoverPreferences preferences);

  Future<void> reset();
}

class FilePreferencesRepository implements PreferencesRepository {
  FilePreferencesRepository({
    File? file,
    Future<Directory> Function()? directoryProvider,
    this.legacyFile,
  }) : _explicitFile = file,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final File? _explicitFile;
  final Future<Directory> Function() _directoryProvider;
  final File? legacyFile;
  Future<File?>? _resolvedFile;

  Future<File?> _file() => _resolvedFile ??= _resolveFile();

  Future<File?> _resolveFile() async {
    if (kIsWeb) return null;
    if (_explicitFile != null) return _explicitFile;
    final directory = await _directoryProvider();
    final file = File('${directory.path}/rover_preferences.json');
    final legacy =
        legacyFile ??
        File('${Directory.systemTemp.path}/rover_preferences.json');
    if (!await file.exists() && await legacy.exists()) {
      await file.parent.create(recursive: true);
      await legacy.copy(file.path);
    }
    // Remove the old cache only after a durable copy exists.
    if (await file.exists() && await legacy.exists()) await legacy.delete();
    return file;
  }

  RoverPreferences _webPreferences = const RoverPreferences();

  @override
  Future<RoverPreferences> load() async {
    final file = await _file();

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
    final file = await _file();

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
    final file = await _file();

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
