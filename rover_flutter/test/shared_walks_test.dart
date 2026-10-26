import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/accounts/account_library.dart';
import 'package:rover/src/api/rover_api_config.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/memories/memory_store.dart';
import 'package:rover/src/sharing/shared_walks.dart';
import 'package:rover/src/sharing/retry_share_screen.dart';
import 'package:rover/src/memories/walk_trail_store.dart';
import 'package:rover/src/sharing/shared_replay_screen.dart';
import 'package:rover/src/sharing/story_share_data.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';

class SharingTrail extends WalkTrailStore {
  @override
  Future<List<Map<String, dynamic>>> readJourney(String id) async => [
    {
      'at': '2026-10-25T12:00:00Z',
      'latitude': 43.0,
      'longitude': 7.0,
      'segment': 0,
    },
    {
      'at': '2026-10-25T12:00:10Z',
      'latitude': 43.0001,
      'longitude': 7.0,
      'segment': 0,
    },
  ];
}

final journey = MemoryJourney(
  id: 'route',
  route: RoverRoam(
    title: 'Nice',
    summary: 'Coastal walk',
    walkingMinutes: 30,
    distanceMiles: 1,
    startingPoint: 'Private home',
    stops: const [],
    routeGeometry: const [
      RoverLatLng(latitude: 43, longitude: 7),
      RoverLatLng(latitude: 43.01, longitude: 7.01),
    ],
    accessibilityNotes: const [],
    warnings: const [],
  ),
);
final memory = WalkMemory(
  File('1-1.mp4'),
  details: MemoryDetails(
    journey: journey,
    caption: 'Seafront',
    location: const RoverLatLng(latitude: 43, longitude: 7),
  ),
);

class SharingMemoryStore extends MemoryStore {
  final mappings = <String, Map<String, String>>{};
  @override
  Future<void> saveUploadFiles(String id, Map<String, String> files) async { mappings[id] = Map.of(files); }
  @override
  Future<Map<String, String>> uploadFiles(String id) async => mappings[id] ?? {};
  @override
  Future<void> forgetUpload(String id) async { mappings.remove(id); }
  @override
  Future<List<WalkMemory>> list() async => [
    memory,
    WalkMemory(File('2-2.mp4')),
  ];
  @override
  Future<String> journeyId(String id) async => id;
}

class SharingLibrary extends AccountLibrary {
  SharingLibrary()
    : super(config: const RoverApiConfig(baseUrl: 'https://example.com'));
  bool loggedIn = true, failUpload = false;
  Completer<void>? uploadHold;
  int generation = 0;
  final calls = <String>[];
  Map<String, dynamic>? draft;
  Completer<dynamic>? create;
  bool supportsStories = true;
  bool unfinished = false;
  final uploaded = <String>[];
  List<LibraryItem> savedWalks = [];
  @override
  Future<List<LibraryItem>> list(String kind) async => savedWalks;
  bool supportsAudience = true, owned = false, private = false;
  @override
  bool get signedIn => loggedIn;
  @override
  int get sessionGeneration => generation;
  @override
  Future<void> load() async {}
  void logout() {
    loggedIn = false;
    generation++;
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    calls.add('$method $path');
    if (method == 'POST' && path.endsWith('/private')) {
      private = true;
      return null;
    }
    if (path == '/api/friends/state')
      return {
        'profile': {'id': 'a', 'username': 'alice', 'displayName': 'Alice'},
        'connections': [
          {
            'member': {'id': 'b', 'username': 'bob', 'displayName': 'Bob'},
            'status': 'friend',
            'requestId': 'request',
          },
        ],
        'blocked': [],
      };
    if (method == 'POST' && path == '/api/shared-walks') {
      draft = body as Map<String, dynamic>;
      return create != null ? create!.future : {'id': 'share'};
    }
    if (method == 'GET' && path == '/api/shared-walks')
      return [
        {
          'id': 'share',
          'title': 'Received walk',
          'sender': 'Bob',
          'owned': false,
          'status': 'published',
          'media': [],
          'route': [],
        },
      ];
    if (method == 'GET' && path == '/api/shared-walks/share') {
      return {
        'id': 'share',
        'title': 'Shared story',
        'sender': 'Bob',
        'owned': owned,
        'status': private ? 'private' : unfinished ? 'draft' : 'published',
        'media': unfinished ? (draft?['media'] ?? []) : [],
        'uploadedMediaIds': uploaded,
        'route': [],
        if (supportsAudience)
          'audience': private
              ? 'private'
              : draft?['audience'] ?? 'selectedFriends',
        if (supportsStories) 'stories': draft?['stories'] ?? [],
        'trail': draft?['trail'] ?? [],
      };
    }
    return null;
  }

  @override
  Future<void> transferSharedMedia(
    String method,
    String path, {
    File? upload,
    File? download,
  }) async {
    calls.add('$method $path');
    if (failUpload) throw const LibraryException('Upload failed');
    if (uploadHold != null) await uploadHold!.future;
    if (method == 'PUT') uploaded.add(path.split('/').last);
  }
}

Future<void> compose(WidgetTester tester, SharingLibrary library) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              c,
              MaterialPageRoute<void>(
                builder: (_) => ShareWalkScreen(
                  journey: journey,
                  library: library,
                  store: SharingMemoryStore(),
                  trailStore: SharingTrail(),
                ),
              ),
            ),
            child: const Text('Open sharing'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open sharing'));
  await tester.pumpAndSettle();
}

Future<void> selectAndConfirm(WidgetTester tester) async {
  await tester.tap(find.text('Bob'));
  await tester.tap(find.text('Seafront'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Share with selected friends'), 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
  await tester.tap(find.text('Share with selected friends'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Share'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Signing out during recovery never publishes the draft', (tester) async {
    final library = SharingLibrary()..owned = true..unfinished = true
      ..uploadHold = Completer<void>()
      ..draft = {'media': [{'id': 'missing', 'kind': 'video', 'caption': 'Seafront'}]};
    final store = SharingMemoryStore();
    await store.saveUploadFiles('share', {'missing': memory.id});
    await tester.pumpWidget(MaterialApp(home: RetryShareScreen(id: 'share', library: library, store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retry upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry upload').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    library.logout();
    library.uploadHold!.complete();
    await tester.pumpAndSettle();
    expect(library.calls, isNot(contains('POST /api/shared-walks/share/publish')));
    expect(await store.uploadFiles('share'), {'missing': memory.id});
    expect(find.textContaining('original account'), findsOneWidget);
  });
  testWidgets('Retry uses the existing draft and skips completed files', (tester) async {
    final library = SharingLibrary()..owned = true..unfinished = true
      ..draft = {'media': [
        {'id': 'done', 'kind': 'video', 'caption': 'Already uploaded'},
        {'id': 'missing', 'kind': 'video', 'caption': 'Seafront'},
      ]};
    library.uploaded.add('done');
    final store = SharingMemoryStore();
    await store.saveUploadFiles('share', {'missing': memory.id});
    await tester.pumpWidget(MaterialApp(home: RetryShareScreen(id: 'share', library: library, store: store)));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 memories uploaded'), findsOneWidget);
    expect(library.calls.where((c) => c.startsWith('PUT')), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry upload'));
    await tester.pumpAndSettle();
    expect(library.calls.where((c) => c.startsWith('PUT')), isEmpty);
    await tester.tap(find.text('Retry upload').last);
    await tester.pumpAndSettle();
    expect(library.calls.where((c) => c.startsWith('PUT')), ['PUT /api/shared-walks/share/media/missing']);
    expect(library.calls, contains('POST /api/shared-walks/share/publish'));
    expect(library.calls, isNot(contains('POST /api/shared-walks')));
    expect(await store.uploadFiles('share'), isEmpty);
  });
  testWidgets('Legacy draft requires choosing original files and logout clears recovery', (tester) async {
    final library = SharingLibrary()..owned = true..unfinished = true
      ..draft = {'media': [{'id': 'missing', 'kind': 'video', 'caption': 'Seafront'}]};
    await tester.pumpWidget(MaterialApp(home: RetryShareScreen(id: 'share', library: library, store: SharingMemoryStore())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retry upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry upload').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose an available file'), findsOneWidget);
    expect(library.calls.where((c) => c.startsWith('PUT') || c.endsWith('/publish')), isEmpty);
    library.logout();
    await tester.pumpAndSettle();
    expect(find.text('Seafront'), findsNothing);
    expect(find.textContaining('original account'), findsOneWidget);
  });
  testWidgets('Owned unfinished draft exposes retry and delete actions', (tester) async {
    final library = SharingLibrary()..owned = true..unfinished = true;
    await tester.pumpWidget(MaterialApp(home: SharedWalkScreen(id: 'share', library: library)));
    await tester.pumpAndSettle();
    expect(find.text('Retry upload'), findsOneWidget);
    expect(find.text('Delete unfinished upload'), findsOneWidget);
    await tester.tap(find.text('Delete unfinished upload'));
    await tester.pumpAndSettle();
    expect(library.calls, isNot(contains('DELETE /api/shared-walks/share')));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(library.calls, contains('DELETE /api/shared-walks/share'));
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'Story share conversion preserves narration, notices and source links',
    () {
      final converted = storyShareData(
        AdaptiveRouteStory.fromJson({
          'title': 'Sanremo',
          'anchor': {'latitude': 43, 'longitude': 7},
          'variants': [
            {'length': 'Standard', 'narration': 'A walk through history.'},
          ],
          'sensitivityNotice': 'Historical accounts vary.',
          'sources': [
            {'url': 'https://example.org/history'},
            {'url': 'javascript:no'},
          ],
        }),
      );
      expect(converted['narration'], 'A walk through history.');
      expect(converted['notice'], contains('Historical accounts vary.'));
      expect(converted['sources'], ['https://example.org/history']);
      expect(converted['location'], {'latitude': 43.0, 'longitude': 7.0});
    },
  );
  testWidgets(
    'Sharing from memories resolves the matching saved walk stories',
    (tester) async {
      final library = SharingLibrary()
        ..savedWalks = [
          const LibraryItem(
            id: 'saved',
            name: 'Sanremo',
            revision: 1,
            data: {
              'walk': {'walkSessionId': 'route'},
              'stories': {
                'stories': [
                  {
                    'title': 'Sanremo history',
                    'variants': [
                      {'length': 'Standard', 'narration': 'The saved history.'},
                    ],
                  },
                ],
              },
            },
          ),
        ];
      await compose(tester, library);
      expect(find.text('Sanremo history'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Bob'), 150, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.tap(find.text('Bob'));
      await tester.scrollUntilVisible(find.text('Share with selected friends'), 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.tap(find.text('Share with selected friends'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 stories'), findsOneWidget);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(
        (library.draft!['stories'] as List).single['narration'],
        'The saved history.',
      );
      expect(library.draft!['trail'], isEmpty);
    },
  );
  testWidgets(
    'Actual trail needs separate consent and is cleared when locations are hidden',
    (tester) async {
      final library = SharingLibrary();
      await compose(tester, library);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).last).value,
        isFalse,
      );
      await tester.tap(find.text('Include my actual walked path'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
        isTrue,
      );
      await tester.tap(find.text('Include route and capture locations'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).last).value,
        isFalse,
      );
      await tester.tap(find.text('Include my actual walked path'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Bob'), 150, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.tap(find.text('Bob'));
      await tester.scrollUntilVisible(find.text('Share with selected friends'), 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.tap(find.text('Share with selected friends'));
      await tester.pumpAndSettle();
      expect(find.textContaining('recording times'), findsOneWidget);
      expect(library.draft, isNull);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(library.draft!['includeReplay'], isTrue);
      expect(library.draft!['trail'], hasLength(2));
    },
  );
  testWidgets(
    'Shared replay displays actual recording and sign-out removes it',
    (tester) async {
      final library = SharingLibrary()
        ..draft = {'trail': await SharingTrail().readJourney('route')};
      await tester.pumpWidget(
        MaterialApp(
          home: SharedReplayScreen(shareId: 'share', library: library),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recorded GPS replay'), findsOneWidget);
      expect(find.byTooltip('Play replay'), findsOneWidget);
      library.logout();
      await tester.pumpAndSettle();
      expect(find.text('Recorded GPS replay'), findsNothing);
      expect(
        find.textContaining('sharing access may have changed'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('Locked memories are excluded and privacy survives metadata edits', () {
    final details = memory.details.withSharingLocked(true);
    final restored = MemoryDetails.fromJson(
      details
          .withCaption('New caption')
          .withPlace('Nice')
          .withJourney(journey)
          .toJson(),
    );
    expect(restored.sharingLocked, isTrue);
    final payload = sharedDraft(
      journey,
      'Nice',
      [WalkMemory(memory.file, details: restored)],
      ['b'],
      true,
    );
    expect(payload['media'], isEmpty);
    expect(MemoryDetails.fromJson({}).sharingLocked, isFalse);
  });
  for (final supported in [true, false]) {
    testWidgets(
      'All friends includes future friends only after consent and server support $supported',
      (tester) async {
        final library = SharingLibrary()..supportsAudience = supported;
        await compose(tester, library);
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('All friends').last);
        await tester.pumpAndSettle();
        expect(find.text('Bob'), findsNothing);
        await tester.ensureVisible(find.text('Share with all friends'));
        await tester.tap(find.text('Share with all friends'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('including friends you add later'),
          findsOneWidget,
        );
        expect(library.draft, isNull);
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        expect(library.draft!['audience'], 'allFriends');
        expect(library.draft!['recipients'], isEmpty);
        expect(library.calls.any((c) => c.endsWith('/publish')), supported);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Owner can make a published share private after confirmation', (
    tester,
  ) async {
    final library = SharingLibrary()..owned = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SharedWalkScreen(id: 'share', library: library),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Make private'));
    await tester.pumpAndSettle();
    expect(library.private, isFalse);
    await tester.tap(find.text('Make private'));
    await tester.pumpAndSettle();
    expect(library.private, isTrue);
    expect(find.text('Private - only you'), findsOneWidget);
    expect(find.byTooltip('Make private'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Shared read-aloud stops on background and sign-out', (
    tester,
  ) async {
    const channel = MethodChannel('ai.myrover.rover/voice');
    Completer<void>? speaking;
    var stops = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'ttsSpeak') {
            speaking = Completer<void>();
            return speaking!.future;
          }
          if (call.method == 'ttsStop') {
            stops++;
            if (speaking != null && !speaking!.isCompleted)
              speaking!.complete();
          }
          return;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final library = SharingLibrary()
      ..draft = {
        'stories': [
          {
            'id': 'story',
            'title': 'History of Nice',
            'narration': 'A narrated history.',
            'notice': null,
            'sources': [],
          },
        ],
      };
    await tester.pumpWidget(
      MaterialApp(
        home: SharedWalkScreen(id: 'share', library: library),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Read story aloud'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Stop story'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Read story aloud'));
    await tester.pumpAndSettle();
    library.logout();
    await tester.pumpAndSettle();
    expect(stops, 2);
    expect(find.byTooltip('Stop story'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final supported in [true, false]) {
    testWidgets(
      'Story-only share requires confirmation and server support $supported',
      (tester) async {
        final library = SharingLibrary()..supportsStories = supported;
        await tester.pumpWidget(
          MaterialApp(
            home: ShareWalkScreen(
              library: library,
              store: SharingMemoryStore(),
              stories: const [
                {
                  'title': 'History of Nice',
                  'narration': 'A narrated history.',
                  'notice': 'Some details are uncertain.',
                  'sources': ['https://example.org/source'],
                  'location': {'latitude': 43, 'longitude': 7},
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bob'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Share with selected friends'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share with selected friends'));
        await tester.pumpAndSettle();
        expect(library.draft, isNull);
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        final story = (library.draft!['stories'] as List).single;
        expect(story['location'], isNull);
        expect(story['narration'], 'A narrated history.');
        expect(story['notice'], 'Some details are uncertain.');
        expect(library.draft!['media'], isEmpty);
        expect(library.calls.any((c) => c.endsWith('/publish')), supported);
        if (!supported)
          expect(library.calls, contains('DELETE /api/shared-walks/share'));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'Recipient sees story text, sources and playback control; logout hides it',
    (tester) async {
      final library = SharingLibrary()
        ..draft = {
          'stories': [
            {
              'id': 'story',
              'title': 'History of Nice',
              'narration': 'A narrated history.',
              'notice': 'Historical accounts vary.',
              'sources': ['https://example.org/source'],
            },
          ],
        };
      await tester.pumpWidget(
        MaterialApp(
          home: SharedWalkScreen(id: 'share', library: library),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Read story aloud'), findsOneWidget);
      await tester.tap(find.text('History of Nice'));
      await tester.pumpAndSettle();
      expect(find.text('A narrated history.'), findsOneWidget);
      expect(find.text('https://example.org/source'), findsOneWidget);
      library.logout();
      await tester.pumpAndSettle();
      expect(find.text('History of Nice'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'Shared payload omits locations and local session metadata by default',
    () {
      final payload = sharedDraft(journey, 'Nice', [memory], ['b'], false);
      expect(payload['route'], isEmpty);
      expect(payload['media'][0]['location'], isNull);
      expect(payload.toString(), isNot(contains('Private home')));
      expect(payload.toString(), isNot(contains('walkSessionId')));
      final located = sharedDraft(journey, 'Nice', [memory], ['b'], true);
      expect(located['route'], hasLength(2));
      expect(located['media'][0]['location']['latitude'], 43);
    },
  );
  testWidgets('No uploads before explicit selection and confirmation', (
    tester,
  ) async {
    final library = SharingLibrary();
    await compose(tester, library);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isFalse,
    );
    expect(library.calls.where((c) => c.startsWith('POST')), isEmpty);
    expect(find.text('Video'), findsNothing);
    await tester.tap(find.text('Bob'));
    await tester.tap(find.text('Seafront'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Share with selected friends'), 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Share with selected friends'));
    await tester.pumpAndSettle();
    expect(library.calls.where((c) => c.startsWith('POST')), isEmpty);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(library.draft!['recipients'], ['b']);
    expect(library.draft!['media'], hasLength(1));
    expect(library.calls.last, 'POST /api/shared-walks/share/publish');
    expect(find.text('Open sharing'), findsOneWidget);
  });
  testWidgets('Failed upload never publishes and retains the retryable draft', (
    tester,
  ) async {
    final library = SharingLibrary()..failUpload = true;
    await compose(tester, library);
    await selectAndConfirm(tester);
    expect(library.calls, isNot(contains('DELETE /api/shared-walks/share')));
    expect(library.calls.any((c) => c.endsWith('/publish')), isFalse);
    expect(find.text('Upload failed'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Retry unfinished upload'), 150,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(find.text('Retry unfinished upload'), findsOneWidget);
  });
  testWidgets('Account switch stops sharing before media upload', (
    tester,
  ) async {
    final library = SharingLibrary()..create = Completer<dynamic>();
    await compose(tester, library);
    await tester.tap(find.text('Bob'));
    await tester.tap(find.text('Seafront'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Share with selected friends'), 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('Share with selected friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pump();
    library.logout();
    library.create!.complete({'id': 'share'});
    await tester.pumpAndSettle();
    expect(
      library.calls.any((c) => c.startsWith('PUT') || c.endsWith('/publish')),
      isFalse,
    );
    expect(find.text('Bob'), findsNothing);
  });
  testWidgets('Shared inbox clears on logout', (tester) async {
    final library = SharingLibrary();
    await tester.pumpWidget(
      MaterialApp(home: SharedWalksScreen(library: library)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Received walk'), findsOneWidget);
    library.logout();
    await tester.pumpAndSettle();
    expect(find.text('Received walk'), findsNothing);
  });
  for (final width in [390.0, 844.0]) {
    testWidgets('Sharing layout fits $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await compose(tester, SharingLibrary());
      expect(tester.takeException(), isNull);
    });
  }
}
