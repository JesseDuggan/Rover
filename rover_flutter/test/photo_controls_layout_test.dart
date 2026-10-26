import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/adventure/roam.dart';
import 'package:rover/src/just_walking/story_images.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/ui/walk_about_theme.dart';
import 'package:rover/src/voice/rover_voice_controller.dart';
import 'package:rover/src/voice/rover_voice_state.dart';
import 'package:rover/src/voice/stop_narration_controls.dart';

import 'voice_controller_test.dart'
    show
        FakeTextToSpeech,
        FakeVoiceWalkRepository,
        FakeSpeechRecognizer,
        FakeAudioSession;

class _ControlledSpeech extends FakeTextToSpeech {
  Completer<void>? pending;
  @override
  Future<void> speak(String text) {
    spoken.add(text);
    pending = Completer<void>();
    return pending!.future;
  }

  void complete() {
    if (pending?.isCompleted == false) pending!.complete();
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    complete();
  }

  @override
  Future<void> stop() async {
    stopCount++;
    complete();
  }
}

void main() {
  const stop = RoverStop(
    id: 'test',
    name: 'Museum',
    image: 'api://test',
    shortDescription: 'A museum on this walk.',
    estimatedVisitMinutes: 5,
    coordinates: RoverLatLng(latitude: 52, longitude: 4),
    category: 'History',
    whySelected: 'History',
    narration: 'The museum story.',
  );
  const picture = StoryPicture(
    url: 'https://upload.wikimedia.org/test-fixture.png',
    caption: 'Local image fixture',
    attribution: 'Walkabout test fixture',
    license: 'CC BY-SA 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Fixture.png',
  );
  const archive = StoryPicture(
    url: 'https://api.europeana.eu/thumbnail/v3/400/820911931db3ccb20e1b7a022ee6dd33.jpg',
    caption: 'Archive layout fixture (1910)',
    attribution: 'Example photographer - Example city archive',
    license: 'CC BY-SA 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    sourceUrl: 'https://www.europeana.eu/item/123/fixture',
    provider: 'Europeana',
    isArchive: true,
  );

  for (final width in [320.0, 390.0, 720.0]) {
    testWidgets('Stop playback controls and loaded carousel layout at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final speech = _ControlledSpeech();
      final voice = RoverVoiceController(
        walkRepository: FakeVoiceWalkRepository(),
        textToSpeech: speech,
        speechRecognizer: FakeSpeechRecognizer(),
        audioSession: FakeAudioSession(),
      );
      addTearDown(voice.dispose);
      final capture = Platform.environment['CAPTURE_WALKABOUT_PHOTOS'] == '1';
      await tester.runAsync(() async {
        if (capture) {
          await (FontLoader(
            'Inter',
          )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        // Local bitmap fixture avoids network dependencies; never used by production.
        final bytes = await rootBundle.load('assets/brand/walkabout-logo.png');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        PaintingBinding.instance.imageCache.putIfAbsent(
          NetworkImage(picture.url),
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame.image)),
          ),
        );
        PaintingBinding.instance.imageCache.putIfAbsent(
          NetworkImage(archive.url),
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame.image.clone())),
          ),
        );
        codec.dispose();
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: walkAboutTheme(Brightness.light),
            home: Scaffold(
              appBar: AppBar(title: const Text('Stop details')),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Museum',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    StopNarrationControls(stop: stop, voice: voice),
                    const SizedBox(height: 24),
                    const PictureCarousel(pictures: [picture, archive]),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play stop information'));
      await tester.pumpAndSettle();
      expect(voice.state, RoverAudioState.speakingNarration);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(voice.state, RoverAudioState.narrationPaused);
      expect(find.text('Resume'), findsOneWidget);
      if (capture) {
        await _capture(tester, boundaryKey, 'stop-photos-${width.toInt()}');
      }
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(voice.state, RoverAudioState.speakingNarration);
      await tester.tap(find.byTooltip('Stop stop information'));
      await tester.pumpAndSettle();
      expect(voice.state, RoverAudioState.idle);
      expect(find.text('Play stop information'), findsOneWidget);
      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      if (capture) {
        await _capture(tester, boundaryKey, 'picture-viewer-${width.toInt()}');
      }
      await tester.tap(find.byTooltip('Next picture').last);
      await tester.pumpAndSettle();
      expect(find.text('Archive material').hitTestable(), findsOneWidget);
      expect(find.text('Europeana').hitTestable(), findsOneWidget);
      if (capture) {
        await _capture(tester, boundaryKey, 'archive-viewer-${width.toInt()}');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
    });
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/walk_about_screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
