import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/preferences/preferences_controller.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/preferences/rover_preferences.dart';
import 'package:rover/src/ui/walk_about_screens.dart';
import 'package:rover/src/ui/walk_about_theme.dart';

void expectNavyLabel(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  expect(paragraph.text.style?.color, WalkaboutColors.navy, reason: text);
  expect(paragraph.text.style?.fontSize, 16, reason: text);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('chip contrast survives selection and $brightness', (
      tester,
    ) async {
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: walkAboutTheme(brightness),
          home: Scaffold(
            body: DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: StatefulBuilder(
                builder: (context, setState) => Wrap(
                  children: [
                    FilterChip(
                      label: const Text('History'),
                      selected: selected,
                      onSelected: (v) => setState(() => selected = v),
                    ),
                    ChoiceChip(
                      label: const Text('Easy'),
                      selected: selected,
                      onSelected: (v) => setState(() => selected = v),
                    ),
                    ActionChip(label: const Text('Custom'), onPressed: () {}),
                    const Chip(label: Text('11 stops')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['History', 'Easy', 'Custom', '11 stops']) {
        expectNavyLabel(tester, label);
      }
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expectNavyLabel(tester, 'History');
      expectNavyLabel(tester, 'Easy');
      await tester.tap(find.text('Easy'));
      await tester.pumpAndSettle();
      expect(selected, isFalse);
      expectNavyLabel(tester, 'Easy');
    });
  }

  for (final width in [390.0, 720.0]) {
    testWidgets('profile contrast at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = PreferencesController(MemoryPreferencesRepository());
      addTearDown(preferences.dispose);
      await preferences.load();
      await preferences.save(
        const RoverPreferences(
          firstName: 'Jesse',
          walkingPace: 'easy',
          interests: [
            'history',
            'hidden gems',
            'culture',
            'notable people',
            'unusual facts',
          ],
        ),
      );
      final capture = Platform.environment['CAPTURE_WALKABOUT_CONTRAST'] == '1';
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
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PreferencesScope(
            controller: preferences,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: walkAboutTheme(Brightness.light),
              home: const WalkProfileScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'History',
        'Architecture',
        'Hidden gems',
        'Culture',
      ]) {
        expectNavyLabel(tester, label);
      }
      await tester.ensureVisible(find.text('Your usual pace'));
      await tester.pumpAndSettle();
      for (final label in ['Easy', 'Steady', 'Brisk']) {
        expectNavyLabel(tester, label);
      }
      expect(tester.takeException(), isNull);
      if (capture) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/walk_about_screenshots/profile-contrast-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  test('chip foreground has strong contrast on both backgrounds', () {
    final theme = walkAboutTheme(Brightness.light).chipTheme;
    final foreground = theme.labelStyle!.color!;
    for (final background in [Colors.white, theme.selectedColor!]) {
      final ratio =
          (background.computeLuminance() + .05) /
          (foreground.computeLuminance() + .05);
      expect(ratio, greaterThanOrEqualTo(7));
    }
  });
}
