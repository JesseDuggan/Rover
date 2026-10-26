import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/accounts/account_library.dart';
import 'package:rover/src/accounts/account_library_screens.dart';
import 'package:rover/src/api/rover_api_config.dart';
import 'package:rover/src/preferences/rover_preferences.dart';
import 'package:rover/src/preferences/preferences_controller.dart';
import 'package:rover/src/preferences/preferences_repository.dart';
import 'package:rover/src/active_roam/active_roam_controller.dart';
import 'package:rover/src/active_roam/active_roam_session.dart';

class SavingLibrary extends FakeLibrary {
  SavingLibrary({this.cancel = false}) : super(loggedIn: false);
  final bool cancel;
  Map<String, dynamic>? saved;
  String? savedName;
  final requests = <String>[];
  @override
  Future<bool> signIn() async {
    loggedIn = !cancel;
    return loggedIn;
  }

  @override
  Future<void> rememberGuest(RoverPreferences preferences) async {}
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    requests.add('$method $path');
    return {'id': 'snapshot'};
  }

  @override
  Future<void> save(
    String kind,
    String id,
    String name,
    Map<String, dynamic> data, {
    int revision = 0,
    bool isDefault = false,
  }) async {
    saved = data;
    savedName = name;
  }
}

class SavingWalk extends ActiveRoamController {
  @override
  RoamSession get session =>
      RoamSession.empty().copyWith(apiWalkSessionId: 'walk-1');
}

class FakeLibrary extends AccountLibrary {
  FakeLibrary({this.loggedIn = true, this.records = const []})
    : super(config: const RoverApiConfig(baseUrl: 'https://example.com'));
  bool loggedIn;
  final List<LibraryItem> records;
  void endSession() {
    loggedIn = false;
    notifyListeners();
  }

  @override
  bool get signedIn => loggedIn;
  @override
  bool get enabled => true;
  @override
  Future<void> load() async {}
  @override
  Future<List<LibraryItem>> list(String kind) async => records;
}

class DeferredLogin extends FlutterAppAuth {
  final started = Completer<void>();
  final result = Completer<AuthorizationTokenResponse>();
  AuthorizationTokenRequest? request;
  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
    AuthorizationTokenRequest request,
  ) {
    this.request = request;
    started.complete();
    return result.future;
  }
}

class ConfiguredTestLibrary extends AccountLibrary {
  ConfiguredTestLibrary(FlutterAppAuth auth)
    : super(
        auth: auth,
        config: const RoverApiConfig(baseUrl: 'https://example.com'),
      );
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async => {
    'enabled': true,
    'issuer': 'https://cognito-idp.eu-west-1.amazonaws.com/test',
    'clientId': 'public-client',
    'redirectUri': 'ai.myrover.rover://oauthredirect',
    'profileLimit': 3,
    'walkLimit': 3,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['profiles', 'walks']) {
    testWidgets('Guest sign-in resumes saving $kind with confirmation', (
      tester,
    ) async {
      final library = SavingLibrary();
      final preferences = PreferencesController(MemoryPreferencesRepository());
      await preferences.save(const RoverPreferences(interests: ['history']));
      final active = SavingWalk();
      await tester.pumpWidget(
        PreferencesScope(
          controller: preferences,
          child: ActiveRoamScope(
            controller: active,
            child: MaterialApp(
              home: PersonalLibraryScreen(kind: kind, library: library),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          kind == 'profiles'
              ? 'Sign in to save preferences'
              : 'Sign in to save walk',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Nice discoveries');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(library.savedName, 'Nice discoveries');
      expect(find.text('Nice discoveries saved'), findsOneWidget);
      if (kind == 'profiles') {
        expect(library.saved!['interests'], ['history']);
      } else {
        expect(library.saved!['walk'], {'id': 'snapshot'});
        expect(library.requests, [
          'GET /api/walks/walk-1',
          'GET /api/walks/walk-1/route-story-pack',
        ]);
      }
      await tester.pumpWidget(const SizedBox());
      active.dispose();
      preferences.dispose();
      library.dispose();
    });
  }
  test('A late browser response cannot restore a signed-out session', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final auth = DeferredLogin();
    final library = ConfiguredTestLibrary(auth);
    final signingIn = library.signIn();
    await auth.started.future;
    await library.signOut();
    final rejected = expectLater(signingIn, throwsA(isA<LibraryException>()));
    auth.result.complete(
      AuthorizationTokenResponse(
        'access',
        'refresh',
        DateTime.now().add(const Duration(hours: 1)),
        null,
        'Bearer',
        ['openid'],
        null,
        null,
      ),
    );
    await rejected;
    expect(library.signedIn, isFalse);
    await library.load();
    expect(library.signedIn, isFalse);
    library.dispose();
  });
  test(
    'Hosted login persists securely and restores without passwords',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final auth = DeferredLogin();
      final library = ConfiguredTestLibrary(auth);
      final signingIn = library.signIn();
      await auth.started.future;
      auth.result.complete(
        AuthorizationTokenResponse(
          'access',
          'refresh',
          DateTime.now().add(const Duration(hours: 1)),
          null,
          'Bearer',
          ['openid'],
          null,
          null,
        ),
      );
      expect(await signingIn, isTrue);
      expect(auth.request!.scopes, ['openid', 'email']);
      expect(auth.request!.redirectUrl, 'ai.myrover.rover://oauthredirect');
      expect(auth.request!.clientSecret, isNull);
      final restored = ConfiguredTestLibrary(DeferredLogin());
      await restored.load();
      expect(restored.signedIn, isTrue);
      await restored.signOut();
      await library.load();
      expect(library.signedIn, isFalse);
      library.dispose();
      restored.dispose();
    },
  );
  testWidgets('Saved stories render narration variants and hide on sign-out', (
    tester,
  ) async {
    final library = FakeLibrary();
    const item = LibraryItem(
      id: 'walk',
      name: 'Palace walk',
      revision: 1,
      data: {
        'walk': {'routeSummary': 'Historic route', 'stops': <dynamic>[]},
        'stories': {
          'stories': [
            {
              'title': 'Palace history',
              'variants': [
                {
                  'length': 'Standard',
                  'narration': 'An archived, sourced story.',
                },
              ],
              'sources': [
                {'title': 'Archive', 'attribution': 'City archive'},
              ],
            },
          ],
        },
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SavedWalkDetails(item: item, library: library),
      ),
    );
    await tester.tap(find.text('Palace history'));
    await tester.pumpAndSettle();
    expect(find.text('An archived, sourced story.'), findsOneWidget);
    expect(find.text('City archive'), findsOneWidget);
    library.endSession();
    await tester.pumpAndSettle();
    expect(find.text('Palace history'), findsNothing);
  });
  test('Walking profiles exclude account and device fields', () {
    const preferences = RoverPreferences(
      firstName: 'Private',
      completedOnboarding: true,
      continueAsGuest: true,
      developmentApiBaseUrl: 'http://local',
      interests: ['History'],
    );
    final data = walkingProfileData(preferences);
    expect(data.keys, isNot(contains('firstName')));
    expect(data.keys, isNot(contains('developmentApiBaseUrl')));
    final applied = applyWalkingProfile(preferences, {
      ...data,
      'interests': ['Nature'],
      'firstName': 'Someone else',
      'completedOnboarding': false,
      'developmentApiBaseUrl': 'https://evil.example',
    });
    expect(applied.firstName, 'Private');
    expect(applied.completedOnboarding, isTrue);
    expect(applied.developmentApiBaseUrl, 'http://local');
    expect(applied.interests, ['Nature']);
  });
  test('Library IDs are persistent-compatible distinct UUIDs', () {
    final ids = List.generate(100, (_) => newLibraryId());
    expect(ids.toSet().length, 100);
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
    }
  });
  test(
    'Account requests reject insecure transport before sending tokens',
    () async {
      final library = AccountLibrary(
        config: const RoverApiConfig(baseUrl: 'http://localhost:5080'),
      );
      await expectLater(
        library.request(
          'GET',
          '/api/account-library/config',
          authenticated: false,
        ),
        throwsA(isA<LibraryException>()),
      );
      library.dispose();
    },
  );
  testWidgets('Guests see sign-in without account data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLibraryScreen(
          kind: 'profiles',
          library: FakeLibrary(loggedIn: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to save preferences'), findsOneWidget);
    expect(find.text('Save current preferences'), findsNothing);
  });
  for (final size in [const Size(390, 844), const Size(1100, 800)]) {
    testWidgets('Three-profile limit and layout at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records =
          [
                'City discoveries',
                'Restaurants and markets',
                'Nature and accessible paths',
              ].indexed
              .map(
                (e) => LibraryItem(
                  id: '${e.$1}',
                  name: e.$2,
                  data: const {},
                  revision: 1,
                  isDefault: e.$1 == 0,
                ),
              )
              .toList();
      await tester.pumpWidget(
        MaterialApp(
          home: PersonalLibraryScreen(
            kind: 'profiles',
            library: FakeLibrary(records: records),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 saved'), findsOneWidget);
      expect(find.text('Default profile'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save current preferences'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
