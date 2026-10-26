import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/memories/memory_store.dart';
import 'package:rover/src/memories/memories_screen.dart';
import 'package:rover/src/adventure/roam.dart';

void main() {
  testWidgets('Privacy lock persists only after confirmation and disables sharing', (tester) async {
    final store = PrivacyMemoryStore();
    final memory = WalkMemory(File('missing.jpg'));
    await tester.pumpWidget(MaterialApp(home: MemoryViewer(memory: memory, store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep this memory private'));
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    await tester.tap(find.text('Keep private'));
    await tester.pumpAndSettle();
    expect(store.saved!.sharingLocked, isTrue);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Share memory')).onPressed, isNull);
    await tester.tap(find.text('Keep this memory private'));
    await tester.pumpAndSettle();
    expect(store.saved!.sharingLocked, isFalse);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Share memory')).onPressed, isNotNull);
  });
  testWidgets('Adventure history groups routes and filters reopened sessions', (
    tester,
  ) async {
    final route = RoverRoam(
      title: 'Nice',
      summary: 'Coastal walk',
      walkingMinutes: 30,
      distanceMiles: 1,
      startingPoint: 'Nice',
      stops: const [],
      routeGeometry: const [],
      accessibilityNotes: const [],
      warnings: const [],
    );
    final journey = MemoryJourney(id: 'original', route: route);
    final store = JourneyMemoryStore([
      WalkMemory(
        File('1-1.mp4'),
        details: MemoryDetails(journey: journey, caption: 'Coastal memory'),
      ),
      WalkMemory(
        File('2-2.mp4'),
        details: MemoryDetails(journey: journey, caption: 'Second memory'),
      ),
      WalkMemory(
        File('3-3.mp4'),
        details: const MemoryDetails(caption: 'Unattached'),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: MemoriesScreen(store: store, showHistory: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nice'), findsOneWidget);
    expect(find.text('2 memories - Private on this device'), findsOneWidget);
    await tester.tap(find.text('Nice'));
    await tester.pumpAndSettle();
    expect(find.text('Coastal memory'), findsOneWidget);
    expect(find.text('Unattached'), findsNothing);
    expect(find.byTooltip('Capture a memory'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: MemoriesScreen(
          store: store,
          journey: MemoryJourney(id: 'preview', route: route),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coastal memory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Empty memories has capture and refresh controls', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('memory-ui');
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(home: MemoriesScreen(store: EmptyMemoryStore())),
    );
    await tester.pumpAndSettle();
    expect(find.text('No memories yet'), findsOneWidget);
    expect(find.byTooltip('Capture a memory'), findsOneWidget);
    expect(find.byTooltip('Refresh memories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Photo viewer closes completely without deleting the memory', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('memory-viewer');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = MemoryStore(directory: root);
    final memory = WalkMemory(File('${root.path}/missing.jpg'));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemoryViewer(memory: memory, store: store),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete memory'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this memory?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(MemoryViewer), findsNothing);
  });
}

class EmptyMemoryStore extends MemoryStore {
  @override
  Future<List<WalkMemory>> list() async => [];
}
class PrivacyMemoryStore extends MemoryStore {
  MemoryDetails? saved;
  @override
  Future<void> updateDetails(WalkMemory memory, MemoryDetails details) async { saved = details; }
}

class JourneyMemoryStore extends MemoryStore {
  JourneyMemoryStore(this.items);
  final List<WalkMemory> items;
  @override
  Future<List<WalkMemory>> list() async => items;
  @override
  Future<String> journeyId(String sessionId) async =>
      sessionId == 'preview' ? 'original' : sessionId;
}
