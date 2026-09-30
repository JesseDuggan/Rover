import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/location_observation_models.dart';
import 'package:rover/src/api/problem_details.dart';
import 'package:rover/src/camera_explorer/identification_photo.dart';
import 'package:rover/src/camera_explorer/photo_identification_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1sAAAAASUVORK5CYII=',
  );
  final candidate = LocationObservationCandidate.fromJson({
    'place': {
      'canonicalId': 'test:1',
      'name': 'Test monument',
      'address': 'Munich',
    },
  });
  final result = LocationObservationResolution(
    status: LocationObservationResolutionStatus.ambiguous,
    candidates: [candidate],
    diagnosticCode: 'photo_confirmation_required',
    warnings: [],
  );

  test('photo preparation strips to bounded PNG pixels', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2000, 1000);
    final original = await image.toByteData(format: ui.ImageByteFormat.png);
    final prepared = await prepareIdentificationPhoto(
      original!.buffer.asUint8List(),
    );
    final codec = await ui.instantiateImageCodec(prepared);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1024);
    expect(frame.image.height, 512);
    expect(prepared.length, lessThanOrEqualTo(2 * 1024 * 1024));
    frame.image.dispose();
    codec.dispose();
    image.dispose();
    picture.dispose();
    await expectLater(
      prepareIdentificationPhoto(base64Decode('AAAA')),
      throwsA(anything),
    );
  });

  testWidgets(
    'no upload before consent and dismissal preserves camera background',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('Nearby business overlay'),
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => PhotoIdentificationSheet(
                        photo: photo,
                        identify: () async {
                          calls++;
                          return result;
                        },
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Nearby business overlay'), findsOneWidget);
    },
  );

  testWidgets('candidate requires explicit confirmation', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoIdentificationSheet(
            photo: photo,
            identify: () async {
              calls++;
              return result;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Send and identify'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.text('Test monument'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm place'), findsOneWidget);
    await tester.tap(find.text('Not this one'));
    await tester.pumpAndSettle();
    expect(find.text('Test monument'), findsOneWidget);
  });

  testWidgets('quota failure is recoverable without a false match', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoIdentificationSheet(
            photo: photo,
            identify: () async =>
                throw const RoverApiException('quota', statusCode: 429),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Send and identify'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Photo limit reached'), findsOneWidget);
    expect(find.text('Confirm place'), findsNothing);
  });
}
