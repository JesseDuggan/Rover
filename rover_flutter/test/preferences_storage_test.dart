import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/preferences/rover_preferences.dart';

void main() {
  test(
    'migrates cached preferences and keeps durable selections after restart',
    () async {
      final root = await Directory.systemTemp.createTemp('walk-preferences-');
      addTearDown(() => root.delete(recursive: true));
      final legacy = File('${root.path}/legacy.json');
      const preferences = RoverPreferences(
        interests: ['history'],
        includePaidAttractions: true,
      );
      await legacy.writeAsString(preferences.toJson());
      final support = Directory('${root.path}/support');
      FilePreferencesRepository repository() => FilePreferencesRepository(
        directoryProvider: () async => support,
        legacyFile: legacy,
      );
      expect((await repository().load()).interests, ['history']);
      expect(await legacy.exists(), isFalse);
      expect((await repository().load()).includePaidAttractions, isTrue);
      await repository().reset();
      expect((await repository().load()).interests, isEmpty);
    },
  );
}
