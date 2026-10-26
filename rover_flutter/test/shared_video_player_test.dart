import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:rover/src/sharing/shared_video_player.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      'Shared video controls remain visible above navigation at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final player = VideoPlayerController.file(File('fixture.mp4'));
        player.value = const VideoPlayerValue(
          duration: Duration(seconds: 20),
          size: Size(1920, 1080),
        );
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: const EdgeInsets.only(bottom: 80),
              ),
              child: Scaffold(
                appBar: AppBar(title: const Text('Shared memory')),
                body: SharedVideoPlayer(
                  controller: player,
                  enabled: true,
                  onToggle: () {
                    taps++;
                    player.value = player.value.copyWith(
                      isPlaying: !player.value.isPlaying,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.byTooltip('Play video'), findsOneWidget);
        expect(
          tester.getBottomLeft(find.byTooltip('Play')).dy,
          lessThanOrEqualTo(size.height - 80),
        );
        await tester.tap(find.byTooltip('Play video'));
        await tester.pump();
        expect(taps, 1);
        expect(find.byTooltip('Pause'), findsOneWidget);
        expect(find.text('0:00 / 0:20'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await player.dispose();
      },
    );
  }
}
