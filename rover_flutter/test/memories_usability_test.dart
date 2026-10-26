import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/accounts/account_library.dart';
import 'package:rover/src/memories/memories_screen.dart';
import 'package:rover/src/memories/memory_store.dart';
import 'package:rover/src/memories/memory_thumbnail.dart';
import 'package:rover/src/memories/saved_memory_walk_picker.dart';
import 'package:rover/src/sharing/shared_walks.dart';

import 'shared_walks_test.dart' as fixture;

class PendingWalkLibrary extends fixture.SharingLibrary {
  final pending = Completer<List<LibraryItem>>();
  @override
  Future<List<LibraryItem>> list(String kind) => pending.future;
}

void main() {
  test('Standalone sharing never bundles a route, even for linked media', () {
    final hidden = sharedDraft(
      null,
      'Our memories',
      [fixture.memory],
      ['friend'],
      false,
    );
    expect(hidden['route'], isEmpty);
    expect(hidden['media'][0]['location'], isNull);
    final located = sharedDraft(
      null,
      'Our memories',
      [fixture.memory],
      ['friend'],
      true,
    );
    expect(located['route'], isEmpty);
    expect(located['media'][0]['location'], isNotNull);
    expect(located.toString(), isNot(contains('Private home')));
  });
  testWidgets(
    'Standalone composer includes unattached media and requires selection',
    (tester) async {
      final library = fixture.SharingLibrary();
      await tester.pumpWidget(
        MaterialApp(
          home: ShareWalkScreen(
            library: library,
            store: fixture.SharingMemoryStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Share memories'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      await tester.tap(find.text('Bob'));
      await tester.pump();
      await tester.ensureVisible(find.text('Share with selected friends'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Share with selected friends'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Video'));
      await tester.tap(find.text('Video'));
      await tester.pump();
      await tester.ensureVisible(find.text('Share with selected friends'));
      await tester.tap(find.text('Share with selected friends'));
      await tester.pumpAndSettle();
      expect(find.text('Share these memories?'), findsOneWidget);
      expect(library.calls.where((c) => c.startsWith('POST')), isEmpty);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(library.draft!['route'], isEmpty);
      expect(library.draft!['media'], hasLength(1));
      expect(library.draft!['media'][0]['location'], isNull);
      expect(library.calls.last, 'POST /api/shared-walks/share/publish');
    },
  );
  for (final width in [320.0, 390.0, 844.0]) {
    testWidgets('Visible memories tabs and sharing fit $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: MemoriesScreen(store: fixture.SharingMemoryStore())),
      );
      await tester.pumpAndSettle();
      expect(find.text('All memories'), findsOneWidget);
      expect(find.text('By walk'), findsOneWidget);
      expect(find.byTooltip('Share memories'), findsOneWidget);
      await tester.tap(find.text('By walk'));
      await tester.pumpAndSettle();
      expect(find.text('Coastal walk'), findsOneWidget);
      await tester.tap(find.text('All memories'));
      await tester.pumpAndSettle();
      expect(find.text('Seafront'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'Attaching persists canonical route without moving capture or uploading',
    () async {
      final root = Directory.systemTemp.createTempSync('attach-memory');
      addTearDown(() => root.deleteSync(recursive: true));
      final store = MemoryStore(directory: Directory('${root.path}/store'));
      final source = await File('${root.path}/source.jpg').writeAsBytes([1, 2]);
      final saved = await store.save(
        source,
        video: false,
        details: MemoryDetails(
          caption: 'Keep caption',
          location: fixture.memory.details.location,
          capturedAt: DateTime.utc(2026, 10, 24),
          poiName: 'Old place',
        ),
      );
      await store.linkSession(fixture.journey.id, 'canonical');
      await store.attachToWalk(saved, fixture.journey);
      final reopened = (await MemoryStore(
        directory: store.directory,
      ).list()).single;
      expect(reopened.details.journey!.id, 'canonical');
      expect(reopened.details.caption, 'Keep caption');
      expect(
        reopened.details.location!.latitude,
        fixture.memory.details.location!.latitude,
      );
      expect(reopened.details.capturedAt, DateTime.utc(2026, 10, 24));
      expect(reopened.details.poiName, isNull);
      expect(await reopened.file.readAsBytes(), [1, 2]);
      await expectLater(
        store.attachToWalk(WalkMemory(source), fixture.journey),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
  testWidgets('Saved walk picker rejects late results after logout', (
    tester,
  ) async {
    final library = PendingWalkLibrary();
    await tester.pumpWidget(
      MaterialApp(home: SavedMemoryWalkPicker(library: library)),
    );
    await tester.pump();
    library.logout();
    library.pending.complete([
      const LibraryItem(
        id: 'private',
        name: 'Private saved walk',
        data: {},
        revision: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Private saved walk'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });
  testWidgets('Unavailable thumbnail falls back without starting playback', (
    tester,
  ) async {
    const channel = MethodChannel('ai.myrover.rover/memories');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      throw PlatformException(code: 'unreadable');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 100,
          height: 100,
          child: MemoryThumbnail(
            memory: WalkMemory(File('thumbnail-fixture.mp4')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.single.method, 'thumbnail');
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
