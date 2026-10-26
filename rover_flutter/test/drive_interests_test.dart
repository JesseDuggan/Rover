import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/drives/scenic_drive.dart';
import 'package:rover/src/drives/drive_settings.dart';
import 'package:rover/src/drives/drive_interests_screen.dart';
import 'package:rover/src/ui/walk_about_theme.dart';
import 'package:rover/src/location/rover_location.dart';

import 'scenic_drive_test.dart' show origin, destination;

void main() {
  test('12 broad categories and 48 unique subcategories', () {
    expect(driveCategories, hasLength(12));
    final children = driveCategories.expand((c) => c.children.keys).toList();
    expect(children, hasLength(48));
    expect(children.toSet(), hasLength(48));
    expect(
      children,
      containsAll([
        'nature.national_parks',
        'nature.lakes',
        'scenic.coast',
        'history.castles',
        'family.playgrounds',
        'wildlife.sanctuaries',
      ]),
    );
  });
  test(
    'settings persist and overwrite without storing location or destination',
    () async {
      final dir = await Directory.systemTemp.createTemp('drive_settings_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/settings.json');
      final store = FileDriveSettingsStore(file: file);
      await store.save(
        const DriveSettings(
          interests: {'nature.lakes', 'towns'},
          preferences: DrivePreferences(
            preferLocalRoads: true,
            avoidTolls: true,
            maxDetourMinutes: 30,
          ),
        ),
      );
      var restored = await FileDriveSettingsStore(file: file).load();
      expect(restored.interests, {'nature.lakes', 'towns'});
      expect(restored.preferences.avoidTolls, true);
      await store.save(const DriveSettings(interests: {}));
      restored = await store.load();
      expect(restored.interests, isEmpty);
      expect(await file.readAsString(), isNot(contains('latitude')));
      await file.writeAsString('bad json');
      expect((await store.load()).interests, const DriveSettings().interests);
      expect(
        DriveSettings.fromJson({
          'interests': ['invented', 'nature.lakes'],
        }).interests,
        {'nature.lakes'},
      );
    },
  );
  test(
    'long trips split navigation without dropping visits or road preferences',
    () {
      final extra = List.generate(
        6,
        (i) => DrivePlace(
          id: 'p$i',
          name: 'Place $i',
          location: RoverLatLng(latitude: 43.7 + i * .01, longitude: 7.3),
        ),
      );
      final plan = DrivePlan(
        origin: origin,
        destination: destination,
        returnToStart: true,
        stops: extra,
        geometry: [origin, destination.location],
        drivingMinutes: 60,
        distanceMeters: 10000,
        stopMinutes: 105,
        bufferMinutes: 9,
        totalMinutes: 174,
        availableMinutes: 180,
        fitsBudget: true,
        warnings: const [],
        preferences: const DrivePreferences(
          preferLocalRoads: true,
          avoidTolls: true,
        ),
      );
      expect(plan.navigationSections, 2);
      final covered = <String>[];
      for (var section = 0; section < plan.navigationSections; section++) {
        final uri = plan.directions(section: section);
        final intermediate = uri.queryParameters['waypoints']!.split('|');
        expect(intermediate.length, lessThanOrEqualTo(3));
        expect(uri.queryParameters['avoid'], 'highways,tolls');
        covered.addAll([...intermediate, uri.queryParameters['destination']!]);
        if (section == 1) {
          expect(
            uri.queryParameters['origin'],
            '${extra[3].location.latitude},${extra[3].location.longitude}',
          );
        }
      }
      expect(
        covered,
        plan.visits
            .map((v) => '${v.location.latitude},${v.location.longitude}')
            .toList(),
      );
      expect(() => plan.directions(section: 2), throwsRangeError);
    },
  );
  for (final width in [320.0, 720.0]) {
    testWidgets('subcategory selection and cancel at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Set<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: walkAboutTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Choose interests'),
                onPressed: () async {
                  result = await Navigator.push<Set<String>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const DriveInterestsScreen(selected: {'scenic'}),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose interests'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parks, Lakes & Nature'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('National parks'));
      await tester.tap(find.text('National parks'));
      await tester.tap(find.text('Lakes'));
      await tester.tap(find.text('Use these interests'));
      await tester.pumpAndSettle();
      expect(result, {'scenic', 'nature.national_parks', 'nature.lakes'});
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Choose interests'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  }
}
