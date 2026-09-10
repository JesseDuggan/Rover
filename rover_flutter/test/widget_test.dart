import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rover/src/active_roam/active_roam_repository.dart';
import 'package:rover/src/adaptive_stories/route_story_question_dialog.dart';
import 'package:rover/src/app.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/preferences/preferences_repository.dart';

void main() {
  testWidgets('route question closes safely through its exit animation', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => OutlinedButton(
              onPressed: () async {
                submitted = await showRouteStoryQuestionDialog(context);
              },
              child: const Text('Ask about route'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ask = find.widgetWithText(OutlinedButton, 'Ask about route');
    await tester.ensureVisible(ask);
    await tester.tap(ask);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'what happens here');
    await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Ask about this route'), findsNothing);
    expect(submitted, 'what happens here');
    expect(tester.takeException(), isNull);
  });

  final routeExpectations = <String, String>{
    '/welcome': 'You bring the time. ROVER creates the adventure.',
    '/onboarding': 'What should Riley call you?',
    '/home': 'What do you want to do?',
    '/home/adventure-request': 'Start casual. Riley will build the walk from your current device location.',
    '/home/route-preview':
        'Riley needs an adventure request before making suggestions.',
    '/home/active-roam':
        'Create a live walk from your current location to start navigation.',
    '/home/stop-details':
        'A friendly placeholder for why this stop belongs in the adventure.',
    '/roams': 'Saved placeholder adventures live here.',
    '/profile': 'Set up Riley so future ROAMs feel more like you.',
    '/profile/settings': 'Riley keeps these on this device for now. No account or backend is connected.',
    '/profile/on-device-ai': 'On-device AI',
  };

  for (final entry in routeExpectations.entries) {
    testWidgets('renders ${entry.key}', (tester) async {
      await tester.pumpWidget(_app(initialLocation: entry.key));
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsOneWidget);
    });
  }

  testWidgets('welcome route starts onboarding and supports guest mode', (
    tester,
  ) async {
    final repository = MemoryPreferencesRepository();
    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('What should Riley call you?'), findsOneWidget);

    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Continue as Guest'));
    await tester.pumpAndSettle();

    expect(find.text('What do you want to do?'), findsOneWidget);
    expect((await repository.load()).continueAsGuest, isTrue);
  });

  testWidgets('onboarding saves preferences and they persist after restart', (
    tester,
  ) async {
    final repository = MemoryPreferencesRepository();
    await tester.pumpWidget(
      _app(repository: repository, initialLocation: '/onboarding'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Jesse');
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('food'));
    await tester.tap(find.text('hidden gems'));
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('steady'));
    await tester.tap(find.text('90 minutes'));
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Prefer step-free stops',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('deeper stories'));
    await tester.tap(find.text('prefer audio'));
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('helpful nudges'));
    await tester.tap(find.text('miles'));
    await tester.tap(find.text('English'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save preferences'));
    await tester.pumpAndSettle();

    expect(find.text('Jesse'), findsOneWidget);
    expect(find.text('food, hidden gems'), findsOneWidget);
    expect(find.text('Prefer step-free stops'), findsOneWidget);

    await tester.pumpWidget(
      _app(repository: repository, initialLocation: '/profile/settings'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jesse'), findsOneWidget);
    expect((await repository.load()).completedOnboarding, isTrue);
  });

  testWidgets('preferences can be reviewed, edited, and reset', (tester) async {
    final repository = MemoryPreferencesRepository();
    await tester.pumpWidget(
      _app(repository: repository, initialLocation: '/profile/settings'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Skipped for now'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Edit preferences'));
    await tester.pumpAndSettle();
    expect(find.text('What should Riley call you?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reset onboarding'));
    await tester.pumpAndSettle();

    expect(find.text('ROVER'), findsOneWidget);
    expect((await repository.load()).completedOnboarding, isFalse);
  });

  testWidgets('every primary destination is reachable from the shell', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/home'));
    await tester.pumpAndSettle();

    expect(find.text('What do you want to do?'), findsOneWidget);

    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    expect(
      find.text('Browse sample ideas for future ROVER adventures.'),
      findsOneWidget,
    );

    await tester.tap(find.text('My ROAMs'));
    await tester.pumpAndSettle();
    expect(
      find.text('Saved placeholder adventures live here.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(
      find.text('Set up Riley so future ROAMs feel more like you.'),
      findsOneWidget,
    );
  });

  testWidgets('detail routes are reachable and Android back pops them', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Build an adventure request'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Start casual. Riley will build the walk from your current device location.',
      ),
      findsOneWidget,
    );

    final didPop = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(didPop, isTrue);
    expect(find.text('What do you want to do?'), findsOneWidget);
  });

  testWidgets('branch navigation preserves nested navigation state', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Build an adventure request'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Start casual. Riley will build the walk from your current device location.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    expect(
      find.text('Browse sample ideas for future ROVER adventures.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Start casual. Riley will build the walk from your current device location.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('creates and edits a complete adventure request', (tester) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(initialLocation: '/home/adventure-request'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('architecture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outdoor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create My Walk'));
    await tester.pumpAndSettle();

    expect(find.text('Route preview'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit request'));
    await tester.pumpAndSettle();
    expect(find.text('Adventure request'), findsOneWidget);
    expect(find.textContaining('Device location active:'), findsOneWidget);
  });

  testWidgets('adventure request validation is clear and friendly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(initialLocation: '/home/adventure-request'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '10');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create My Walk'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Give Riley at least 20 minutes so the ROAM does not feel rushed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('device location is the only adventure starting point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(initialLocation: '/home/adventure-request'));
    await tester.pumpAndSettle();

    expect(find.text('Starting point'), findsNothing);
    expect(find.text('Use device location'), findsNothing);
    expect(find.textContaining('Device location'), findsWidgets);
  });

  testWidgets('active ROAM exposes accessible critical controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(initialLocation: '/home/active-roam'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Stay aware of traffic'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Create live walk first'),
      findsOneWidget,
    );
    expect(find.textContaining('Current stop: Union Square'), findsOneWidget);
    expect(find.textContaining('Next Up: Lotta\'s Fountain'), findsOneWidget);
    expect(find.text('Rover voice'), findsOneWidget);
  });

  testWidgets('active ROAM explains live walk requirement', (tester) async {
    tester.view.physicalSize = const Size(430, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(initialLocation: '/home/active-roam'));
    await tester.pumpAndSettle();

    expect(find.text('Itinerary'), findsOneWidget);
    expect(
      find.text(
        'Create a live walk from your current location to start navigation.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Create live walk first'),
      findsOneWidget,
    );
  });

  testWidgets('not-found screen is reachable', (tester) async {
    await tester.pumpWidget(_app(initialLocation: '/missing-roam'));
    await tester.pumpAndSettle();

    expect(find.text('ROAM not found'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Go Home'), findsOneWidget);
  });
}

Widget _app({
  MemoryPreferencesRepository? repository,
  MemoryActiveRoamRepository? activeRoamRepository,
  String initialLocation = '/welcome',
}) {
  return RoverTestApp(
    preferencesRepository: repository ?? MemoryPreferencesRepository(),
    activeRoamRepository: activeRoamRepository,
    locationProvider: SimulatedLocationProvider(),
    initialLocation: initialLocation,
    key: UniqueKey(),
  );
}
