import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/app.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/preferences/rover_preferences.dart';

import 'api_walk_test.dart' show FakeWalkRepository;
import 'support/location_fixtures.dart';

// Optional local visual evidence. Preview uses a repository fixture, never a
// production fallback. Native map tiles require the Android integration run.
void main() {
  testWidgets('capture Walk About phone screens', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    const voice = MethodChannel('ai.myrover.rover/voice');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      voice,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        voice,
        null,
      ),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': 'C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
        'Georgia': 'C:/Windows/Fonts/georgia.ttf',
        'MaterialIcons': 'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key);
        loader.addFont(
          File(entry.value)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      }
    });
    final preferences = MemoryPreferencesRepository();
    await preferences.save(
      const RoverPreferences(
        firstName: 'Jesse',
        interests: ['history', 'architecture'],
        completedOnboarding: true,
      ),
    );
    final key = GlobalKey();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/walk_about_screenshots/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: RoverTestApp(
          preferencesRepository: preferences,
          walkRepository: FakeWalkRepository(),
          locationProvider: SimulatedLocationProvider(),
          initialLocation: '/home',
        ),
      ),
    );
    await capture('home');
    await tester.ensureVisible(find.text('Just walking'));
    await tester.tap(find.text('Just walking'));
    await capture('just-walking');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fine tune this walk'));
    await tester.tap(find.text('Fine tune this walk'));
    await capture('fine-tune');
    await tester.tap(find.text('Profile'));
    await capture('profile');
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create my walk'));
    await capture('preview-fixture');
  }, skip: Platform.environment['CAPTURE_WALK_ABOUT'] != '1');
}
