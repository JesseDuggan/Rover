import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'scenic_drive.dart';

class DriveSettings {
  const DriveSettings({
    this.interests = const {'scenic', 'history'},
    this.preferences = const DrivePreferences(preferLocalRoads: true),
  });
  final Set<String> interests;
  final DrivePreferences preferences;
  Map<String, dynamic> toJson() => {
    'interests': interests.toList(),
    'preferences': preferences.toJson(),
  };
  factory DriveSettings.fromJson(Map<String, dynamic> json) {
    final valid = {
      for (final c in driveCategories) c.id,
      for (final c in driveCategories) ...c.children.keys,
    };
    return DriveSettings(
      interests: (json['interests'] as List? ?? ['scenic', 'history'])
          .whereType<String>()
          .where(valid.contains)
          .toSet(),
      preferences: DrivePreferences.fromJson(
        json['preferences'] as Map<String, dynamic>? ??
            {'preferLocalRoads': true},
      ),
    );
  }
}

abstract interface class DriveSettingsStore {
  Future<DriveSettings> load();
  Future<void> save(DriveSettings settings);
}

class FileDriveSettingsStore implements DriveSettingsStore {
  FileDriveSettingsStore({this.file});
  final File? file;
  Future<File> _file() async =>
      file ??
      File(
        '${(await getApplicationSupportDirectory()).path}/drive_settings.json',
      );
  @override
  Future<DriveSettings> load() async {
    final target = await _file();
    if (!await target.exists()) return const DriveSettings();
    try {
      return DriveSettings.fromJson(
        jsonDecode(await target.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      return const DriveSettings();
    } on TypeError {
      return const DriveSettings();
    }
  }

  @override
  Future<void> save(DriveSettings settings) async {
    final target = await _file();
    await target.parent.create(recursive: true);
    final pending = File('${target.path}.tmp');
    await pending.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await pending.rename(target.path);
  }
}

class MemoryDriveSettingsStore implements DriveSettingsStore {
  MemoryDriveSettingsStore([this.value = const DriveSettings()]);
  DriveSettings value;
  @override
  Future<DriveSettings> load() async => value;
  @override
  Future<void> save(DriveSettings settings) async {
    value = settings;
  }
}
