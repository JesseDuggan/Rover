import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/app.dart';
import 'package:rover/src/api/walk_models.dart';
import 'package:rover/src/api/walk_place_models.dart';
import 'package:rover/src/api/adaptation_models.dart';
import 'package:rover/src/active_roam/active_roam_repository.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/preferences/rover_preferences.dart';
import 'package:rover/src/ui/walk_about_screens.dart';

import 'api_walk_test.dart' show FakeWalkRepository;
import 'support/location_fixtures.dart';
import 'support/route_fixtures.dart';

class RecordingWalkRepository extends FakeWalkRepository
    implements WalkPlaceRepository {
  CreateWalkRequest? request;
  WalkAdaptationEvaluateRequest? adaptation;
  bool emptySearch = false;
  @override
  Future<WalkPlaceSearchResult> searchWalkPlaces({
    required String query,
    required double latitude,
    required double longitude,
  }) async => WalkPlaceSearchResult(
    emptySearch
        ? []
        : const [
            WalkPlaceOption(
              placeId: 'hotel-1',
              name: 'Vocal Hotel',
              address: 'First address',
              attribution: 'Test Maps',
            ),
            WalkPlaceOption(
              placeId: 'hotel-2',
              name: 'Vocal Hotel Riverside',
              address: 'Second address',
              attribution: 'Test Maps',
            ),
          ],
    [],
  );
  @override
  Future<WalkAdaptationProposal> evaluateAdaptation(
    String walkSessionId,
    WalkAdaptationEvaluateRequest request,
  ) {
    adaptation = request;
    return super.evaluateAdaptation(walkSessionId, request);
  }

  bool fail = false;
  @override
  Future<WalkSession> createWalk(CreateWalkRequest request) {
    this.request = request;
    if (fail) return Future.error(Exception('Offline'));
    return super.createWalk(request);
  }
}

void main() {
  for (final mode in ['Add stop', 'End here']) {
    testWidgets(
      '$mode selects an explicit place and preserves profile interests',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = MemoryPreferencesRepository();
        await preferences.save(const RoverPreferences(interests: ['history']));
        final api = RecordingWalkRepository();
        await tester.pumpWidget(
          RoverTestApp(
            preferencesRepository: preferences,
            walkRepository: api,
            locationProvider: SimulatedLocationProvider(),
            initialLocation: '/home',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(mode));
        await tester.enterText(find.byType(TextField), 'Vocal Hotel');
        tester.testTextInput.hide();
        await tester.tap(find.widgetWithIcon(TextButton, Icons.search));
        await tester.pumpAndSettle();
        expect(api.request, isNull);
        await tester.ensureVisible(find.text('Vocal Hotel Riverside'));
        await tester.tap(find.text('Vocal Hotel Riverside'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Create my walk'));
        await tester.tap(find.text('Create my walk'));
        await tester.pumpAndSettle();
        expect(api.request!.selectedPlace!.placeId, 'hotel-2');
        expect(api.request!.selectedPlace!.isDestination, mode == 'End here');
        expect(api.request!.interests, ['history']);
        expect(find.byType(WalkPreviewScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final accept in [false, true]) {
    testWidgets('add stop to active walk requires confirmation: $accept', (
      tester,
    ) async {
      final api = RecordingWalkRepository();
      await tester.pumpWidget(
        RoverTestApp(
          preferencesRepository: MemoryPreferencesRepository(),
          activeRoamRepository: MemoryActiveRoamRepository(
            demoSession().copyWith(
              apiWalkSessionId: 'walk-live',
              status: RoamSessionStatus.active,
            ),
          ),
          walkRepository: api,
          locationProvider: SimulatedLocationProvider(),
          initialLocation: '/plan',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a stop or destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add stop'));
      await tester.enterText(find.byType(TextField), 'Hotel');
      await tester.tap(find.widgetWithIcon(TextButton, Icons.search));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Vocal Hotel'));
      await tester.tap(find.text('Vocal Hotel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review route change'));
      await tester.tap(find.text('Review route change'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(api.calls, isNot(contains('cancelWalk')));
      expect(api.calls, isNot(contains('createWalk')));
      expect(api.calls, isNot(contains('acceptAdaptation:adapt-1')));
      expect(api.adaptation!.selectedPlace!.placeId, 'hotel-1');
      await tester.tap(
        find.text(accept ? 'Apply route' : 'Keep current route'),
      );
      await tester.pumpAndSettle();
      expect(
        api.calls,
        contains(
          accept ? 'acceptAdaptation:adapt-1' : 'rejectAdaptation:adapt-1',
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('no match cannot silently create a walk', (tester) async {
    final api = RecordingWalkRepository()..emptySearch = true;
    await tester.pumpWidget(
      RoverTestApp(
        preferencesRepository: MemoryPreferencesRepository(),
        walkRepository: api,
        locationProvider: SimulatedLocationProvider(),
        initialLocation: '/home',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('End here'));
    await tester.enterText(find.byType(TextField), 'Unknown hotel');
    await tester.tap(find.widgetWithIcon(TextButton, Icons.search));
    await tester.pumpAndSettle();
    expect(
      find.text('No matching places nearby. Try the full name and town.'),
      findsOneWidget,
    );
    expect(api.request, isNull);
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('phone ${width.toInt()}: profile, create then start', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = MemoryPreferencesRepository();
      final api = RecordingWalkRepository();
      await tester.pumpWidget(
        RoverTestApp(
          preferencesRepository: preferences,
          walkRepository: api,
          locationProvider: SimulatedLocationProvider(),
          initialLocation: '/home',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'History'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Architecture'));
      await tester.pumpAndSettle();
      expect(
        (await preferences.load()).interests,
        containsAll(['history', 'architecture']),
      );
      await tester.tap(find.text('Walk'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Old buildings and a quiet coffee',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create my walk'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'createWalk'), hasLength(1));
      expect(api.calls, isNot(contains('startWalk')));
      expect(api.request!.naturalRequest, 'Old buildings and a quiet coffee');
      expect(api.request!.companions, 'Solo');
      expect(api.request!.interests, containsAll(['history', 'architecture']));
      expect(find.byType(WalkPreviewScreen), findsOneWidget);
      expect(find.text('Start walking'), findsOneWidget);
      expect(find.byTooltip('Save walk'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Start walking'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(api.calls.where((c) => c == 'startWalk'), hasLength(1));
      expect(find.byTooltip('Save walk'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('failed generation stays home and retains request', (
    tester,
  ) async {
    final api = RecordingWalkRepository()..fail = true;
    await tester.pumpWidget(
      RoverTestApp(
        preferencesRepository: MemoryPreferencesRepository(),
        walkRepository: api,
        locationProvider: SimulatedLocationProvider(),
        initialLocation: '/home',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A quiet walk');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(find.text('Create my walk'), 250,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Create my walk'));
    await tester.pumpAndSettle();
    expect(find.byType(WalkPreviewScreen), findsNothing);
    await tester.scrollUntilVisible(find.byType(TextField), -250,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('A quiet walk'), findsOneWidget);
    expect(api.calls, isNot(contains('startWalk')));
  });

  testWidgets('Scenic Drive opens without starting or replacing a walk', (tester) async {
    final api = RecordingWalkRepository();
    await tester.pumpWidget(RoverTestApp(
      preferencesRepository: MemoryPreferencesRepository(),
      walkRepository: api,
      locationProvider: SimulatedLocationProvider(),
      initialLocation: '/home',
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scenic Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
    expect(api.calls, isNot(contains('startWalk')));
    expect(api.request, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Create your walk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('new profile fields round trip without losing existing preferences', () {
    const source = RoverPreferences(
      firstName: 'Jesse',
      interests: ['art', 'history'],
      mobility: 'Avoid stairs',
      includePaidAttractions: true,
    );
    final loaded = RoverPreferences.fromJson(source.toJson());
    expect(loaded.includePaidAttractions, isTrue);
    expect(loaded.interests, source.interests);
    expect(loaded.mobility, source.mobility);
    expect(RoverPreferences.fromMap({}).includePaidAttractions, isFalse);
  });
}
