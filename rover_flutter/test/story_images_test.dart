import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/just_walking/story_images.dart';

void main() {
  final picture = <String, dynamic>{
    'url': 'https://upload.wikimedia.org/view.jpg',
    'caption': 'Historic view',
    'attribution': 'Photographer',
    'license': 'CC BY-SA 4.0',
    'licenseUrl': 'https://creativecommons.org/licenses/by-sa/4.0/',
    'sourceUrl': 'https://commons.wikimedia.org/wiki/File:View.jpg',
  };
  test('Only trusted picture and credit URLs are accepted', () {
    expect(StoryPicture.parse(picture), isNotNull);
    expect(
      StoryPicture.parse({...picture, 'url': 'http://localhost/private'}),
      isNull,
    );
    expect(
      StoryPicture.parse({...picture, 'sourceUrl': 'javascript:alert(1)'}),
      isNull,
    );
    expect(StoryPicture.parse({...picture, 'attribution': ''}), isNull);
  });
  final archive = <String, dynamic>{
    ...picture,
    'provider': 'Europeana',
    'isArchive': true,
    'url': 'https://api.europeana.eu/thumbnail/v3/400/820911931db3ccb20e1b7a022ee6dd33.jpg',
    'sourceUrl': 'https://www.europeana.eu/item/123/view_1',
    'articleUrl': 'https://www.europeana.eu/item/123/view_1',
    'caption': 'Laan van Meerdervoort (1910)',
    'attribution': 'Photographer - City Archive',
  };
  test('Europeana thumbnails require matching provenance and open rights', () {
    final parsed = StoryPicture.parse(archive);
    expect(parsed?.provider, 'Europeana');
    expect(parsed?.kindLabel, 'Archive material');
    expect(
      supportedPictureSource('https://www.europeana.eu/en/item/123/view_1'),
      isTrue,
    );
    expect(
      supportedPictureSource(
        'https://www.europeana.eu.evil.org/item/123/view_1',
      ),
      isFalse,
    );
    expect(
      StoryPicture.parse({...archive, 'isNearby': true})?.kindLabel,
      'Nearby archive material',
    );
    for (final change in <Map<String, dynamic>>[
      {'url': 'https://api.europeana.eu/record/v2/search.json?wskey=secret'},
      {
        'url': 'https://api.europeana.eu.evil.org/thumbnail/v3/400/820911931db3ccb20e1b7a022ee6dd33.jpg',
      },
      {
        'url': 'https://api.europeana.eu/thumbnail/v3/400/820911931db3ccb20e1b7a022ee6dd33.jpg?wskey=secret',
      },
      {'url': 'https://museum.example.org/image.jpg'},
      {'sourceUrl': 'https://www.europeana.eu/account'},
      {'provider': 'Wikimedia Commons'},
      {'isArchive': false},
      {'licenseUrl': 'https://creativecommons.org/licenses/by-nc/4.0/'},
      {'attribution': ''},
    ]) {
      expect(
        StoryPicture.parse({...archive, ...change}),
        isNull,
        reason: '$change',
      );
    }
    const legacy =
        'https://api.europeana.eu/thumbnail/v2/url.json?uri=https%3A%2F%2Farchive.example.org%2Fview.jpg&size=w400&type=IMAGE';
    expect(StoryPicture.parse({...archive, 'url': legacy}), isNotNull);
    expect(
      StoryPicture.parse({...archive, 'url': '$legacy&wskey=secret'}),
      isNull,
    );
  });
  test(
    'Picture sources accept entity and Commons links, not arbitrary hosts',
    () {
      expect(
        supportedPictureSource('https://www.wikidata.org/entity/Q2742215'),
        isTrue,
      );
      expect(
        supportedPictureSource(
          'https://commons.wikimedia.org/wiki/File:View.jpg',
        ),
        isTrue,
      );
      expect(
        supportedPictureSource(
          'https://en.wikipedia.org/wiki/Laan_van_Meerdervoort',
        ),
        isTrue,
      );
      expect(supportedPictureSource('https://evil.org/wiki/Test'), isFalse);
      expect(
        supportedPictureSource('https://en.wikipedia.org:444/wiki/Test'),
        isFalse,
      );
    },
  );
  for (final width in [320.0, 390.0, 720.0]) {
    testWidgets('Archive viewer keeps labels and attribution at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: const TextScaler.linear(1.5),
                ),
                child: StoryImages(
                  sourceUrls: const [
                    'https://www.europeana.eu/item/123/view_1',
                  ],
                  loader: (_) async => {
                    'status': 'ready',
                    'images': [archive],
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 1 - Archive material'), findsOneWidget);
      expect(find.text('Europeana'), findsOneWidget);
      expect(find.text('Wikimedia Commons'), findsNothing);
      await tester.tap(
        find.bySemanticsLabel(
          'Enlarge picture 1: Laan van Meerdervoort (1910)',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archive material').hitTestable(), findsOneWidget);
      expect(
        find.text('Photographer - City Archive').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('About this place'), findsNothing);
      expect(find.text('CC BY-SA 4.0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Carousel opens clicked image with credits at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: const TextScaler.linear(1.5),
              ),
              child: SingleChildScrollView(
                child: StoryImages(
                  sourceUrls: const ['source'],
                  loader: (_) async => {
                    'images': [
                      picture,
                      {
                        ...picture,
                        'url': 'https://upload.wikimedia.org/second.jpg',
                        'caption': 'Second view',
                        'attribution': 'Second photographer',
                        'isNearby': true,
                      },
                    ],
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(find.text('Second photographer'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Enlarge picture 2: Second view'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Nearby place illustration'), findsOneWidget);
      expect(find.text('Second photographer').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Previous picture').last);
      await tester.pumpAndSettle();
      expect(find.text('Photographer').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Empty and unavailable images do not block story UI', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryImages(
            sourceUrls: const ['https://en.wikipedia.org/wiki/Test'],
            loader: (_) async {
              count++;
              return {
                'status': count == 1 ? 'unavailable' : 'empty',
                'images': [],
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pictures unavailable right now.'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry pictures'));
    await tester.pumpAndSettle();
    expect(
      find.text('No sourced picture available for this story.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Late requests cannot replace a new story or update disposed views',
    (tester) async {
      final old = Completer<Map<String, dynamic>>();
      Widget view(String source) => MaterialApp(
        home: Scaffold(
          body: StoryImages(
            sourceUrls: [source],
            loader: (sources) => sources.first == 'old'
                ? old.future
                : Future.value({'status': 'empty', 'images': []}),
          ),
        ),
      );
      await tester.pumpWidget(view('old'));
      await tester.pumpWidget(view('new'));
      await tester.pumpAndSettle();
      old.complete({
        'status': 'ready',
        'images': [picture],
      });
      await tester.pumpAndSettle();
      expect(find.text('Historic view'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Phone view shows credits and opens a zoomable picture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoryImages(
              sourceUrls: const ['source'],
              loader: (_) async => {
                'status': 'ready',
                'images': [picture],
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Photographer'), findsOneWidget);
    expect(find.text('CC BY-SA 4.0'), findsOneWidget);
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Story picture'), findsOneWidget);
    await tester.tap(find.byTooltip('Close picture'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Story picture'), findsNothing);
    expect(find.byType(StoryImages), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
