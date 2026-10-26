import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rover/src/accounts/account_library.dart';
import 'package:rover/src/api/rover_api_config.dart';
import 'package:rover/src/friends/friend_models.dart';
import 'package:rover/src/friends/friends_screen.dart';

const alice = {'id': 'a', 'username': 'alice', 'displayName': 'Alice'};
const bob = {'id': 'b', 'username': 'bob', 'displayName': 'Bob'};
final code = List.filled(48, 'a').join();

class FriendsLibrary extends AccountLibrary {
  FriendsLibrary()
    : super(config: const RoverApiConfig(baseUrl: 'https://example.com'));
  bool loggedIn = true;
  int generation = 0;
  Map<String, dynamic>? profile = alice;
  List<Map<String, dynamic>> connections = [];
  final calls = <String>[];
  Completer<dynamic>? delayed;
  bool failLookup = false;
  @override
  bool get signedIn => loggedIn;
  @override
  int get sessionGeneration => generation;
  @override
  Future<void> load() async {}
  void switchAccount() {
    generation++;
    loggedIn = false;
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    calls.add('$method $path');
    if (path == '/api/friends/state') {
      return {'profile': profile, 'connections': connections, 'blocked': []};
    }
    if (path.startsWith('/api/friends/lookup')) {
      if (failLookup) throw const LibraryException('Member unavailable.');
      return delayed != null
          ? delayed!.future
          : {'member': bob, 'status': 'none', 'requestId': null};
    }
    if (path == '/api/friends/profile') {
      profile = {...alice, ...body as Map<String, dynamic>};
      return profile;
    }
    if (path == '/api/friends/invites') {
      return {'code': code, 'expiresAtUtc': '2026-10-30T12:00:00Z'};
    }
    if (path == '/api/friends/invites/resolve') {
      return {'member': bob, 'status': 'none', 'requestId': null};
    }
    if (path == '/api/friends/requests') {
      connections = [
        {'member': bob, 'status': 'outgoing', 'requestId': 'request'},
      ];
    }
    if (path.endsWith('/accept')) {
      connections = [
        {'member': bob, 'status': 'friend', 'requestId': 'request'},
      ];
    }
    return null;
  }
}

void main() {
  test('Invitation parsing accepts only known routes and valid codes', () {
    expect(invitationCode(code, 'https://example.com'), code);
    expect(
      invitationCode('https://example.com/invite#$code', 'https://example.com'),
      code,
    );
    expect(
      invitationCode(
        'ai.myrover.rover.friends://friends/invite?code=$code',
        'https://example.com',
      ),
      code,
    );
    for (final value in [
      'https://other.com/invite#$code',
      'http://example.com/invite#$code',
      'ai.myrover.rover://oauthredirect?code=$code',
      'https://example.com/other#$code',
      'bad',
      'https:///invite#$code',
      'https:invite#$code',
      'https://someone@example.com/invite#$code',
    ]) {
      expect(invitationCode(value, 'https://example.com'), isNull);
    }
  });
  testWidgets('Sign-in is required and sign-out clears member data', (
    tester,
  ) async {
    final library = FriendsLibrary();
    await tester.pumpWidget(MaterialApp(home: FriendsScreen(library: library)));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    library.switchAccount();
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Sign in or create account'), findsOneWidget);
  });
  testWidgets('Profile creation needs explicit confirmation', (tester) async {
    final library = FriendsLibrary()..profile = null;
    await tester.pumpWidget(MaterialApp(home: FriendsScreen(library: library)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'Alice');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(library.calls.where((c) => c.startsWith('PUT')), isEmpty);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(library.calls, contains('PUT /api/friends/profile'));
  });
  testWidgets('Invitation review does not automatically send a request', (
    tester,
  ) async {
    final library = FriendsLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: FriendsScreen(library: library, invitation: code),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review invitation'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(library.calls, isNot(contains('POST /api/friends/requests')));
    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();
    expect(library.calls, contains('POST /api/friends/requests'));
  });
  testWidgets('Incoming request requires acceptance', (tester) async {
    final library = FriendsLibrary()
      ..connections = [
        {'member': bob, 'status': 'incoming', 'requestId': 'request'},
      ];
    await tester.pumpWidget(MaterialApp(home: FriendsScreen(library: library)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(
      library.calls,
      contains('POST /api/friends/requests/request/accept'),
    );
    await tester.tap(find.text('Friends').last);
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
  });
  testWidgets('Late lookup cannot expose data after account switch', (
    tester,
  ) async {
    final library = FriendsLibrary()..delayed = Completer<dynamic>();
    await tester.pumpWidget(
      MaterialApp(
        home: FriendsScreen(library: library, invitation: code),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Find member'));
    await tester.pump();
    library.switchAccount();
    library.delayed!.complete({'member': bob, 'status': 'none'});
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsNothing);
  });
  testWidgets('Failed lookup clears previous result', (tester) async {
    final library = FriendsLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: FriendsScreen(library: library, invitation: code),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Find member'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    library.failLookup = true;
    await tester.tap(find.byTooltip('Find member'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Member unavailable.'), findsOneWidget);
  });
  for (final width in [390.0, 844.0]) {
    testWidgets('Invitation QR fits $width viewport', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: FriendsScreen(library: FriendsLibrary())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create invitation'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
