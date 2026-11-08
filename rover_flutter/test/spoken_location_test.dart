import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/voice/spoken_location.dart';

void main() {
  test('keeps named places and ordinary numbers in stories', () {
    expect(
      spokenLocationText('The theatre (43.6512, -79.4759) opened in 1927.'),
      'The theatre opened in 1927.',
    );
    expect(
      spokenLocationText('Walk 250 metres to 2190 Bloor Street West.'),
      'Walk 250 metres to 2190 Bloor Street West.',
    );
  });
  test('removes labelled and compass coordinate readings', () {
    for (final reading in [
      'latitude: 43.65 and longitude: -79.47',
      '43.65° N, 79.47° W',
      '43°39′04″N, 79°28′34″W',
    ]) {
      expect(
        spokenLocationText('Near $reading, the river bends.'),
        'Near this location, the river bends.',
      );
    }
  });
}
