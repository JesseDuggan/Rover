import 'support/route_fixtures.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/active_roam/active_roam_controller.dart';
import 'package:rover/src/active_roam/active_roam_repository.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/active_roam/screen_awake_controller.dart';
import 'package:rover/src/location/rover_location.dart';

void main() {
  test('start pause resume and end update status and screen awake', () async {
    final awake = MemoryScreenAwakeController();
    final controller = ActiveRoamController(
      repository: MemoryActiveRoamRepository(demoSession()),
      screenAwakeController: awake,
    );
    await controller.load();

    await controller.resume();
    expect(controller.session.status, RoamSessionStatus.active);
    expect(controller.session.screenAwake, isTrue);
    expect(awake.enabled, isTrue);

    await controller.pause();
    expect(controller.session.status, RoamSessionStatus.paused);
    expect(awake.enabled, isFalse);

    await controller.resume();
    expect(controller.session.status, RoamSessionStatus.active);
    expect(awake.enabled, isTrue);

    await controller.end();
    expect(controller.session.status, RoamSessionStatus.ended);
    expect(awake.enabled, isFalse);
  });

  test(
    'arrival detection changes when simulated location reaches stop',
    () async {
      final controller = ActiveRoamController(
        repository: MemoryActiveRoamRepository(demoSession()),
        screenAwakeController: MemoryScreenAwakeController(),
      );
      await controller.load();
      await controller.resume();
      await controller.completeCurrentStop();

      await controller.updateLocation(
        const RoverLatLng(latitude: 37.0, longitude: -122.0),
      );
      expect(controller.session.arrivedAtCurrentStop, isFalse);

      await controller.updateLocation(
        controller.session.currentStop.coordinates,
      );
      expect(controller.session.arrivedAtCurrentStop, isTrue);
    },
  );

  test('complete and skip advance progress until completed', () async {
    final controller = ActiveRoamController(
      repository: MemoryActiveRoamRepository(demoSession()),
      screenAwakeController: MemoryScreenAwakeController(),
    );
    await controller.load();
    await controller.resume();

    await controller.completeCurrentStop();
    expect(controller.session.currentStop.name, 'Lotta\'s Fountain');
    expect(controller.session.progress, 0.2);

    await controller.skipCurrentStop();
    expect(controller.session.currentStop.name, 'Dragon Gate');
    expect(controller.session.progress, 0.4);

    while (controller.session.status != RoamSessionStatus.completed) {
      await controller.completeCurrentStop();
    }

    expect(controller.session.progress, 1);
    expect(controller.session.screenAwake, isFalse);
  });

  test('progress survives controller reload', () async {
    final repository = MemoryActiveRoamRepository(demoSession());
    final first = ActiveRoamController(
      repository: repository,
      screenAwakeController: MemoryScreenAwakeController(),
    );
    await first.load();
    await first.resume();
    await first.completeCurrentStop();

    final second = ActiveRoamController(
      repository: repository,
      screenAwakeController: MemoryScreenAwakeController(),
    );
    await second.load();

    expect(second.session.currentStop.name, 'Lotta\'s Fountain');
    expect(second.session.completedStopIds, contains('sf-demo-union-square'));
  });

  test(
    'arrival narration completion survives persistence and reload',
    () async {
      final repository = MemoryActiveRoamRepository(demoSession());
      final first = ActiveRoamController(
        repository: repository,
        screenAwakeController: MemoryScreenAwakeController(),
      );
      await first.load();
      await first.resume();
      await first.markArrivalNarrated('sf-demo-union-square');

      final second = ActiveRoamController(
        repository: repository,
        screenAwakeController: MemoryScreenAwakeController(),
      );
      await second.load();
      final restored = RoamSession.fromJson(second.session.toJson());

      expect(
        second.session.narratedArrivalStopIds,
        contains('sf-demo-union-square'),
      );
      expect(restored.narratedArrivalStopIds, contains('sf-demo-union-square'));
    },
  );

  test('demo route remains correctly ordered through Coit Tower', () {
    final session = demoSession();

    expect(session.orderedStops.map((orderedStop) => orderedStop.sequence), [
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(session.roam.stops.first.name, 'Union Square');
    expect(session.roam.stops.last.name, 'Coit Tower');
  });

  test('auto demo completes the San Francisco ROAM', () async {
    final controller = ActiveRoamController(
      repository: MemoryActiveRoamRepository(demoSession()),
      screenAwakeController: MemoryScreenAwakeController(),
    );
    await controller.load();

    await controller.resume();
    while (controller.session.status != RoamSessionStatus.completed) {
      await controller.completeCurrentStop();
    }

    expect(controller.session.status, RoamSessionStatus.completed);
    expect(controller.session.progress, 1);
    expect(controller.session.completedStopIds, hasLength(5));
  });
}
