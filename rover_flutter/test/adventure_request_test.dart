import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/adventure/adventure_request.dart';

void main() {
  test('validates available time as realistic', () {
    final shortRequest = AdventureRequest.empty.copyWith(
      availableMinutes: 10,
      startingPoint: 'near me',
      interests: const ['food'],
    );
    final longRequest = AdventureRequest.empty.copyWith(
      availableMinutes: 420,
      startingPoint: 'near me',
      interests: const ['food'],
    );

    expect(
      shortRequest.validate(),
      contains(
        'Give Riley at least 20 minutes so the ROAM does not feel rushed.',
      ),
    );
    expect(
      longRequest.validate(),
      contains('That is a big day. Keep this request under 6 hours for now.'),
    );
  });

  test('requires a starting point', () {
    final request = AdventureRequest.empty.copyWith(
      availableMinutes: 60,
      startingPoint: '',
      interests: const ['nature'],
    );

    expect(
      request.validate(),
      contains('Add a starting point, even if it is just "near me" for now.'),
    );
  });

  test('allows no interests only when surprise is enabled', () {
    final needsInterest = AdventureRequest.empty.copyWith(
      availableMinutes: 60,
      startingPoint: 'near me',
      interests: const [],
      surpriseMe: false,
    );
    final surprise = needsInterest.copyWith(surpriseMe: true);

    expect(
      needsInterest.validate(),
      contains('Pick at least one interest, or choose Surprise me.'),
    );
    expect(surprise.validate(), isEmpty);
    expect(surprise.isComplete, isTrue);
  });

  test('creates a complete request and mock suggestions', () {
    const request = AdventureRequest(
      availableMinutes: 90,
      startingPoint: 'Downtown library',
      routeMode: 'Accessible route',
      interests: ['architecture', 'food'],
      pace: 'Steady',
      routeShape: 'Loop route',
      companions: 'Family',
      environment: 'Outdoor',
      budget: 'Free-only',
      surpriseMe: false,
      naturalRequest: 'I have 90 minutes. Take me for a walk.',
    );

    expect(request.isComplete, isTrue);
    expect(createMockSuggestions(request), hasLength(3));
  });
}
