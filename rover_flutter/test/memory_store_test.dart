import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/memories/memory_store.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/location/rover_location.dart';

void main() {
  late Directory temp;
  late MemoryStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('walk-memory-test');
    store = MemoryStore(directory: Directory('${temp.path}/memories'));
  });
  tearDown(() async => temp.delete(recursive: true));
  test('Upload mapping survives restart and is not listed as a memory', () async {
    await store.saveUploadFiles('share', {'remote': 'local.jpg'});
    final reopened = MemoryStore(directory: store.directory);
    expect(await reopened.uploadFiles('share'), {'remote': 'local.jpg'});
    expect(await reopened.list(), isEmpty);
    await reopened.saveUploadFiles('share', {'remote': 'other.jpg'});
    expect(await store.uploadFiles('share'), {'remote': 'other.jpg'});
    await reopened.forgetUpload('share');
    expect(await store.uploadFiles('share'), isEmpty);
  });
  test('Route, position, caption and capture time survive reopening', () async {
    final source = await File('${temp.path}/source.jpg').writeAsBytes([1]);
    final when = DateTime.utc(2026, 10, 23);
    const point = RoverLatLng(latitude: 43.7, longitude: 7.26);
    final journey = MemoryJourney(
      id: 'original',
      route: RoverRoam(
        title: 'Nice',
        summary: 'Along the coast',
        walkingMinutes: 30,
        distanceMiles: 1,
        startingPoint: 'Nice',
        stops: const [],
        routeGeometry: const [point],
        accessibilityNotes: const [],
        warnings: const [],
      ),
    );
    final saved = await store.save(
      source,
      video: false,
      details: MemoryDetails(
        journey: journey,
        capturedAt: when,
        location: point,
        accuracyMeters: 8,
        poiName: 'Promenade',
        caption: 'Our walk',
      ),
    );
    final reopened = MemoryStore(directory: store.directory);
    final memory = (await reopened.list()).single;
    expect(memory.details.journey!.id, 'original');
    expect(memory.details.journey!.route.routeGeometry.single.latitude, 43.7);
    expect(memory.details.location!.longitude, 7.26);
    expect(memory.details.capturedAt, when);
    expect(memory.details.poiName, 'Promenade');
    await reopened.updateDetails(
      memory,
      memory.details.withCaption('  Family day  '),
    );
    final edited = (await reopened.list()).single;
    expect(edited.details.caption, 'Family day');
    expect(edited.details.journey!.id, 'original');
    await reopened.renameJourney(journey, '  Nice with family  ');
    final renamed = (await MemoryStore(directory: store.directory).list()).single;
    expect(renamed.details.journey!.displayName, 'Nice with family');
    expect(renamed.details.capturedAt, when);
    expect(renamed.details.location!.longitude, 7.26);
    expect(renamed.details.caption, 'Family day');
    expect(
      await File('${saved.file.path}.json').readAsString(),
      contains('"visibility":"private"'),
    );
    await reopened.delete(edited);
    expect(await File('${saved.file.path}.json').exists(), false);
  });
  test(
    'Reopened preview sessions keep the original route across restarts',
    () async {
      await store.linkSession('preview-1', 'original');
      await store.linkSession('preview-2', 'preview-1');
      final reopened = MemoryStore(directory: store.directory);
      expect(await reopened.journeyId('preview-1'), 'original');
      expect(await reopened.journeyId('preview-2'), 'original');
      expect(await reopened.journeyId('another-walk'), 'another-walk');
      expect(await reopened.list(), isEmpty);
    },
  );
  test('Legacy captures and missing location remain accessible', () async {
    await store.directory!.create();
    final file = await File('${store.directory!.path}/123-456.jpg')
        .writeAsBytes([1]);
    expect((await store.list()).single.details.location, isNull);
    await File('${file.path}.json').writeAsString('{broken');
    expect((await store.list()).single.details.journey, isNull);
    await store.updateDetails(
      WalkMemory(file),
      const MemoryDetails(caption: 'No GPS'),
    );
    expect((await store.list()).single.details.caption, 'No GPS');
  });
  test('Memory survives reload and owns its copy', () async {
    final source = await File('${temp.path}/source.jpg')
        .writeAsBytes([1, 2, 3]);
    final item = await store.save(source, video: false);
    await source.delete();
    final restored = await MemoryStore(directory: store.directory).list();
    expect(restored.single.id, item.id);
    expect(await restored.single.file.readAsBytes(), [1, 2, 3]);
    expect(restored.single.isVideo, false);
    await store.delete(restored.single);
    expect(await store.list(), isEmpty);
  });
  test('Videos are private files and incomplete writes are hidden', () async {
    final source = await File('${temp.path}/source.mp4').writeAsBytes([1]);
    expect((await store.save(source, video: true)).isVideo, true);
    await File('${store.directory!.path}/unfinished.pending').writeAsBytes([1]);
    expect(await store.list(), hasLength(1));
  });
  test('Empty media and deleting outside the store are rejected', () async {
    final source = await File('${temp.path}/source.jpg').writeAsBytes([]);
    await expectLater(
      store.save(source, video: false),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      store.delete(WalkMemory(source)),
      throwsA(isA<FileSystemException>()),
    );
    expect(await source.exists(), true);
  });
}
