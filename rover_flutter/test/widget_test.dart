import 'support/location_fixtures.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rover/src/active_roam/active_roam_repository.dart';
import 'package:rover/src/adaptive_stories/route_story_question_dialog.dart';
import 'package:rover/src/app.dart';
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
    '/welcome': 'Your adventure, curated as you go.',
    '/onboarding': 'What should we call you?',
    '/home': 'Create your walk',
    '/home/adventure-request': 'Create your walk',
    '/home/route-preview': 'Create your walk',
    '/home/active-roam': 'Create your walk',
    '/home/stop-details': 'No stop selected.',
    '/roams': 'Saved walks',
    '/profile': 'Your interests',
    '/profile/settings': 'Your voice, narration, and walking preferences.',
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
    expect(find.text('What should we call you?'), findsOneWidget);

    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Continue as Guest'));
    await tester.pumpAndSettle();

    expect(find.text('Create your walk'), findsOneWidget);
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

    expect(find.text('Your interests'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'History'));
    await tester.tap(find.widgetWithText(FilterChip, 'Art'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Art'));
    final next = find.widgetWithText(FilledButton, 'Next');
    await tester.ensureVisible(next);
    await tester.tap(next);
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
    expect((await repository.load()).interests, ['history']);
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
    expect(find.text('What should we call you?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reset onboarding'));
    await tester.pumpAndSettle();

    expect(find.text('Walkabout'), findsOneWidget);
    expect((await repository.load()).completedOnboarding, isFalse);
  });

  testWidgets('every primary destination is reachable from the shell', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/home'));
    await tester.pumpAndSettle();

    expect(find.text('Create your walk'), findsOneWidget);

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Your itinerary'), findsOneWidget);

    await tester.tap(find.text('Stories'));
    await tester.pumpAndSettle();
    expect(find.text('Walk stories'), findsOneWidget);
    await tester.tap(find.text('Routes'));
    await tester.pumpAndSettle();
    expect(find.text('Route options'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Your interests'), findsOneWidget);
  });

  testWidgets('detail routes are reachable and Android back pops them', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    // Build the lazy row, then render its final scroll position before tapping.
    await tester.scrollUntilVisible(
      find.text('Stop details'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Stop details').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Stop details'));
    await tester.pumpAndSettle();
    expect(find.text('No stops in your current walk.'), findsOneWidget);

    final didPop = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(didPop, isTrue);
    await tester.scrollUntilVisible(
      find.text('Your interests'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Your interests').hitTestable(), findsOneWidget);
  });

  testWidgets('branch navigation preserves nested navigation state', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Stop details'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Stop details').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Stop details'));
    await tester.pumpAndSettle();
    expect(find.text('No stops in your current walk.'), findsOneWidget);

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Your itinerary'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('No stops in your current walk.'), findsOneWidget);
  });

  testWidgets('custom duration validates before applying', (tester) async {
    await tester.pumpWidget(_app(initialLocation: '/home'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Custom'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '10');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Enter 20 to 240 minutes'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '45');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('45 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create stays minimal with interests only in Profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(initialLocation: '/home/adventure-request'));
    await tester.pumpAndSettle();
    expect(find.text('Create your walk'), findsOneWidget);
    expect(find.text('What would you like to discover?'), findsOneWidget);
    expect(find.text('Time available'), findsOneWidget);
    expect(find.text('Create my walk'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('empty active ROAM has no demo and offers a new walk', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/home/active-roam'));
    await tester.pumpAndSettle();
    expect(find.text('Create your walk'), findsOneWidget);
    expect(find.textContaining('Union Square'), findsNothing);
    expect(find.text('Itinerary'), findsNothing);
    expect(find.text('Rover voice'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Create my walk'), findsOneWidget);
  });

  testWidgets('not-found screen is reachable', (tester) async {
    await tester.pumpWidget(_app(initialLocation: '/missing-roam'));
    await tester.pumpAndSettle();

    expect(find.text('Walk not found'), findsOneWidget);
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
