import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/app.dart';
import 'package:rover/src/preferences/preferences_repository.dart';

import 'support/location_fixtures.dart';
import 'walk_about_flow_test.dart' show RecordingWalkRepository;

void main() {
  for (final width in [320.0, 390.0, 720.0]) {
    testWidgets('place selection layout and invalidation at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = Platform.environment['CAPTURE_WALKABOUT_PLACES'] == '1';
      if (capture) {
        await tester.runAsync(() async {
          final font = FontLoader('Inter')
            ..addFont(
              File('assets/fonts/Inter-Regular.ttf')
                  .readAsBytes()
                  .then(ByteData.sublistView),
            );
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      final boundaryKey = GlobalKey();
      final api = RecordingWalkRepository();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: RoverTestApp(
            preferencesRepository: MemoryPreferencesRepository(),
            walkRepository: api,
            locationProvider: SimulatedLocationProvider(),
            initialLocation: '/home',
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (capture) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/brand/walkabout-logo.png'),
            tester.element(find.byType(Scaffold).first),
          ),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('End here'));
      await tester.enterText(find.byType(TextField), 'Vocal Hotel');
      tester.testTextInput.hide();
      await tester.tap(find.widgetWithIcon(TextButton, Icons.search));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vocal Hotel Riverside'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (capture) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/walk_about_screenshots/selected-place-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.enterText(find.byType(TextField), 'Another hotel');
      await tester.pumpAndSettle();
      expect(find.text('Vocal Hotel Riverside'), findsNothing);
      expect(find.text('Create my walk'), findsNothing);
      expect(api.request, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
