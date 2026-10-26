import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/drives/scenic_drive.dart';
import 'package:rover/src/drives/scenic_drive_screen.dart';
import 'package:rover/src/drives/drive_settings.dart';
import 'package:rover/src/location/location_controller.dart';
import 'package:rover/src/location/rover_location.dart';

import 'support/location_fixtures.dart';

import 'package:rover/src/ui/walk_about_theme.dart';

const origin = RoverLatLng(latitude: 43.7, longitude: 7.25);
const destination = DrivePlace(
  id: 'end',
  name: 'Sanremo, Italy',
  address: 'Liguria, Italy',
  attribution: 'Google Maps',
  location: RoverLatLng(latitude: 43.82, longitude: 7.7),
);
DrivePlan fixturePlan({bool back = false, bool fits = true}) => DrivePlan(
  origin: origin,
  destination: destination,
  returnToStart: back,
  stops: const [
    DrivePlace(
      id: 'one',
      name: 'Historic village',
      location: RoverLatLng(latitude: 43.75, longitude: 7.4),
    ),
    DrivePlace(
      id: 'two',
      name: 'Coastal viewpoint',
      location: RoverLatLng(latitude: 43.8, longitude: 7.6),
    ),
  ],
  geometry: [origin, destination.location],
  drivingMinutes: 80,
  distanceMeters: 75000,
  stopMinutes: 45,
  bufferMinutes: 12,
  totalMinutes: 137,
  availableMinutes: fits ? 180 : 60,
  fitsBudget: fits,
  warnings: const ['Traffic, opening hours and parking can change.'],
);

class FakeDrives implements ScenicDriveRepository {
  DriveRequest? last;
  bool fits = true;
  bool fail = false;
  @override
  Future<DriveSearch> search(String query, RoverLatLng origin) async =>
      const DriveSearch([destination], []);
  @override
  Future<DrivePlan> plan(DriveRequest request) async {
    last = request;
    if (fail) throw StateError('Driving directions are unavailable.');
    return fixturePlan(back: request.returnToStart, fits: fits);
  }
}

void main() {
  test(
    'driving URLs preserve destination, ordered stops and optional return',
    () {
      var uri = fixturePlan().directions();
      expect(uri.queryParameters['travelmode'], 'driving');
      expect(uri.queryParameters['destination'], '43.82,7.7');
      expect(uri.queryParameters['waypoints']!.split('|'), hasLength(2));
      uri = fixturePlan(back: true).directions();
      expect(uri.queryParameters['destination'], '43.7,7.25');
      expect(uri.queryParameters['waypoints']!.split('|'), hasLength(3));
      uri = fixturePlan().directions(leg: destination);
      expect(uri.queryParameters.containsKey('origin'), false);
      expect(uri.queryParameters.containsKey('waypoints'), false);
      expect(uri.queryParameters['dir_action'], 'navigate');
    },
  );
  test('request only sends selected identity and selected budget', () {
    final json = const DriveRequest(
      origin: origin,
      destination: destination,
      query: 'Sanremo',
      returnToStart: true,
      availableMinutes: 180,
      minutesPerStop: 15,
      interests: ['Nature'],
    ).toJson();
    expect(json['destination'], {
      'query': 'Sanremo',
      'placeId': 'end',
      'isDestination': true,
    });
    expect(json['returnToStart'], true);
    expect(json['minutesPerStop'], 15);
    expect(json['maxOptionalStops'], 6);
  });
  for (final width in [320.0, 720.0]) {
    testWidgets('destination selection, budget and navigation at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeDrives();
      final location = LocationController(
        realProvider: SimulatedLocationProvider(route: const [origin]),
      );
      addTearDown(location.dispose);
      var allowed = false;
      var launched = 0;
      var stories = 0;
      final capture = Platform.environment['CAPTURE_SCENIC_DRIVE'] == '1';
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
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: walkAboutTheme(Brightness.light),
            debugShowCheckedModeBanner: false,
            home: ScenicDriveScreen(
              settingsStore: MemoryDriveSettingsStore(),
              repository: repo,
              location: location,
              beforeNavigate: () async => allowed,
              tellHere: () => stories++,
              launchDirections: (_) async {
                launched++;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sanremo');
      await tester.tap(find.text('Find destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sanremo, Italy'));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Plan drive'));
      await tester.tap(find.text('Plan drive'));
      await tester.pumpAndSettle();
      expect(repo.last?.returnToStart, true);
      expect(repo.last?.destination.id, 'end');
      expect(repo.last?.availableMinutes, 180);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Open driving directions'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open driving directions'));
      await tester.pumpAndSettle();
      expect(launched, 0);
      allowed = true;
      await tester.tap(find.text('Open driving directions'));
      await tester.pumpAndSettle();
      expect(launched, 1);
      await tester.ensureVisible(find.text('Tell me about here'));
      await tester.tap(find.text('Tell me about here'));
      await tester.pumpAndSettle();
      expect(stories, 0);
      await tester.tap(find.text('I am parked'));
      await tester.pumpAndSettle();
      expect(stories, 1);
      if (capture) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/walk_about_screenshots/scenic-drive-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      // A changed budget must invalidate the previous itinerary and navigation.
      await tester.scrollUntilVisible(
        find.byType(SwitchListTile),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('Open driving directions'), findsNothing);
      repo.fits = false;
      await tester.ensureVisible(find.text('Plan drive'));
      await tester.tap(find.text('Plan drive'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Open driving directions'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Open driving directions'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
    'search changes clear selection; failed planning stays retryable',
    (tester) async {
      final repo = FakeDrives()..fail = true;
      final location = LocationController(
        realProvider: SimulatedLocationProvider(route: const [origin]),
      );
      addTearDown(location.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ScenicDriveScreen(
            settingsStore: MemoryDriveSettingsStore(),
            repository: repo,
            location: location,
            beforeNavigate: () async => false,
            tellHere: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sanremo');
      await tester.tap(find.text('Find destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sanremo, Italy'));
      await tester.scrollUntilVisible(
        find.text('Plan drive'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Plan drive'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Driving directions are unavailable.'),
      );
      expect(find.text('Driving directions are unavailable.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Plan drive'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'Monaco');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Plan drive'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Plan drive'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
