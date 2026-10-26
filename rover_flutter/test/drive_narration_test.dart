import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_story_models.dart';
import 'package:rover/src/drives/drive_narration.dart';
import 'package:rover/src/drives/scenic_drive.dart';
import 'package:rover/src/drives/scenic_drive_screen.dart';
import 'package:rover/src/drives/drive_settings.dart';
import 'package:rover/src/location/location_controller.dart';

import 'scenic_drive_test.dart' show FakeDrives, origin, destination;
import 'support/location_fixtures.dart';

class FakeNarration implements DriveNarration {
  final events = <String>[];
  bool active = false;
  bool fail = false;
  @override
  Future<Map<String, String>> prepare(DrivePlan plan) async {
    events.add('prepare');
    return {
      for (final p in [...plan.stops, plan.destination]) p.id: 'Audio ready',
    };
  }

  @override
  Future<void> start(DrivePlan plan, {DrivePlace? leg}) async {
    events.add('start');
    if (fail) throw StateError('Precise location is required.');
    active = true;
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    active = false;
  }

  @override
  Future<bool> isActive() async => active;
}

void main() {
  test('only matching, sourced, unexpired stories may play', () {
    final now = DateTime.utc(2026, 10, 25);
    final json = <String, dynamic>{
      'placeId': destination.id,
      'shortSpokenNarration': 'Verified introduction.',
      'factIdsUsed': ['one'],
      'sourceReferences': [
        {'providerName': 'Archive', 'attribution': 'Archive'},
      ],
      'researchStatus': 'ready',
      'expiresUtc': now.add(const Duration(hours: 1)).toIso8601String(),
    };
    expect(
      usableDriveStory(LocationStoryResponse.fromJson(json), destination, now),
      isTrue,
    );
    for (final change in [
      {'placeId': 'other'},
      {'factIdsUsed': []},
      {'sourceReferences': []},
      {'researchStatus': 'failed'},
      {'shortSpokenNarration': ''},
      {
        'expiresUtc': now
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      },
    ]) {
      expect(
        usableDriveStory(
          LocationStoryResponse.fromJson({...json, ...change}),
          destination,
          now,
        ),
        isFalse,
      );
    }
  });
  for (final width in [320.0, 720.0]) {
    testWidgets('prepare and start before Maps, stop on failure at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final location = LocationController(
        realProvider: SimulatedLocationProvider(route: const [origin]),
      );
      addTearDown(location.dispose);
      final narration = FakeNarration();
      var launchWorks = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ScenicDriveScreen(
            repository: FakeDrives(),
            location: location,
            settingsStore: MemoryDriveSettingsStore(),
            narration: narration,
            beforeNavigate: () async => true,
            tellHere: () {},
            launchDirections: (_) async {
              expect(narration.active, isTrue);
              narration.events.add('maps');
              return launchWorks;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sanremo');
      await tester.tap(find.text('Find destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sanremo, Italy'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Plan drive'));
      await tester.tap(find.text('Plan drive'));
      await tester.pumpAndSettle();
      Future<void> openDirections() async {
        await tester.scrollUntilVisible(find.text('Open driving directions').hitTestable(),
            150, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open driving directions').hitTestable());
        await tester.pumpAndSettle();
      }
      await openDirections();
      expect(narration.events.sublist(narration.events.length - 3), [
        'prepare',
        'start',
        'maps',
      ]);
      expect(find.text('Stop drive stories'), findsOneWidget);
      expect(tester.takeException(), isNull);
      launchWorks = false;
      await openDirections();
      expect(narration.active, isFalse);
      expect(narration.events.last, 'stop');
      final mapsBefore = narration.events.where((e) => e == 'maps').length;
      narration.fail = true;
      await openDirections();
      expect(narration.events.where((e) => e == 'maps').length, mapsBefore);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(narration.events.last, 'stop');
    });
  }
}
