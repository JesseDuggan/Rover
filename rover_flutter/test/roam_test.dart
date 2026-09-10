import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/adventure/adventure_request.dart';
import 'package:rover/src/adventure/roam.dart';

void main() {
  test('generated ordered stops are always sequential', () {
    final roam = MockRouteGenerationService.sanFrancisco90();

    expect(roam.orderedStops.map((stop) => stop.sequence), [1, 2, 3, 4]);
  });

  test('reordering cannot create duplicate sequence numbers', () {
    final reordered = MockRouteGenerationService.sanFrancisco90()
        .reorderStop(0, 3)
        .reorderStop(2, 1);

    expect(reordered.orderedStops.map((stop) => stop.sequence), [1, 2, 3, 4]);
    expect(
      reordered.orderedStops.map((stop) => stop.sequence).toSet(),
      hasLength(4),
    );
  });

  test('remove and replace recalculate time and distance', () {
    final service = const MockRouteGenerationService();
    final original = MockRouteGenerationService.familyNewYork();
    final removed = original.removeStop(original.stops.first.id);
    final replaced = removed.replaceStop(
      removed.stops.first.id,
      service.replacementFor(removed.stops.first),
    );

    expect(
      removed.totalEstimatedMinutes,
      lessThan(original.totalEstimatedMinutes),
    );
    expect(removed.distanceMiles, isNot(original.distanceMiles));
    expect(replaced.totalEstimatedMinutes, removed.totalEstimatedMinutes);
    expect(replaced.orderedStops.map((stop) => stop.sequence), [1, 2, 3]);
  });

  test('90 minute San Francisco sample fits its budget boundary', () {
    final request = AdventureRequest.empty.copyWith(
      availableMinutes: 90,
      startingPoint: 'San Francisco Ferry Building',
      interests: const ['history', 'food'],
    );
    final roam = const MockRouteGenerationService().generate(request);

    expect(roam.title, contains('Bayfront'));
    expect(roam.totalEstimatedMinutes, lessThanOrEqualTo(90));
    expect(roam.fitsBudget(90), isTrue);
  });

  test('short budget trims route until it fits', () {
    final request = AdventureRequest.empty.copyWith(
      availableMinutes: 30,
      startingPoint: 'near me',
      interests: const ['hidden gems'],
    );
    final roam = const MockRouteGenerationService().generate(request);

    expect(roam.totalEstimatedMinutes, lessThanOrEqualTo(30));
    expect(roam.stops.length, 2);
  });

  test('sample catalog includes family New York and local discovery walks', () {
    final nyc = MockRouteGenerationService.familyNewYork();
    final local = MockRouteGenerationService.shortLocalDiscovery();

    expect(nyc.summary, contains('kid-friendly NYC'));
    expect(local.title, 'Short local discovery walk');
    expect(nyc.orderedStops.map((stop) => stop.sequence), [1, 2, 3, 4]);
    expect(local.orderedStops.map((stop) => stop.sequence), [1, 2, 3]);
  });
}
