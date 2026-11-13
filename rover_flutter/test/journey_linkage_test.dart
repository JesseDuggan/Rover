import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/journey_identity.dart';
import 'package:rover/src/api/rover_api_client.dart';
import 'package:rover/src/api/rover_api_config.dart';

void main() {
  test('saved identity survives reopening, old replays get a new identity', () {
    final id = JourneyIdentity.create();
    expect(id, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(JourneyIdentity.restore(id), id);
    expect(JourneyIdentity.restore(null), isNot(id));
    expect(JourneyIdentity.restore('Perth'), isNot('Perth'));
    expect(JourneyIdentity.create(), isNot(id));
  });

  test(
    'research carries journey across requests and captures it before I/O',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String?>[];
      Map<String, dynamic>? areaRequest;
      server.listen((request) async {
        received.add(request.headers.value('X-Walkabout-Journey'));
        final body = await utf8.decoder.bind(request).join();
        if (request.uri.path == '/api/area-stories') {
          areaRequest = jsonDecode(body) as Map<String, dynamic>;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"stories": []}');
        await request.response.close();
      });
      final first = JourneyIdentity.create();
      final second = JourneyIdentity.create();
      final client = RoverApiClient(
        config: RoverApiConfig(baseUrl: 'http://127.0.0.1:${server.port}'),
        journeyId: first,
      );
      try {
        final pending = client.researchAreaStories(
          latitude: 44.9,
          longitude: -76.2,
          interests: ['history'],
          excludedTitles: [],
          contentDepth: 'deep',
          neighbourhoodContext: true,
        );
        client.journeyId = second;
        await pending;
        await client.getStoryImages([]);
        client.journeyId = null;
        await client.getHealth();
        expect(received, [first, second, null]);
        expect(areaRequest?['contentDepth'], 'deep');
        expect(areaRequest?['neighbourhoodContext'], true);
        expect(areaRequest?['interests'], ['history']);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );
}
