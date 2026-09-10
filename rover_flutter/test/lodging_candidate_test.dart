import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/camera_explorer/lodging_candidate.dart';

void main() {
  test('recognizes common lodging categories', () {
    expect(isLodgingCandidate(category: 'hotel', name: 'The Cove'), isTrue);
    expect(
      isLodgingCandidate(category: 'Bed and Breakfast', name: 'Harbour House'),
      isTrue,
    );
  });

  test('recognizes lodging terms in place names', () {
    expect(
      isLodgingCandidate(category: 'Place', name: 'The Cove Country Inn'),
      isTrue,
    );
  });

  test('does not classify stores and cafes as lodging', () {
    expect(
      isLodgingCandidate(category: 'Hardware Store', name: 'Home Hardware'),
      isFalse,
    );
    expect(
      isLodgingCandidate(category: 'Cafe', name: 'The Woodfired Cafe'),
      isFalse,
    );
  });
}
